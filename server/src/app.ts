import cors from '@fastify/cors';
import jwt from '@fastify/jwt';
import rateLimit from '@fastify/rate-limit';
import Fastify, { type FastifyInstance } from 'fastify';
import type { Config } from './config.js';
import type { Db } from './db.js';
import { ApiError } from './errors.js';
import { authRoutes } from './routes/auth.js';
import { centerRoutes } from './routes/centers.js';
import { paymentRoutes } from './routes/payments.js';
import { vehicleRoutes } from './routes/vehicles.js';

export interface AppOptions {
  config: Config;
  db: Db;
  /** Désactivable pour les tests. */
  rateLimit?: boolean;
  logger?: boolean;
}

export async function buildApp(opts: AppOptions): Promise<FastifyInstance> {
  const { config, db } = opts;
  const app = Fastify({
    logger: opts.logger ?? false,
    bodyLimit: 64 * 1024,
    // Derrière un reverse proxy (nginx, Caddy…), l'IP réelle vient de X-Forwarded-For.
    trustProxy: config.isProd,
  });

  await app.register(cors, { origin: config.corsOrigin });
  await app.register(jwt, { secret: config.jwtSecret, sign: { expiresIn: config.accessTtlSeconds } });
  if (opts.rateLimit ?? true) {
    await app.register(rateLimit, { global: true, max: 300, timeWindow: '1 minute' });
  }

  app.setErrorHandler((err, req, reply) => {
    if (err instanceof ApiError) {
      return reply.status(err.status).send({ error: err.code, message: err.message });
    }
    const e = err as { statusCode?: number; code?: string; message: string };
    if (e.statusCode === 429) {
      return reply.status(429).send({ error: 'rate_limited', message: 'Trop de tentatives, réessayez plus tard.' });
    }
    if (e.statusCode && e.statusCode >= 400 && e.statusCode < 500) {
      return reply.status(e.statusCode).send({ error: 'bad_request', message: e.message });
    }
    req.log.error(err);
    return reply.status(500).send({ error: 'internal', message: 'Erreur interne.' });
  });
  app.setNotFoundHandler((_req, reply) =>
    reply.status(404).send({ error: 'not_found', message: 'Route inconnue.' }),
  );

  app.get('/health', async () => {
    await db.query('SELECT 1');
    return { ok: true };
  });

  await app.register(authRoutes(db, config), { prefix: '/auth' });
  await app.register(centerRoutes(db));
  await app.register(vehicleRoutes(db));
  await app.register(paymentRoutes(db));
  return app;
}
