import assert from 'node:assert/strict';
import { generateKeyPairSync, sign } from 'node:crypto';
import { after, before, describe, it } from 'node:test';
import { enrollMessage, pickupMessage, verifyEd25519 } from '../src/pickup.js';
import { client, type Ctx, signup, start } from './helpers.js';

let ctx: Ctx;
let call: ReturnType<typeof client>;

before(async () => {
  ctx = await start();
  call = client(ctx.app);
});
after(async () => ctx.close());

/** Un « téléphone de client » : paire de clés Ed25519, clé publique en base64url brut. */
function phoneKey() {
  const { publicKey, privateKey } = generateKeyPairSync('ed25519');
  const pub = (publicKey.export({ format: 'der', type: 'spki' }) as Buffer).subarray(12).toString('base64url');
  return { pub, sign: (m: string) => sign(null, Buffer.from(m), privateKey).toString('base64url') };
}
const nonce = () => Buffer.from(Array.from({ length: 16 }, () => Math.floor(Math.random() * 256))).toString('base64url');

async function setup() {
  const u = await signup(call);
  const c = (await call('POST', '/centers', u.token, { name: 'C', guardHours: 24, tariff: { moto: 0 } })).body.center;
  const v = (await call('POST', `/centers/${c.id}/vehicles`, u.token, { type: 'moto', ownerName: 'Client' })).body.vehicle;
  return { u, c, v };
}

describe('vérification de signature Ed25519 (vecteur partagé avec Dart)', () => {
  const vec = {
    pub: 'A6EHv_POEL4dcN0Y50vAmWfk1jCbpQ1fHdyGZBJVMbg',
    vid: '11111111-2222-4333-8444-555555555555',
    nonce: 'AAECAwQFBgcICQoLDA0ODw',
    enroll: '-NBvMOPCtF2zxi4IkdbwDHtWIx7VeFcuv9_kTutZnbx9o5KgzV2MiBbPokzLMJ8n46QjTOqNwe8qEZC3Pw7dDA',
    pickup: 'NtlJaRcFP_lxp4oLCPQY2jXb4Z_Ip7BNJ6ZBLvAkKh9SMtXFDLzQzkdC6qosayv5JgHs3vtvpUzXDARAQmmbAQ',
  };
  it('accepte les bonnes signatures et refuse le reste', () => {
    assert.ok(verifyEd25519(vec.pub, enrollMessage(vec.vid, vec.nonce), vec.enroll));
    assert.ok(verifyEd25519(vec.pub, pickupMessage(vec.vid, vec.nonce), vec.pickup));
    // Une signature d'enrôlement ne vaut pas preuve de remise (et inversement).
    assert.ok(!verifyEd25519(vec.pub, pickupMessage(vec.vid, vec.nonce), vec.enroll));
    assert.ok(!verifyEd25519(vec.pub, pickupMessage('autre-id', vec.nonce), vec.pickup));
    assert.ok(!verifyEd25519(vec.pub, pickupMessage(vec.vid, 'AAAAAAAAAAAAAAAAAAAAAA'), vec.pickup));
    assert.ok(!verifyEd25519('court', 'x', vec.pickup));
  });
});

