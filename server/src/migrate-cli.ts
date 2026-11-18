import { loadConfig } from './config.js';
import { createDb } from './db.js';
import { migrate } from './migrate.js';

const db = createDb(loadConfig().databaseUrl);
try {
  const applied = await migrate(db);
  console.log(applied.length ? `Migrations appliquées : ${applied.join(', ')}` : 'Base à jour.');
} finally {
  await db.end();
}
