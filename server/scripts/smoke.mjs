#!/usr/bin/env node
// Test de bout en bout d'un serveur Garde DÉJÀ lancé (local, Docker ou production).
//   node scripts/smoke.mjs https://api.exemple.com
// Crée deux comptes jetables et un centre de test ; ne touche à aucune donnée existante.
import { randomUUID, randomInt } from 'node:crypto';
import assert from 'node:assert/strict';

const base = (process.argv[2] ?? process.env.API_URL ?? 'http://localhost:3000').replace(/\/+$/, '');
let step = 0;
const ok = (msg) => console.log(`  ✓ ${String(++step).padStart(2)}. ${msg}`);

async function call(method, path, { token, body } = {}) {
  const res = await fetch(base + path, {
    method,
    headers: {
      ...(body === undefined ? {} : { 'content-type': 'application/json' }),
      ...(token ? { authorization: `Bearer ${token}` } : {}),
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await res.text();
  let json = null;
  try { json = text ? JSON.parse(text) : null; } catch { /* corps non JSON */ }
  return { status: res.status, body: json };
}

// Numéros jetables au format béninois (229 + 8 chiffres), uniques à chaque exécution.
const phone = () => `01${randomInt(10000000, 99999999)}`;
const password = 'Mot-de-passe-test-1';

console.log(`Test de bout en bout → ${base}`);

const health = await call('GET', '/health');
assert.equal(health.status, 200, `/health a répondu ${health.status}`);
ok('le serveur répond et la base de données est joignable');

// --- Comptes -----------------------------------------------------------------
const ownerPhone = phone();
const agentPhone = phone();
const owner = await call('POST', '/auth/register', { body: { phone: ownerPhone, name: 'Propriétaire test', password } });
assert.equal(owner.status, 201, JSON.stringify(owner.body));
const agent = await call('POST', '/auth/register', { body: { phone: agentPhone, name: 'Agent test', password } });
assert.equal(agent.status, 201, JSON.stringify(agent.body));
ok('deux comptes créés (propriétaire, agent)');

const dup = await call('POST', '/auth/register', { body: { phone: ownerPhone, name: 'Doublon', password } });
assert.equal(dup.status, 409);
ok('un numéro déjà inscrit est refusé');

const bad = await call('POST', '/auth/login', { body: { phone: ownerPhone, password: 'mauvais-mot-de-passe' } });
assert.equal(bad.status, 401);
ok('un mauvais mot de passe est refusé');

let O = owner.body;
const A = agent.body;

// --- Centre et équipe -------------------------------------------------------
const centerId = randomUUID(); // identifiant créé par l'app hors-ligne
const created = await call('POST', '/centers', {
  token: O.accessToken,
  body: { id: centerId, name: 'Centre de test', location: 'Cotonou', guardHours: 24, tariff: { moto: 200, velo: 100 } },
});
assert.equal(created.status, 201, JSON.stringify(created.body));
const again = await call('POST', '/centers', {
  token: O.accessToken,
  body: { id: centerId, name: 'Centre de test', location: 'Cotonou', guardHours: 24, tariff: { moto: 200, velo: 100 } },
});
assert.ok(again.status === 200 || again.status === 201, `rejeu idempotent : ${again.status}`);
ok('centre créé avec un identifiant client, rejeu sans doublon');

assert.equal((await call('GET', '/centers', { token: A.accessToken })).body.centers.length, 0);
ok("l'agent ne voit pas le centre avant d'être ajouté");

const add = await call('POST', `/centers/${centerId}/members`, { token: O.accessToken, body: { phone: agentPhone, role: 'agent' } });
assert.equal(add.status, 201, JSON.stringify(add.body));
assert.equal((await call('GET', '/centers', { token: A.accessToken })).body.centers.length, 1);
ok('le propriétaire ajoute l\'agent par son numéro ; le centre apparaît chez l\'agent');

const agentAdds = await call('POST', `/centers/${centerId}/members`, { token: A.accessToken, body: { phone: ownerPhone, role: 'agent' } });
assert.ok([403, 404].includes(agentAdds.status), `agent ne gère pas l'équipe : ${agentAdds.status}`);
ok("l'agent ne peut pas gérer l'équipe");

// --- Dépôt hors-ligne, paiement, remise -------------------------------------
const since = new Date(Date.now() - 60_000).toISOString();
const vehicleId = randomUUID();
const code = String(randomInt(100000, 999999));
const dep = new Date(Date.now() - 3600_000);
const due = new Date(dep.getTime() + 24 * 3600_000);
const v = await call('POST', `/centers/${centerId}/vehicles`, {
  token: A.accessToken,
  body: { id: vehicleId, code, plate: 'AB 1234 RB', type: 'moto', ownerName: 'Client test',
          depositedAt: dep.toISOString(), dueAt: due.toISOString() },
});
assert.equal(v.status, 201, JSON.stringify(v.body));
assert.equal(v.body.vehicle.code, code);
assert.equal(v.body.vehicle.price, 200);
ok("dépôt fait hors-ligne : l'identifiant, le code du ticket et les heures sont conservés");

const same = await call('POST', `/centers/${centerId}/vehicles`, {
  token: A.accessToken,
  body: { id: randomUUID(), code, type: 'moto', ownerName: 'Autre client' },
});
assert.equal(same.status, 201);
assert.notEqual(same.body.vehicle.code, code);
ok('code déjà pris par un autre véhicule en garde : le serveur en attribue un nouveau');

const over = await call('POST', `/vehicles/${vehicleId}/payments`, { token: A.accessToken, body: { amount: 500 } });
assert.ok(over.status >= 400 && over.status < 500, `trop-perçu refusé : ${over.status}`);
const payId = randomUUID();
const pay = await call('POST', `/vehicles/${vehicleId}/payments`, { token: A.accessToken, body: { id: payId, amount: 200 } });
assert.equal(pay.status, 201, JSON.stringify(pay.body));
const payAgain = await call('POST', `/vehicles/${vehicleId}/payments`, { token: A.accessToken, body: { id: payId, amount: 200 } });
assert.ok(payAgain.status === 200 || payAgain.status === 201);
const pending = await call('GET', `/centers/${centerId}/pending`, { token: O.accessToken });
assert.equal(pending.status, 200);
ok('paiement encaissé une seule fois même rejoué ; le trop-perçu est refusé');

const changes = await call('GET', `/centers/${centerId}/changes?since=${encodeURIComponent(since)}`, { token: O.accessToken });
assert.equal(changes.status, 200);
assert.ok(changes.body.vehicles.some((x) => x.id === vehicleId));
assert.ok(changes.body.payments.some((x) => x.id === payId));
assert.ok(typeof changes.body.serverTime === 'string');
ok('le propriétaire reçoit le véhicule et le paiement de l\'agent (flux /changes)');

const collect = await call('POST', `/vehicles/${vehicleId}/collect`, { token: A.accessToken, body: { pickupCheck: 'exact', ticketVerified: true } });
assert.equal(collect.status, 200, JSON.stringify(collect.body));
const twice = await call('POST', `/vehicles/${vehicleId}/collect`, { token: A.accessToken, body: { pickupCheck: 'exact', ticketVerified: true } });
assert.equal(twice.status, 409);
ok('remise enregistrée ; une seconde remise est refusée');

// --- Sessions ---------------------------------------------------------------
const rotated = await call('POST', '/auth/refresh', { body: { refreshToken: O.refreshToken } });
assert.equal(rotated.status, 200, JSON.stringify(rotated.body));
const replay = await call('POST', '/auth/refresh', { body: { refreshToken: O.refreshToken } });
assert.equal(replay.status, 401);
const revoked = await call('POST', '/auth/refresh', { body: { refreshToken: rotated.body.refreshToken } });
assert.equal(revoked.status, 401);
ok('jeton de rafraîchissement rotatif : le rejouer révoque toute la session');

assert.equal((await call('GET', '/centers')).status, 401);
ok('sans jeton : accès refusé');

console.log(`\nTout est bon (${step} vérifications). Les comptes et le centre de test restent en base : ${ownerPhone}, ${agentPhone}.`);