describe('remise sécurisée par clé', () => {
  it('enrôle la clé du client, rejeu accepté, autre clé refusée', async () => {
    const { u, v } = await setup();
    const k = phoneKey();
    const n = nonce();
    const body = { ownerKey: k.pub, nonce: n, sig: k.sign(enrollMessage(v.id, n)) };
    const r = await call('POST', `/vehicles/${v.id}/owner-key`, u.token, body);
    assert.equal(r.status, 200, JSON.stringify(r.body));
    assert.equal(r.body.vehicle.ownerKey, k.pub);
    assert.equal((await call('POST', `/vehicles/${v.id}/owner-key`, u.token, body)).status, 200);

    const k2 = phoneKey();
    const n2 = nonce();
    const other = await call('POST', `/vehicles/${v.id}/owner-key`, u.token, {
      ownerKey: k2.pub, nonce: n2, sig: k2.sign(enrollMessage(v.id, n2)),
    });
    assert.equal(other.status, 409);
    assert.equal(other.body.error, 'key_already_set');
  });

  it("refuse un enrôlement dont la signature n'est pas celle de la clé", async () => {
    const { u, v } = await setup();
    const k = phoneKey();
    const thief = phoneKey();
    const n = nonce();
    const r = await call('POST', `/vehicles/${v.id}/owner-key`, u.token, {
      ownerKey: k.pub, nonce: n, sig: thief.sign(enrollMessage(v.id, n)),
    });
    assert.equal(r.status, 422);
    assert.equal(r.body.error, 'invalid_proof');
    // Signature faite pour un autre véhicule : refusée aussi.
    const other = (await call('POST', `/centers/${v.centerId}/vehicles`, u.token, { type: 'moto', ownerName: 'Z' })).body.vehicle;
    const r2 = await call('POST', `/vehicles/${v.id}/owner-key`, u.token, {
      ownerKey: k.pub, nonce: n, sig: k.sign(enrollMessage(other.id, n)),
    });
    assert.equal(r2.status, 422);
  });

  it('un autre centre ne peut pas enrôler (404)', async () => {
    const { v } = await setup();
    const stranger = await signup(call);
    const k = phoneKey();
    const n = nonce();
    const r = await call('POST', `/vehicles/${v.id}/owner-key`, stranger.token, {
      ownerKey: k.pub, nonce: n, sig: k.sign(enrollMessage(v.id, n)),
    });
    assert.equal(r.status, 404);
  });

  it('remise avec preuve valide : méthode « key » ; preuve fausse : 422 et le véhicule reste en garde', async () => {
    const { u, v } = await setup();
    const k = phoneKey();
    const n = nonce();
    await call('POST', `/vehicles/${v.id}/owner-key`, u.token, { ownerKey: k.pub, nonce: n, sig: k.sign(enrollMessage(v.id, n)) });

    const n2 = nonce();
    const bad = await call('POST', `/vehicles/${v.id}/collect`, u.token, {
      pickupCheck: 'exact', ticketVerified: true, pickupMethod: 'key',
      proof: { nonce: n2, sig: phoneKey().sign(pickupMessage(v.id, n2)) },
    });
    assert.equal(bad.status, 422);
    assert.equal((await call('GET', `/vehicles/${v.id}`, u.token)).body.vehicle.collectedAt, null);

    const noProof = await call('POST', `/vehicles/${v.id}/collect`, u.token, {
      pickupCheck: 'exact', ticketVerified: true, pickupMethod: 'key',
    });
    assert.equal(noProof.status, 422);

    // Une signature d'enrôlement ne peut pas servir de preuve de remise.
    const replayEnroll = await call('POST', `/vehicles/${v.id}/collect`, u.token, {
      pickupCheck: 'exact', ticketVerified: true, pickupMethod: 'key',
      proof: { nonce: n, sig: k.sign(enrollMessage(v.id, n)) },
    });
    assert.equal(replayEnroll.status, 422);

    const n3 = nonce();
    const ok = await call('POST', `/vehicles/${v.id}/collect`, u.token, {
      pickupCheck: 'exact', ticketVerified: true, pickupMethod: 'key',
      proof: { nonce: n3, sig: k.sign(pickupMessage(v.id, n3)) },
    });
    assert.equal(ok.status, 200, JSON.stringify(ok.body));
    assert.equal(ok.body.vehicle.pickupMethod, 'key');
    const log = await ctx.db.query(`SELECT details FROM audit_log WHERE action = 'vehicle.collect' AND entity_id = $1`, [v.id]);
    assert.equal(log.rows[0].details.pickupMethod, 'key');
  });

  it("« key » sans clé enrôlée est refusé ; la remise manuelle reste possible et tracée", async () => {
    const { u, v } = await setup();
    const n = nonce();
    const k = phoneKey();
    const noKey = await call('POST', `/vehicles/${v.id}/collect`, u.token, {
      pickupCheck: 'exact', ticketVerified: true, pickupMethod: 'key',
      proof: { nonce: n, sig: k.sign(pickupMessage(v.id, n)) },
    });
    assert.equal(noKey.status, 422);
    assert.equal(noKey.body.error, 'no_key');

    const manual = await call('POST', `/vehicles/${v.id}/collect`, u.token, { pickupCheck: 'skipped', ticketVerified: false });
    assert.equal(manual.status, 200);
    assert.equal(manual.body.vehicle.pickupMethod, 'manual');
  });

  it('la clé enrôlée apparaît dans le flux /changes pour les autres appareils', async () => {
    const { u, c, v } = await setup();
    const k = phoneKey();
    const n = nonce();
    await call('POST', `/vehicles/${v.id}/owner-key`, u.token, { ownerKey: k.pub, nonce: n, sig: k.sign(enrollMessage(v.id, n)) });
    const ch = await call('GET', `/centers/${c.id}/changes?since=1970-01-01T00:00:00Z`, u.token);
    assert.equal(ch.body.vehicles.find((x: { id: string }) => x.id === v.id).ownerKey, k.pub);
  });
});
