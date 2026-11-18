import type { FastifyPluginAsync } from 'fastify';
import { z } from 'zod';
import { requireAuth, requireOwner, roleInCenter, vehicleCenter } from '../auth.js';
import { randomInt } from 'node:crypto';
import { type Db, type Queryable, tx } from '../db.js';
import { conflict, notFound } from '../errors.js';
import { plateDisplay, plateKey } from '../plates.js';
import { paymentJson, vehicleJson } from '../serializers.js';
import { parse } from '../validate.js';
import { uuid } from '../crypto.js';

const uid = z.string().uuid();
const iso = z.string().datetime({ offset: true });
const type = z.enum(['moto', 'velo', 'voiture', 'autre']);
const money = z.number().int().min(0).max(10_000_000);

const createBody = z.object({
  id: uid.optional(), // généré par l'appli hors-ligne (rejeu idempotent)
  plate: z.string().max(20).default(''),
  type,
  ownerName: z.string().trim().min(1, 'Nom du propriétaire obligatoire.').max(80),
  ownerPhone: z.string().trim().max(32).default(''),
  note: z.string().trim().max(300).default(''),
  price: money.optional(), // défaut : tarif du centre pour ce type
  guardHours: z.number().int().min(1).max(720).optional(), // défaut : durée du centre
  depositedAt: iso.optional(), // défaut : maintenant (appli hors-ligne : heure réelle du dépôt)
});
const patchBody = z.object({
  plate: z.string().max(20),
  type,
  ownerName: z.string().trim().min(1).max(80),
  ownerPhone: z.string().trim().max(32),
  note: z.string().trim().max(300),
  price: money,
}).partial();
const collectBody = z.object({
  pickupCheck: z.enum(['exact', 'close', 'different', 'skipped']),
  ticketVerified: z.boolean(),
  collectedAt: iso.optional(),
});
const range = z.object({ from: iso, to: iso });

const MAX_PAST_MS = 30 * 24 * 3600_000;
const MAX_FUTURE_MS = 3600_000;

/** Échappe % _ \ pour un LIKE : la recherche de l'utilisateur est un texte, pas un motif. */
const esc = (s: string) => s.replace(/[\\%_]/g, (m) => `\\${m}`);

async function uniqueCode(db: Queryable, centerId: string): Promise<string> {
  for (let i = 0; i < 30; i++) {
    const code = String(randomInt(100000, 1000000));
    const { rows } = await db.query(
      'SELECT 1 FROM vehicles WHERE center_id = $1 AND code = $2 AND collected_at IS NULL',
      [centerId, code],
    );
    if (rows.length === 0) return code;
  }
  throw new Error('Impossible de générer un code unique.');
}

