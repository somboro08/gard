import assert from 'node:assert/strict';
import { after, before, describe, it } from 'node:test';
import { client, type Ctx, signup, start } from './helpers.js';

let ctx: Ctx;
let call: ReturnType<typeof client>;

before(async () => {
  ctx = await start();
  call = client(ctx.app);
});
after(async () => ctx.close());

const iso = (d: Date) => d.toISOString();
const dayRange = () => {
  const from = new Date(Date.now() - 24 * 3600_000);
  const to = new Date(Date.now() + 24 * 3600_000);
  return `from=${encodeURIComponent(iso(from))}&to=${encodeURIComponent(iso(to))}`;
};

async function newCenter(token: string, extra: object = {}) {
  const r = await call('POST', '/centers', token, {
    name: 'Parking école', location: 'Cotonou', guardHours: 24,
    tariff: { moto: 100, velo: 50, voiture: 500 }, ...extra,
  });
  assert.equal(r.status, 201);
  return r.body.center as { id: string };
}

describe('authentification', () => {
  it('inscrit, connecte et renvoie le profil', async () => {
    const reg = await call('POST', '/auth/register', undefined, {
      phone: '+229 01 97 00 00 01', name: 'Georges', password: 'motdepasse1',
    });
    assert.equal(reg.status, 201);
    assert.equal(reg.body.user.phone, '2290197000001');
    // même numéro écrit autrement → déjà pris
    const dup = await call('POST', '/auth/register', undefined, {
      phone: '0197000001', name: 'Autre', password: 'motdepasse1',
    });
    assert.equal(dup.status, 409);
    assert.equal(dup.body.error, 'phone_taken');

    const login = await call('POST', '/auth/login', undefined, { phone: '0197000001', password: 'motdepasse1' });
    assert.equal(login.status, 200);
    const me = await call('GET', '/auth/me', login.body.accessToken);
    assert.equal(me.body.user.name, 'Georges');
  });

  it('refuse un mauvais mot de passe, un numéro inconnu et un jeton absent', async () => {
    const bad = await call('POST', '/auth/login', undefined, { phone: '0197000001', password: 'faux-faux-1' });
    assert.equal(bad.status, 401);
    const unknown = await call('POST', '/auth/login', undefined, { phone: '0100000000', password: 'motdepasse1' });
    assert.equal(unknown.status, 401);
    assert.equal(unknown.body.message, bad.body.message); // même message : pas d'énumération
    assert.equal((await call('GET', '/centers')).status, 401);
    assert.equal((await call('GET', '/centers', 'jeton.invalide.x')).status, 401);
  });

  it('valide les champs', async () => {
    const r = await call('POST', '/auth/register', undefined, { phone: '12', name: 'X', password: 'court' });
    assert.equal(r.status, 400);
  });

  it('fait tourner le jeton de rafraîchissement et coupe la session si on le rejoue', async () => {
    const u = await signup(call);
    const r1 = await call('POST', '/auth/refresh', undefined, { refreshToken: u.refresh });
    assert.equal(r1.status, 200);
    assert.notEqual(r1.body.refreshToken, u.refresh);
    // Rejeu de l'ancien jeton : refusé, et le nouveau est révoqué aussi.
    assert.equal((await call('POST', '/auth/refresh', undefined, { refreshToken: u.refresh })).status, 401);
    assert.equal((await call('POST', '/auth/refresh', undefined, { refreshToken: r1.body.refreshToken })).status, 401);
  });

  it('déconnecte (révoque la session)', async () => {
    const u = await signup(call);
    assert.equal((await call('POST', '/auth/logout', undefined, { refreshToken: u.refresh })).status, 204);
    assert.equal((await call('POST', '/auth/refresh', undefined, { refreshToken: u.refresh })).status, 401);
  });
});

