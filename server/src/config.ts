export interface Config {
  port: number;
  host: string;
  databaseUrl: string;
  jwtSecret: string;
  accessTtlSeconds: number;
  refreshTtlDays: number;
  corsOrigin: string | boolean;
  isProd: boolean;
}

export function loadConfig(env: NodeJS.ProcessEnv = process.env): Config {
  const isProd = env.NODE_ENV === 'production';
  const jwtSecret = env.JWT_SECRET ?? '';
  if (isProd && jwtSecret.length < 32) {
    throw new Error('JWT_SECRET doit contenir au moins 32 caractères en production.');
  }
  const databaseUrl = env.DATABASE_URL ?? '';
  if (!databaseUrl) throw new Error('DATABASE_URL est obligatoire.');
  return {
    port: Number(env.PORT ?? 3000),
    host: env.HOST ?? '0.0.0.0',
    databaseUrl,
    jwtSecret: jwtSecret || 'dev-only-secret-change-me-dev-only-secret',
    accessTtlSeconds: Number(env.ACCESS_TTL_SECONDS ?? 15 * 60),
    refreshTtlDays: Number(env.REFRESH_TTL_DAYS ?? 30),
    // Une app mobile n'a pas besoin de CORS ; on ne l'ouvre que si demandé.
    corsOrigin: env.CORS_ORIGIN ? env.CORS_ORIGIN : false,
    isProd,
  };
}
