import type { FastifyPluginAsync } from 'fastify';
import { z } from 'zod';
import { requireAuth, requireOwner, roleInCenter } from '../auth.js';
import { uuid } from '../crypto.js';
import { type Db, tx } from '../db.js';
import { badRequest, conflict, forbidden, notFound } from '../errors.js';
import { normalizePhone } from '../plates.js';
import { centerJson } from '../serializers.js';
import { parse } from '../validate.js';

const price = z.number().int().min(0).max(10_000_000);
const tariff = z.object({ moto: price, velo: price, voiture: price, autre: price }).partial();
const id = z.string().uuid();

const createBody = z.object({
  id: id.optional(), // identifiant généré par l'appli hors-ligne
  name: z.string().trim().min(1, 'Nom obligatoire.').max(80),
  location: z.string().trim().max(160).default(''),
  guardHours: z.number().int().min(1).max(720),
  tariff: tariff.default({}),
});
const patchBody = createBody.omit({ id: true }).partial();
const memberBody = z.object({
  phone: z.string().max(32).transform(normalizePhone),
  role: z.enum(['owner', 'agent']).default('agent'),
});

const COLS = `c.*, m.role`;

export const centerRoutes =
  (db: Db): FastifyPluginAsync =>
  async (app) => {
    app.addHook('preHandler', requireAuth);

    const load = async (centerId: string, userId: string) => {
      const { rows } = await db.query(
        `SELECT ${COLS} FROM centers c JOIN center_members m ON m.center_id = c.id AND m.user_id = $2
          WHERE c.id = $1`,
        [centerId, userId],
      );
      if (!rows[0]) throw notFound('Centre introuvable.');
      return rows[0];
    };

    app.get('/centers', async (req) => {
      const { rows } = await db.query(
        `SELECT ${COLS} FROM centers c JOIN center_members m ON m.center_id = c.id
          WHERE m.user_id = $1 ORDER BY c.created_at`,
        [req.user.sub],
      );
      return { centers: rows.map(centerJson) };
    });

    app.post('/centers', async (req, reply) => {
      const b = parse(createBody, req.body);
      const cid = b.id ?? uuid();
      const created = await tx(db, async (c) => {
        const r = await c.query(
          `INSERT INTO centers(id, name, location, guard_hours, price_moto, price_velo,
                               price_voiture, price_autre, created_by)
           VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9) ON CONFLICT (id) DO NOTHING`,
          [cid, b.name, b.location, b.guardHours, b.tariff.moto ?? 0, b.tariff.velo ?? 0,
           b.tariff.voiture ?? 0, b.tariff.autre ?? 0, req.user.sub],
        );
        if (r.rowCount === 0) return false;
        await c.query(
          `INSERT INTO center_members(center_id, user_id, role) VALUES ($1, $2, 'owner')`,
          [cid, req.user.sub],
        );
        return true;
      });
      if (!created) {
        // Rejeu d'une création hors-ligne : idempotent pour le propriétaire, sinon conflit.
        const { rows } = await db.query(
          `SELECT role FROM center_members WHERE center_id = $1 AND user_id = $2`,
          [cid, req.user.sub],
        );
        if (rows[0]?.role !== 'owner') throw conflict('id_taken', 'Cet identifiant est déjà utilisé.');
        return reply.status(200).send({ center: centerJson(await load(cid, req.user.sub)) });
      }
      return reply.status(201).send({ center: centerJson(await load(cid, req.user.sub)) });
    });

    app.get<{ Params: { id: string } }>('/centers/:id', async (req) => {
      parse(id, req.params.id);
      return { center: centerJson(await load(req.params.id, req.user.sub)) };
    });

    app.patch<{ Params: { id: string } }>('/centers/:id', async (req) => {
      parse(id, req.params.id);
      await requireOwner(db, req.user.sub, req.params.id);
      const b = parse(patchBody, req.body);
      await db.query(
        `UPDATE centers SET
           name = COALESCE($2, name), location = COALESCE($3, location),
           guard_hours = COALESCE($4, guard_hours),
           price_moto = COALESCE($5, price_moto), price_velo = COALESCE($6, price_velo),
           price_voiture = COALESCE($7, price_voiture), price_autre = COALESCE($8, price_autre),
           updated_at = now()
         WHERE id = $1`,
        [req.params.id, b.name ?? null, b.location ?? null, b.guardHours ?? null,
         b.tariff?.moto ?? null, b.tariff?.velo ?? null, b.tariff?.voiture ?? null,
         b.tariff?.autre ?? null],
      );
      return { center: centerJson(await load(req.params.id, req.user.sub)) };
    });

    app.delete<{ Params: { id: string } }>('/centers/:id', async (req, reply) => {
      parse(id, req.params.id);
      await requireOwner(db, req.user.sub, req.params.id);
      await db.query('DELETE FROM centers WHERE id = $1', [req.params.id]);
      return reply.status(204).send();
    });

    // --- Membres (agents) ---------------------------------------------------

    app.get<{ Params: { id: string } }>('/centers/:id/members', async (req) => {
      parse(id, req.params.id);
      await roleInCenter(db, req.user.sub, req.params.id);
      const { rows } = await db.query(
        `SELECT u.id, u.name, u.phone, m.role FROM center_members m
           JOIN users u ON u.id = m.user_id WHERE m.center_id = $1 ORDER BY m.created_at`,
        [req.params.id],
      );
      return { members: rows };
    });

    // Le propriétaire ajoute un agent qui a DÉJÀ créé son compte (par son numéro).
    app.post<{ Params: { id: string } }>('/centers/:id/members', async (req, reply) => {
      parse(id, req.params.id);
      await requireOwner(db, req.user.sub, req.params.id);
      const b = parse(memberBody, req.body);
      const u = (await db.query('SELECT id, name, phone FROM users WHERE phone = $1', [b.phone])).rows[0];
      if (!u) throw notFound("Aucun compte avec ce numéro : l'agent doit d'abord s'inscrire.");
      await tx(db, async (c) => {
        const cur = (
          await c.query(`SELECT role FROM center_members WHERE center_id = $1 AND user_id = $2 FOR UPDATE`, [
            req.params.id, u.id,
          ])
        ).rows[0];
        if (cur?.role === 'owner' && b.role === 'agent') {
          await assertNotLastOwner(c, req.params.id);
        }
        await c.query(
          `INSERT INTO center_members(center_id, user_id, role) VALUES ($1,$2,$3)
           ON CONFLICT (center_id, user_id) DO UPDATE SET role = EXCLUDED.role`,
          [req.params.id, u.id, b.role],
        );
      });
      return reply.status(201).send({ member: { id: u.id, name: u.name, phone: u.phone, role: b.role } });
    });

    // Le propriétaire retire un agent ; chacun peut aussi quitter un centre.
    app.delete<{ Params: { id: string; userId: string } }>(
      '/centers/:id/members/:userId',
      async (req, reply) => {
        parse(id, req.params.id);
        parse(id, req.params.userId);
        const role = await roleInCenter(db, req.user.sub, req.params.id);
        if (req.params.userId !== req.user.sub && role !== 'owner') {
          throw forbidden('Réservé au propriétaire du centre.');
        }
        await tx(db, async (c) => {
          const cur = (
            await c.query(`SELECT role FROM center_members WHERE center_id = $1 AND user_id = $2 FOR UPDATE`, [
              req.params.id, req.params.userId,
            ])
          ).rows[0];
          if (!cur) throw notFound('Membre introuvable.');
          if (cur.role === 'owner') await assertNotLastOwner(c, req.params.id);
          await c.query('DELETE FROM center_members WHERE center_id = $1 AND user_id = $2', [
            req.params.id, req.params.userId,
          ]);
        });
        return reply.status(204).send();
      },
    );
  };

async function assertNotLastOwner(c: { query: (q: string, v: unknown[]) => Promise<{ rows: unknown[] }> }, centerId: string) {
  const { rows } = await c.query(
    `SELECT 1 FROM center_members WHERE center_id = $1 AND role = 'owner' FOR UPDATE`,
    [centerId],
  );
  if (rows.length <= 1) throw badRequest('Un centre doit garder au moins un propriétaire.');
}