describe('centres et agents', () => {
  it('crée un centre (idempotent avec un id client) et le liste', async () => {
    const u = await signup(call);
    const id = '11111111-1111-4111-8111-111111111111';
    const a = await call('POST', '/centers', u.token, { id, name: 'C1', guardHours: 12, tariff: { moto: 200 } });
    assert.equal(a.status, 201);
    assert.equal(a.body.center.tariff.moto, 200);
    assert.equal(a.body.center.tariff.velo, 0);
    assert.equal(a.body.center.role, 'owner');
    const again = await call('POST', '/centers', u.token, { id, name: 'C1', guardHours: 12 });
    assert.equal(again.status, 200); // rejeu : pas de doublon
    assert.equal((await call('GET', '/centers', u.token)).body.centers.length, 1);

    // Un autre utilisateur ne peut pas squatter cet identifiant.
    const other = await signup(call);
    assert.equal((await call('POST', '/centers', other.token, { id, name: 'X', guardHours: 1 })).status, 409);
  });

  it('cloisonne les centres entre utilisateurs (404, pas 403)', async () => {
    const a = await signup(call);
    const b = await signup(call);
    const c = await newCenter(a.token);
    assert.equal((await call('GET', `/centers/${c.id}`, b.token)).status, 404);
    assert.equal((await call('GET', `/centers/${c.id}/vehicles/active`, b.token)).status, 404);
    assert.equal((await call('PATCH', `/centers/${c.id}`, b.token, { name: 'Pirate' })).status, 404);
    assert.equal((await call('DELETE', `/centers/${c.id}`, b.token)).status, 404);
    assert.equal((await call('GET', '/centers', b.token)).body.centers.length, 0);
  });

  it('gère les agents : ajout par numéro, droits limités, dernier propriétaire protégé', async () => {
    const owner = await signup(call, 'Patron');
    const agent = await signup(call, 'Agent');
    const c = await newCenter(owner.token);

    assert.equal((await call('POST', `/centers/${c.id}/members`, owner.token, { phone: '0100000999' })).status, 404);
    const add = await call('POST', `/centers/${c.id}/members`, owner.token, { phone: agent.phone });
    assert.equal(add.status, 201);
    assert.equal(add.body.member.role, 'agent');

    // L'agent voit le centre mais ne peut ni le modifier, ni le supprimer, ni inviter.
    assert.equal((await call('GET', `/centers/${c.id}`, agent.token)).body.center.role, 'agent');
    assert.equal((await call('PATCH', `/centers/${c.id}`, agent.token, { name: 'Nouveau' })).status, 403);
    assert.equal((await call('DELETE', `/centers/${c.id}`, agent.token)).status, 403);
    assert.equal((await call('POST', `/centers/${c.id}/members`, agent.token, { phone: owner.phone })).status, 403);

    // Le propriétaire modifie le tarif.
    const p = await call('PATCH', `/centers/${c.id}`, owner.token, { tariff: { moto: 300 } });
    assert.equal(p.body.center.tariff.moto, 300);
    assert.equal(p.body.center.tariff.velo, 50);

    // Dernier propriétaire : ni retrait, ni rétrogradation.
    assert.equal((await call('DELETE', `/centers/${c.id}/members/${owner.id}`, owner.token)).status, 400);
    const demote = await call('POST', `/centers/${c.id}/members`, owner.token, { phone: owner.phone, role: 'agent' });
    assert.equal(demote.status, 400);

    // L'agent peut quitter le centre ; il n'en voit plus rien.
    assert.equal((await call('DELETE', `/centers/${c.id}/members/${agent.id}`, agent.token)).status, 204);
    assert.equal((await call('GET', `/centers/${c.id}`, agent.token)).status, 404);
  });
});