export const vehicleRoutes =
  (db: Db): FastifyPluginAsync =>
  async (app) => {
    app.addHook('preHandler', requireAuth);

    // --- Dépôt -------------------------------------------------------------
    app.post<{ Params: { id: string } }>('/centers/:id/vehicles', async (req, reply) => {
      parse(uid, req.params.id);
      await roleInCenter(db, req.user.sub, req.params.id);
      const b = parse(createBody, req.body);

      if (b.id) {
        // Rejeu d'un dépôt hors-ligne déjà reçu : on renvoie l'existant.
        const { rows } = await db.query('SELECT * FROM vehicles WHERE id = $1', [b.id]);
        if (rows[0]) {
          if (rows[0].center_id !== req.params.id) throw conflict('id_taken', 'Identifiant déjà utilisé.');
          return reply.status(200).send({ vehicle: vehicleJson(rows[0]) });
        }
      }

      const center = (await db.query('SELECT * FROM centers WHERE id = $1', [req.params.id])).rows[0];
      const now = Date.now();
      const deposited = b.depositedAt ? new Date(b.depositedAt) : new Date(now);
      if (deposited.getTime() < now - MAX_PAST_MS || deposited.getTime() > now + MAX_FUTURE_MS) {
        throw conflict('bad_date', 'Date de dépôt invalide.');
      }
      const hours = b.guardHours ?? center.guard_hours;
      const due = new Date(deposited.getTime() + hours * 3600_000);
      const price = b.price ?? center[`price_${b.type}`];

      for (let attempt = 0; attempt < 5; attempt++) {
        const code = await uniqueCode(db, req.params.id);
        try {
          const r = await db.query(
            `INSERT INTO vehicles(id, center_id, code, plate, plate_key, type, owner_name,
                                  owner_phone, note, deposited_at, due_at, price, created_by)
             VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13) RETURNING *`,
            [b.id ?? uuid(), req.params.id, code, plateDisplay(b.plate), plateKey(b.plate), b.type,
             b.ownerName, b.ownerPhone, b.note, deposited, due, price, req.user.sub],
          );
          return reply.status(201).send({ vehicle: vehicleJson(r.rows[0]) });
        } catch (e) {
          // Course sur le code (deux agents en même temps) → on retire un autre code.
          if ((e as { code?: string; constraint?: string }).code === '23505' &&
              (e as { constraint?: string }).constraint === 'uq_vehicles_active_code') continue;
          throw e;
        }
      }
      throw new Error('Impossible de générer un code unique.');
    });

    // --- Lectures ----------------------------------------------------------
    app.get<{ Params: { id: string }; Querystring: { from?: string; to?: string } }>(
      '/centers/:id/vehicles',
      async (req) => {
        parse(uid, req.params.id);
        await roleInCenter(db, req.user.sub, req.params.id);
        const q = parse(range, req.query);
        const { rows } = await db.query(
          `SELECT * FROM vehicles WHERE center_id = $1 AND deposited_at >= $2 AND deposited_at < $3
            ORDER BY deposited_at DESC LIMIT 1000`,
          [req.params.id, q.from, q.to],
        );
        return { vehicles: rows.map(vehicleJson) };
      },
    );

    app.get<{ Params: { id: string } }>('/centers/:id/vehicles/active', async (req) => {
      parse(uid, req.params.id);
      await roleInCenter(db, req.user.sub, req.params.id);
      const { rows } = await db.query(
        `SELECT * FROM vehicles WHERE center_id = $1 AND collected_at IS NULL
          ORDER BY deposited_at DESC LIMIT 1000`,
        [req.params.id],
      );
      return { vehicles: rows.map(vehicleJson) };
    });

    // Les codes à 6 chiffres se devinent (1 sur 900 000) : on limite fortement les essais.
    const lookup = { config: { rateLimit: { max: 30, timeWindow: '1 minute' } } };

    app.get<{ Params: { id: string; code: string } }>(
      '/centers/:id/vehicles/by-code/:code',
      lookup,
      async (req) => {
        parse(uid, req.params.id);
        await roleInCenter(db, req.user.sub, req.params.id);
        const code = parse(z.string().regex(/^\d{6}$/, 'Code à 6 chiffres.'), req.params.code);
        const { rows } = await db.query(
          `SELECT * FROM vehicles WHERE center_id = $1 AND code = $2
            ORDER BY (collected_at IS NULL) DESC, deposited_at DESC LIMIT 1`,
          [req.params.id, code],
        );
        if (!rows[0]) throw notFound('Aucun ticket avec ce code.');
        return { vehicle: vehicleJson(rows[0]) };
      },
    );

    app.get<{ Params: { id: string; key: string } }>(
      '/centers/:id/vehicles/by-plate/:key',
      async (req) => {
        parse(uid, req.params.id);
        await roleInCenter(db, req.user.sub, req.params.id);
        const key = plateKey(req.params.key);
        if (!key) return { vehicles: [] };
        const { rows } = await db.query(
          `SELECT * FROM vehicles WHERE center_id = $1 AND plate_key = $2 AND collected_at IS NULL
            ORDER BY deposited_at DESC`,
          [req.params.id, key],
        );
        return { vehicles: rows.map(vehicleJson) };
      },
    );

    app.get<{ Params: { id: string }; Querystring: { q?: string } }>(
      '/centers/:id/vehicles/search',
      async (req) => {
        parse(uid, req.params.id);
        await roleInCenter(db, req.user.sub, req.params.id);
        const q = parse(z.object({ q: z.string().trim().min(1).max(60) }), req.query).q;
        const like = `%${esc(q.toLowerCase())}%`;
        const digits = `%${esc(q.replace(/\s/g, ''))}%`;
        const key = plateKey(q);
        const { rows } = await db.query(
          `SELECT * FROM vehicles
            WHERE center_id = $1 AND (
                  LOWER(owner_name) LIKE $2 OR owner_phone LIKE $2 OR code LIKE $3
               OR ($4 <> '' AND plate_key LIKE $5))
            ORDER BY deposited_at DESC LIMIT 80`,
          [req.params.id, like, digits, key, `%${esc(key)}%`],
        );
        return { vehicles: rows.map(vehicleJson) };
      },
    );

    // Flux de changements pour la synchronisation des appareils (hors-ligne).
    app.get<{ Params: { id: string }; Querystring: { since?: string } }>(
      '/centers/:id/changes',
      async (req) => {
        parse(uid, req.params.id);
        await roleInCenter(db, req.user.sub, req.params.id);
        const since = parse(z.object({ since: iso.default('1970-01-01T00:00:00Z') }), req.query).since;
        const serverTime = new Date();
        const [v, p, d] = await Promise.all([
          db.query('SELECT * FROM vehicles WHERE center_id = $1 AND updated_at > $2 ORDER BY updated_at', [req.params.id, since]),
          db.query(
            `SELECT p.* FROM payments p WHERE p.center_id = $1 AND p.created_at > $2 ORDER BY p.created_at`,
            [req.params.id, since],
          ),
          db.query('SELECT id FROM deleted_vehicles WHERE center_id = $1 AND deleted_at > $2', [req.params.id, since]),
        ]);
        return {
          serverTime: serverTime.toISOString(),
          vehicles: v.rows.map(vehicleJson),
          payments: p.rows.map(paymentJson),
          deletedVehicleIds: d.rows.map((r) => r.id as string),
        };
      },
    );

    // --- Modifications -----------------------------------------------------
    app.get<{ Params: { id: string } }>('/vehicles/:id', async (req) => {
      parse(uid, req.params.id);
      await vehicleCenter(db, req.user.sub, req.params.id);
      const { rows } = await db.query('SELECT * FROM vehicles WHERE id = $1', [req.params.id]);
      return { vehicle: vehicleJson(rows[0]) };
    });

    app.patch<{ Params: { id: string } }>('/vehicles/:id', async (req) => {
      parse(uid, req.params.id);
      const centerId = await vehicleCenter(db, req.user.sub, req.params.id);
      const b = parse(patchBody, req.body);
      const r = await db.query(
        `UPDATE vehicles SET
           plate = COALESCE($2, plate), plate_key = COALESCE($3, plate_key),
           type = COALESCE($4, type), owner_name = COALESCE($5, owner_name),
           owner_phone = COALESCE($6, owner_phone), note = COALESCE($7, note),
           price = COALESCE($8, price), updated_at = now()
         WHERE id = $1 RETURNING *`,
        [req.params.id,
         b.plate === undefined ? null : plateDisplay(b.plate),
         b.plate === undefined ? null : plateKey(b.plate),
         b.type ?? null, b.ownerName ?? null, b.ownerPhone ?? null, b.note ?? null, b.price ?? null],
      );
      if (b.price !== undefined) {
        await audit(db, centerId, req.user.sub, 'vehicle.price', req.params.id, { price: b.price });
      }
      return { vehicle: vehicleJson(r.rows[0]) };
    });

    // Remise du véhicule : une seule fois, avec le résultat de la vérification.
    app.post<{ Params: { id: string } }>('/vehicles/:id/collect', async (req) => {
      parse(uid, req.params.id);
      const centerId = await vehicleCenter(db, req.user.sub, req.params.id);
      const b = parse(collectBody, req.body);
      const at = b.collectedAt ? new Date(b.collectedAt) : new Date();
      const r = await db.query(
        `UPDATE vehicles SET collected_at = $2, pickup_check = $3, ticket_verified = $4,
                collected_by = $5, updated_at = now()
          WHERE id = $1 AND collected_at IS NULL RETURNING *`,
        [req.params.id, at, b.pickupCheck, b.ticketVerified, req.user.sub],
      );
      if (!r.rows[0]) throw conflict('already_collected', 'Ce véhicule a déjà été remis.');
      const v = r.rows[0];
      await audit(db, centerId, req.user.sub, 'vehicle.collect', req.params.id, {
        pickupCheck: b.pickupCheck,
        ticketVerified: b.ticketVerified,
        unpaid: Math.max(0, v.price - v.paid_amount),
      });
      return { vehicle: vehicleJson(v) };
    });

    // Suppression : réservée au propriétaire (une preuve ne doit pas disparaître par erreur).
    app.delete<{ Params: { id: string } }>('/vehicles/:id', async (req, reply) => {
      parse(uid, req.params.id);
      const centerId = await vehicleCenter(db, req.user.sub, req.params.id);
      await requireOwner(db, req.user.sub, centerId);
      await tx(db, async (c) => {
        const r = await c.query('DELETE FROM vehicles WHERE id = $1 RETURNING plate, price, paid_amount', [req.params.id]);
        await c.query('INSERT INTO deleted_vehicles(id, center_id) VALUES ($1, $2) ON CONFLICT DO NOTHING', [req.params.id, centerId]);
        await audit(c, centerId, req.user.sub, 'vehicle.delete', req.params.id, r.rows[0] ?? {});
      });
      return reply.status(204).send();
    });
  };

export async function audit(
  db: Queryable,
  centerId: string,
  userId: string,
  action: string,
  entityId: string,
  details: unknown,
): Promise<void> {
  await db.query(
    `INSERT INTO audit_log(center_id, user_id, action, entity, entity_id, details)
     VALUES ($1, $2, $3, $4, $5, $6)`,
    [centerId, userId, action, action.split('.')[0], entityId, JSON.stringify(details)],
  );
}
