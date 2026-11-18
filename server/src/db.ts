import pg from 'pg';

export type Db = pg.Pool;
export type Queryable = Pick<pg.Pool, 'query'>;

// Les colonnes BIGINT/NUMERIC ne sont pas utilisées : tout est INTEGER (FCFA) ou TIMESTAMPTZ.
export function createDb(databaseUrl: string): Db {
  return new pg.Pool({ connectionString: databaseUrl, max: 10 });
}

/** Exécute [fn] dans une transaction (COMMIT si OK, ROLLBACK si exception). */
export async function tx<T>(db: Db, fn: (c: pg.PoolClient) => Promise<T>): Promise<T> {
  const c = await db.connect();
  try {
    await c.query('BEGIN');
    const out = await fn(c);
    await c.query('COMMIT');
    return out;
  } catch (e) {
    await c.query('ROLLBACK').catch(() => undefined);
    throw e;
  } finally {
    c.release();
  }
}
