import { readdir, readFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import type { Db } from './db.js';

const dir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../migrations');

/** Applique les fichiers migrations/NNN_*.sql pas encore appliqués, dans l'ordre. */
export async function migrate(db: Db): Promise<string[]> {
  const applied: string[] = [];
  const c = await db.connect();
  try {
    // Verrou : deux instances qui démarrent en même temps ne migrent pas en double.
    await c.query('SELECT pg_advisory_lock(727274)');
    await c.query(
      `CREATE TABLE IF NOT EXISTS schema_migrations (
         name TEXT PRIMARY KEY, applied_at TIMESTAMPTZ NOT NULL DEFAULT now())`,
    );
    const done = new Set(
      (await c.query<{ name: string }>('SELECT name FROM schema_migrations')).rows.map((r) => r.name),
    );
    const files = (await readdir(dir)).filter((f) => /^\d+_.+\.sql$/.test(f)).sort();
    for (const f of files) {
      if (done.has(f)) continue;
      const sql = await readFile(path.join(dir, f), 'utf8');
      await c.query('BEGIN');
      try {
        await c.query(sql);
        await c.query('INSERT INTO schema_migrations(name) VALUES ($1)', [f]);
        await c.query('COMMIT');
      } catch (e) {
        await c.query('ROLLBACK');
        throw new Error(`Migration ${f} échouée : ${(e as Error).message}`);
      }
      applied.push(f);
    }
    return applied;
  } finally {
    await c.query('SELECT pg_advisory_unlock(727274)').catch(() => undefined);
    c.release();
  }
}
