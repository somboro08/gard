import type { ZodTypeAny, z } from 'zod';
import { badRequest } from './errors.js';

/** Valide [data] ; en cas d'échec : 400 avec le premier message lisible. */
export function parse<S extends ZodTypeAny>(schema: S, data: unknown): z.infer<S> {
  const r = schema.safeParse(data ?? {});
  if (!r.success) {
    const i = r.error.issues[0];
    const where = i && i.path.length ? `${i.path.join('.')} : ` : '';
    throw badRequest(`${where}${i?.message ?? 'Requête invalide.'}`);
  }
  return r.data;
}