describe('véhicules', () => {
  it('enregistre un dépôt avec tarif, échéance et code à 6 chiffres', async () => {
    const u = await signup(call);
    const c = await newCenter(u.token, { guardHours: 48 });
    const r = await call('POST', `/centers/${c.id}/vehicles`, u.token, {
      plate: 'ab-1234  rb', type: 'moto', ownerName: 'Georges', ownerPhone: '0197000000',
    });
    assert.equal(r.status, 201);
    const v = r.body.vehicle;
    assert.match(v.code, /^\d{6}$/);
    assert.equal(v.plate, 'AB 1234 RB');
    assert.equal(v.price, 100); // tarif moto du centre
    assert.equal(v.paidAmount, 0);
    const hours = (Date.parse(v.dueAt) - Date.parse(v.depositedAt)) / 3600_000;
    assert.equal(hours, 48);
  });

  it('rejoue un dépôt hors-ligne sans doublon', async () => {
    const u = await signup(call);
    const c = await newCenter(u.token);
    const id = '22222222-2222-4222-8222-222222222222';
    const body = { id, type: 'velo', ownerName: 'Awa', depositedAt: iso(new Date(Date.now() - 3600_000)) };
    const a = await call('POST', `/centers/${c.id}/vehicles`, u.token, body);
    const b = await call('POST', `/centers/${c.id}/vehicles`, u.token, body);
    assert.equal(a.status, 201);
    assert.equal(b.status, 200);
    assert.equal(a.body.vehicle.code, b.body.vehicle.code);
    assert.equal((await call('GET', `/centers/${c.id}/vehicles/active`, u.token)).body.vehicles.length, 1);
    // Date absurde refusée.
    const old = await call('POST', `/centers/${c.id}/vehicles`, u.token, {
      type: 'velo', ownerName: 'X', depositedAt: '2001-01-01T00:00:00Z',
    });
    assert.equal(old.status, 409);
  });

  it("garde le code et l'échéance fournis par l'appli hors-ligne, sinon réattribue", async () => {
    const u = await signup(call);
    const c = await newCenter(u.token);
    const dep = new Date(Date.now() - 2 * 3600_000);
    const due = new Date(dep.getTime() + 5 * 3600_000);
    const a = await call('POST', `/centers/${c.id}/vehicles`, u.token, {
      type: 'moto', ownerName: 'A', code: '123456', depositedAt: iso(dep), dueAt: iso(due),
    });
    assert.equal(a.status, 201);
    assert.equal(a.body.vehicle.code, '123456');
    assert.equal(Date.parse(a.body.vehicle.dueAt), due.getTime());
    // Même code demandé par un autre appareil (autre véhicule) : réattribué.
    const b = await call('POST', `/centers/${c.id}/vehicles`, u.token, { type: 'moto', ownerName: 'B', code: '123456' });
    assert.equal(b.status, 201);
    assert.notEqual(b.body.vehicle.code, '123456');
    // Échéance antérieure au dépôt : refusée.
    const bad = await call('POST', `/centers/${c.id}/vehicles`, u.token, {
      type: 'moto', ownerName: 'C', depositedAt: iso(dep), dueAt: iso(new Date(dep.getTime() - 1000)),
    });
    assert.equal(bad.status, 409);
  });

  it('génère des codes uniques parmi les véhicules en garde', async () => {
    const u = await signup(call);
    const c = await newCenter(u.token);
    const codes = new Set<string>();
    for (let i = 0; i < 25; i++) {
      const r = await call('POST', `/centers/${c.id}/vehicles`, u.token, { type: 'moto', ownerName: `N${i}` });
      codes.add(r.body.vehicle.code);
    }
    assert.equal(codes.size, 25);
  });

  it('retrouve par code, par plaque et par recherche (sans injection de motif)', async () => {
    const u = await signup(call);
    const c = await newCenter(u.token);
    const a = (await call('POST', `/centers/${c.id}/vehicles`, u.token, {
      plate: 'AB 1234 RB', type: 'moto', ownerName: 'Georges Somboro',
    })).body.vehicle;
    await call('POST', `/centers/${c.id}/vehicles`, u.token, { plate: 'ZZ 9999 CD', type: 'moto', ownerName: 'Awa' });

    const byCode = await call('GET', `/centers/${c.id}/vehicles/by-code/${a.code}`, u.token);
    assert.equal(byCode.body.vehicle.id, a.id);
    assert.equal((await call('GET', `/centers/${c.id}/vehicles/by-code/000000`, u.token)).status, 404);
    assert.equal((await call('GET', `/centers/${c.id}/vehicles/by-code/12`, u.token)).status, 400);

    const byPlate = await call('GET', `/centers/${c.id}/vehicles/by-plate/ab-1234-rb`, u.token);
    assert.equal(byPlate.body.vehicles.length, 1);

    const s1 = await call('GET', `/centers/${c.id}/vehicles/search?q=somboro`, u.token);
    assert.equal(s1.body.vehicles.length, 1);
    const s2 = await call('GET', `/centers/${c.id}/vehicles/search?q=${encodeURIComponent('1234')}`, u.token);
    assert.equal(s2.body.vehicles.length, 1);
    // « % » est cherché comme un caractère, il ne correspond pas à tout.
    const s3 = await call('GET', `/centers/${c.id}/vehicles/search?q=${encodeURIComponent('%')}`, u.token);
    assert.equal(s3.body.vehicles.length, 0);
  });

  it('ne trouve pas un code dans le centre d\'un autre', async () => {
    const a = await signup(call);
    const b = await signup(call);
    const ca = await newCenter(a.token);
    const cb = await newCenter(b.token);
    const v = (await call('POST', `/centers/${ca.id}/vehicles`, a.token, { type: 'moto', ownerName: 'X' })).body.vehicle;
    assert.equal((await call('GET', `/centers/${cb.id}/vehicles/by-code/${v.code}`, b.token)).status, 404);
    assert.equal((await call('GET', `/vehicles/${v.id}`, b.token)).status, 404);
    assert.equal((await call('POST', `/vehicles/${v.id}/collect`, b.token, { pickupCheck: 'exact', ticketVerified: true })).status, 404);
  });

  it('remet un véhicule une seule fois et journalise', async () => {
    const u = await signup(call);
    const c = await newCenter(u.token);
    const v = (await call('POST', `/centers/${c.id}/vehicles`, u.token, { type: 'moto', ownerName: 'X' })).body.vehicle;
    const ok = await call('POST', `/vehicles/${v.id}/collect`, u.token, { pickupCheck: 'close', ticketVerified: true });
    assert.equal(ok.status, 200);
    assert.ok(ok.body.vehicle.collectedAt);
    assert.equal(ok.body.vehicle.pickupCheck, 'close');
    const twice = await call('POST', `/vehicles/${v.id}/collect`, u.token, { pickupCheck: 'exact', ticketVerified: true });
    assert.equal(twice.status, 409);
    const log = await ctx.db.query(`SELECT action, details FROM audit_log WHERE entity_id = $1`, [v.id]);
    assert.equal(log.rows[0].action, 'vehicle.collect');
    assert.equal(log.rows[0].details.unpaid, 100);
    // Un code libéré peut être réutilisé : plus dans les « actifs ».
    assert.equal((await call('GET', `/centers/${c.id}/vehicles/active`, u.token)).body.vehicles.length, 0);
  });

  it('modifie un véhicule et réserve la suppression au propriétaire', async () => {
    const owner = await signup(call);
    const agent = await signup(call);
    const c = await newCenter(owner.token);
    await call('POST', `/centers/${c.id}/members`, owner.token, { phone: agent.phone });
    const v = (await call('POST', `/centers/${c.id}/vehicles`, agent.token, { type: 'moto', ownerName: 'X', plate: 'AA 1 BB' })).body.vehicle;

    const p = await call('PATCH', `/vehicles/${v.id}`, agent.token, { ownerName: 'Y', plate: 'cc-22-dd' });
    assert.equal(p.body.vehicle.ownerName, 'Y');
    assert.equal(p.body.vehicle.plate, 'CC 22 DD');

    assert.equal((await call('DELETE', `/vehicles/${v.id}`, agent.token)).status, 403);
    assert.equal((await call('DELETE', `/vehicles/${v.id}`, owner.token)).status, 204);
    assert.equal((await call('GET', `/vehicles/${v.id}`, owner.token)).status, 404);

    const ch = await call('GET', `/centers/${c.id}/changes`, owner.token);
    assert.deepEqual(ch.body.deletedVehicleIds, [v.id]);
  });
});

