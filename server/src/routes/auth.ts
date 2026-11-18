import type { FastifyPluginAsync } from 'fastify';
import { z } from 'zod';
import { requireAuth } from '../auth.js';
import type { Config } from '../config.js';
import { DUMMY_HASH, hashPassword, newRefreshToken, sha256, uuid, verifyPassword } from '../crypto.js';
import { type Db, tx } from '../db.js';
import { conflict, unauthorized } from '../errors.js';
import { normalizePhone } from '../plates.js';
import { userJson } from '../serializers.js';
import { parse } from '../validate.js';

const phoneField = z
  .string()
  .max(32)
  .transform(normalizePhone)
  .refine((p) => p.length >= 11 && p.length <= 15, 'Numéro de téléphone invalide.');

const registerBody = z.object({
  phone: phoneField,
  name: z.string().trim().min(2, 'Nom trop court.').max(80),
  password: z.string().min(8, 'Mot de passe : 8 caractères minimum.').max(200),
});
const loginBody = z.object({ phone: phoneField, password: z.string().min(1).max(200) });
const refreshBody = z.object({ refreshToken: z.string().min(20).max(200) });

export const authRoutes =
  (db: Db, config: Config): FastifyPluginAsync =>
  async (app) => {
    const strict = { config: { rateLimit: { max: 10, timeWindow: '1 minute' } } };

    /** Jeton d'accès (JWT court) + jeton de rafraîchissement (opaque, rotatif). */
    async function issueTokens(userId: string, familyId: string = uuid()) {
      const refreshToken = newRefreshToken();
      await db.query(
        `INSERT INTO refresh_tokens(id, user_id, family_id, token_hash, expires_at)
         VALUES ($1, $2, $3, $4, now() + make_interval(days => $5))`,
        [uuid(), userId, familyId, sha256(refreshToken), config.refreshTtlDays],
      );
      return {
        accessToken: app.jwt.sign({ sub: userId }),
        refreshToken,
        expiresIn: config.accessTtlSeconds,
      };
    }

    app.post('/register', strict, async (req, reply) => {
      const b = parse(registerBody, req.body);
      const id = uuid();
      const r = await db.query(
        `INSERT INTO users(id, phone, name, password_hash) VALUES ($1, $2, $3, $4)
         ON CONFLICT (phone) DO NOTHING RETURNING id, phone, name`,
        [id, b.phone, b.name, await hashPassword(b.password)],
      );
      if (r.rowCount === 0) throw conflict('phone_taken', 'Un compte existe déjà avec ce numéro.');
      return reply.status(201).send({ user: userJson(r.rows[0]), ...(await issueTokens(id)) });
    });

    app.post('/login', strict, async (req) => {
      const b = parse(loginBody, req.body);
      const { rows } = await db.query(
        'SELECT id, phone, name, password_hash FROM users WHERE phone = $1',
        [b.phone],
      );
      const u = rows[0];
      const ok = await verifyPassword(b.password, u?.password_hash ?? DUMMY_HASH);
      if (!u || !ok) throw unauthorized('Numéro ou mot de passe incorrect.');
      return { user: userJson(u), ...(await issueTokens(u.id)) };
    });

    app.post('/refresh', strict, async (req) => {
      const { refreshToken } = parse(refreshBody, req.body);
      return tx(db, async (c) => {
        const { rows } = await c.query(
          `SELECT id, user_id, family_id, expires_at, revoked_at
             FROM refresh_tokens WHERE token_hash = $1 FOR UPDATE`,
          [sha256(refreshToken)],
        );
        const t = rows[0];
        if (!t) throw unauthorized('Session invalide.');
        if (t.revoked_at) {
          // Jeton déjà utilisé = vol probable : on coupe toute la session.
          await c.query(
            'UPDATE refresh_tokens SET revoked_at = now() WHERE family_id = $1 AND revoked_at IS NULL',
            [t.family_id],
          );
          // Le COMMIT doit avoir lieu malgré l'erreur : on la renvoie après la transaction.
          return { reuse: true as const };
        }
        if (new Date(t.expires_at) < new Date()) throw unauthorized('Session expirée.');
        await c.query('UPDATE refresh_tokens SET revoked_at = now() WHERE id = $1', [t.id]);
        const next = newRefreshToken();
        await c.query(
          `INSERT INTO refresh_tokens(id, user_id, family_id, token_hash, expires_at)
           VALUES ($1, $2, $3, $4, now() + make_interval(days => $5))`,
          [uuid(), t.user_id, t.family_id, sha256(next), config.refreshTtlDays],
        );
        return {
          reuse: false as const,
          accessToken: app.jwt.sign({ sub: t.user_id as string }),
          refreshToken: next,
          expiresIn: config.accessTtlSeconds,
        };
      }).then((out) => {
        if (out.reuse) throw unauthorized('Session invalide.');
        const { reuse: _r, ...tokens } = out;
        return tokens;
      });
    });

    app.post('/logout', async (req, reply) => {
      const { refreshToken } = parse(refreshBody, req.body);
      await db.query(
        `UPDATE refresh_tokens SET revoked_at = now()
          WHERE revoked_at IS NULL AND family_id =
                (SELECT family_id FROM refresh_tokens WHERE token_hash = $1)`,
        [sha256(refreshToken)],
      );
      return reply.status(204).send();
    });

    app.get('/me', { preHandler: requireAuth }, async (req) => {
      const { rows } = await db.query('SELECT id, phone, name FROM users WHERE id = $1', [req.user.sub]);
      if (!rows[0]) throw unauthorized();
      return { user: userJson(rows[0]) };
    });
  };
