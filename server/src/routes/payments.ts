import type { FastifyPluginAsync } from 'fastify';
import { z } from 'zod';
import { requireAuth, roleInCenter, vehicleCenter } from '../auth.js';
import { uuid } from '../crypto.js';
import { type Db, tx } from '../db.js';
import { conflict } from '../errors.js';
import { paymentJson } from '../serializers.js';
import { parse } from '../validate.js';
import { audit } from './vehicles.js';

const uid = z.string().uuid();
const iso = z.string().datetime({ offset: true });

const payBody = z.object({
  id: uid.optional(), // rejeu idempotent d'un encaissement fait hors-ligne
  amount: z.number().int().min(1).max(10_000_000),
  method: z.enum(['cash', 'wallet']).default('cash'),
  paidAt: iso.optional(),
});

export const paymentRoutes =
  (db: Db): FastifyPluginAsync =>
  async (app) => {
    app.addHook('preHandler', requireAuth);

    // Encaissement : ajoute au montant payé du véhicule, sans jamais dépasser le prix.
    app.post<{ Params: { id: string } }>('/vehicles/:id/payments', async (req, reply) => {
      parse(uid, req.params.id);
      const centerId = await vehicleCenter(db, req.user.sub, req.params.id);
      const b = parse(payBody, req.body);
      const out = await tx(db, async (c) => {
        const v = (
          await c.query('SELECT price, paid_amount FROM vehicles WHERE id = $1 FOR UPDATE', [req.params.id])
        ).rows[0];
        if (b.id) {
          const dup = (await c.query('SELECT * FROM payments WHERE id = $1', [b.id])).rows[0];
          if (dup) {
            if (dup.vehicle_id !== req.params.id) throw conflict('id_taken', 'Identifiant déjà utilisé.');
            return { payment: dup, created: false };
          }
        }
        const balance = v.price - v.paid_amount;
        if (b.amount > balance) {
          throw conflict('overpayment', `Montant supérieur au solde (${Math.max(0, balance)} FCFA).`);
        }
        const p = (
          await c.query(
            `INSERT INTO payments(id, vehicle_id, center_id, amount, method, paid_at, created_by)
             VALUES ($1,$2,$3,$4,$5,$6,$7) RETURNING *`,
            [b.id ?? uuid(), req.params.id, centerId, b.amount, b.method,
             b.paidAt ? new Date(b.paidAt) : new Date(), req.user.sub],
          )
        ).rows[0];
        await c.query(
          'UPDATE vehicles SET paid_amount = paid_amount + $2, updated_at = now() WHERE id = $1',
          [req.params.id, b.amount],
        );
        await audit(c, centerId, req.user.sub, 'payment.add', p.id, { amount: b.amount, method: b.method });
        return { payment: p, created: true };
      });
      return reply.status(out.created ? 201 : 200).send({ payment: paymentJson(out.payment) });
    });

    app.get<{ Params: { id: string }; Querystring: { from?: string; to?: string } }>(
      '/centers/:id/payments',
      async (req) => {
        parse(uid, req.params.id);
        await roleInCenter(db, req.user.sub, req.params.id);
        const q = parse(z.object({ from: iso, to: iso }), req.query);
        const { rows } = await db.query(
          `SELECT p.*, v.plate AS plate, v.owner_name AS owner_name, v.type AS vtype
             FROM payments p JOIN vehicles v ON v.id = p.vehicle_id
            WHERE p.center_id = $1 AND p.paid_at >= $2 AND p.paid_at < $3
            ORDER BY p.paid_at DESC LIMIT 2000`,
          [req.params.id, q.from, q.to],
        );
        return { payments: rows.map(paymentJson) };
      },
    );

    // Reste à encaisser sur les véhicules encore en garde.
    app.get<{ Params: { id: string } }>('/centers/:id/pending', async (req) => {
      parse(uid, req.params.id);
      await roleInCenter(db, req.user.sub, req.params.id);
      const { rows } = await db.query(
        `SELECT COALESCE(SUM(price - paid_amount), 0)::int AS pending FROM vehicles
          WHERE center_id = $1 AND collected_at IS NULL AND price > paid_amount`,
        [req.params.id],
      );
      return { pending: rows[0].pending as number };
    });
  };