describe('paiements et revenus', () => {
  it('encaisse en plusieurs fois, refuse le trop-perçu, calcule le reste à encaisser', async () => {
    const u = await signup(call);
    const c = await newCenter(u.token);
    const v = (await call('POST', `/centers/${c.id}/vehicles`, u.token, { type: 'voiture', ownerName: 'X', plate: 'AB 1 CD' })).body.vehicle;
    assert.equal(v.price, 500);
    assert.equal((await call('GET', `/centers/${c.id}/pending`, u.token)).body.pending, 500);

    const p1 = await call('POST', `/vehicles/${v.id}/payments`, u.token, { amount: 200 });
    assert.equal(p1.status, 201);
    assert.equal((await call('GET', `/vehicles/${v.id}`, u.token)).body.vehicle.paidAmount, 200);
    assert.equal((await call('GET', `/centers/${c.id}/pending`, u.token)).body.pending, 300);

    const over = await call('POST', `/vehicles/${v.id}/payments`, u.token, { amount: 400 });
    assert.equal(over.status, 409);
    assert.equal(over.body.error, 'overpayment');
    assert.equal((await call('POST', `/vehicles/${v.id}/payments`, u.token, { amount: 0 })).status, 400);
    assert.equal((await call('POST', `/vehicles/${v.id}/payments`, u.token, { amount: -5 })).status, 400);

    assert.equal((await call('POST', `/vehicles/${v.id}/payments`, u.token, { amount: 300 })).status, 201);
    assert.equal((await call('GET', `/centers/${c.id}/pending`, u.token)).body.pending, 0);

    const list = await call('GET', `/centers/${c.id}/payments?${dayRange()}`, u.token);
    assert.equal(list.body.payments.length, 2);
    assert.equal(list.body.payments.reduce((s: number, p: { amount: number }) => s + p.amount, 0), 500);
    assert.equal(list.body.payments[0].plate, 'AB 1 CD');
    assert.equal(list.body.payments[0].vehicleType, 'voiture');
  });

  it('rejoue un encaissement hors-ligne sans le compter deux fois', async () => {
    const u = await signup(call);
    const c = await newCenter(u.token);
    const v = (await call('POST', `/centers/${c.id}/vehicles`, u.token, { type: 'moto', ownerName: 'X' })).body.vehicle;
    const id = '33333333-3333-4333-8333-333333333333';
    assert.equal((await call('POST', `/vehicles/${v.id}/payments`, u.token, { id, amount: 60 })).status, 201);
    assert.equal((await call('POST', `/vehicles/${v.id}/payments`, u.token, { id, amount: 60 })).status, 200);
    assert.equal((await call('GET', `/vehicles/${v.id}`, u.token)).body.vehicle.paidAmount, 60);
  });

  it('ne laisse pas deux encaissements simultanés dépasser le prix', async () => {
    const u = await signup(call);
    const c = await newCenter(u.token);
    const v = (await call('POST', `/centers/${c.id}/vehicles`, u.token, { type: 'moto', ownerName: 'X' })).body.vehicle;
    const rs = await Promise.all(
      Array.from({ length: 5 }, () => call('POST', `/vehicles/${v.id}/payments`, u.token, { amount: 100 })),
    );
    assert.equal(rs.filter((r) => r.status === 201).length, 1);
    assert.equal((await call('GET', `/vehicles/${v.id}`, u.token)).body.vehicle.paidAmount, 100);
  });

  it('cloisonne les paiements entre centres', async () => {
    const a = await signup(call);
    const b = await signup(call);
    const ca = await newCenter(a.token);
    const v = (await call('POST', `/centers/${ca.id}/vehicles`, a.token, { type: 'moto', ownerName: 'X' })).body.vehicle;
    assert.equal((await call('POST', `/vehicles/${v.id}/payments`, b.token, { amount: 10 })).status, 404);
    assert.equal((await call('GET', `/centers/${ca.id}/payments?${dayRange()}`, b.token)).status, 404);
  });
});

