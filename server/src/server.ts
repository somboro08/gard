import { buildApp } from './app.js';
import { loadConfig } from './config.js';
import { createDb } from './db.js';
import { migrate } from './migrate.js';

const config = loadConfig();
const db = createDb(config.databaseUrl);
const applied = await migrate(db);
if (applied.length) console.log(`Migrations appliquées : ${applied.join(', ')}`);

const app = await buildApp({ config, db, logger: true });

const stop = async () => {
  await app.close();
  await db.end();
  process.exit(0);
};
process.on('SIGINT', stop);
process.on('SIGTERM', stop);

await app.listen({ port: config.port, host: config.host });
