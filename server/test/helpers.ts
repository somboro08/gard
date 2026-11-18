import type { FastifyInstance } from 'fastify';
import { buildApp } from '../src/app.js';
import { loadConfig } from '../src/config.js';
import { createDb, type Db } from '../src/db.js';
import { migrate } from '../src/migrate.js';

export const DATABASE_URL =
  process.env.DATABASE_URL ?? 'postgres://postgres@localhost:5433/garde_test';

export interface Ctx {
  app: FastifyInstance;
  db: Db;
  close: () => Promise<void>;
}

/** Base vierge + migrations + application prête à recevoir des requêtes (app.inject). */
export async function start(opts: { rateLimit?: boolean } = {}): Promise<Ctx> {
  const config = loadConfig({ DATABASE_URL, JWT_SECRET: 'test-secret-test-secret-test-secret-123' });
  const db = createDb(config.databaseUrl);
  await db.query('DROP SCHEMA public CASCADE');
  await db.query('CREATE SCHEMA public');
  await migrate(db);
  const app = await buildApp({ config, db, rateLimit: opts.rateLimit ?? false });
  return { app, db, close: async () => { await app.close(); await db.end(); } };
}

export interface Res {
  status: number;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  body: any;
}

export function client(app: FastifyInstance) {
  return async (method: 'GET' | 'POST' | 'PATCH' | 'DELETE', url: string, token?: string, body?: unknown): Promise<Res> => {
    const r = await app.inject({
      method,
      url,
      headers: token ? { authorization: `Bearer ${token}` } : {},
      ...(body === undefined ? {} : { payload: body as object }),
    });
    return { status: r.statusCode, body: r.body ? JSON.parse(r.body) : null };
  };
}

let n = 0;
/** Crée un compte et renvoie ses jetons. */
export async function signup(call: ReturnType<typeof client>, name = 'Agent') {
  n += 1;
  const phone = `0197${String(100000 + n)}`;
  const r = await call('POST', '/auth/register', undefined, { phone, name, password: 'motdepasse1' });
  if (r.status !== 201) throw new Error(`register ${r.status} ${JSON.stringify(r.body)}`);
  return { phone, token: r.body.accessToken as string, refresh: r.body.refreshToken as string, id: r.body.user.id as string };
}