describe('synchronisation', () => {
  it('renvoie uniquement ce qui a changé depuis un instant donné', async () => {
    const u = await signup(call);
    const c = await newCenter(u.token);
    const v1 = (await call('POST', `/centers/${c.id}/vehicles`, u.token, { type: 'moto', ownerName: 'A' })).body.vehicle;
    const first = await call('GET', `/centers/${c.id}/changes`, u.token);
    assert.equal(first.body.vehicles.length, 1);

    await new Promise((r) => setTimeout(r, 15));
    const v2 = (await call('POST', `/centers/${c.id}/vehicles`, u.token, { type: 'moto', ownerName: 'B' })).body.vehicle;
    await call('POST', `/vehicles/${v2.id}/payments`, u.token, { amount: 50 });
    const next = await call('GET', `/centers/${c.id}/changes?since=${encodeURIComponent(first.body.serverTime)}`, u.token);
    assert.deepEqual(next.body.vehicles.map((v: { id: string }) => v.id), [v2.id]);
    assert.equal(next.body.payments.length, 1);
    assert.ok(!next.body.vehicles.some((v: { id: string }) => v.id === v1.id));
  });
});

describe('divers', () => {
  it('répond sur /health et renvoie un 404 JSON pour une route inconnue', async () => {
    assert.equal((await call('GET', '/health')).body.ok, true);
    const r = await call('GET', '/nimporte');
    assert.equal(r.status, 404);
    assert.equal(r.body.error, 'not_found');
  });

  it('limite les tentatives de connexion', async () => {
    const strict = await start({ rateLimit: true });
    try {
      const c = client(strict.app);
      let last = 0;
      for (let i = 0; i < 12; i++) {
        last = (await c('POST', '/auth/login', undefined, { phone: '0197000001', password: 'x-x-x-x-x' })).status;
      }
      assert.equal(last, 429);
    } finally {
      await strict.close();
    }
  });
});
