import type { FastifyReply, FastifyRequest } from 'fastify';
import type { Db, Queryable } from './db.js';
import { forbidden, notFound, unauthorized } from './errors.js';

declare module '@fastify/jwt' {
  interface FastifyJWT {
    payload: { sub: string };
    user: { sub: string };
  }
}

export type Role = 'owner' | 'agent';

/** Préhandler : exige un jeton d'accès valide. L'identifiant utilisateur est dans req.user.sub. */
export async function requireAuth(req: FastifyRequest, _reply: FastifyReply): Promise<void> {
  try {
    await req.jwtVerify();
  } catch {
    throw unauthorized('Session expirée ou invalide.');
  }
}

/**
 * Rôle de l'utilisateur dans le centre. Un centre inexistant OU auquel l'utilisateur n'a pas
 * accès renvoie le même 404 (on ne confirme pas l'existence des centres des autres).
 */
export async function roleInCenter(db: Queryable, userId: string, centerId: string): Promise<Role> {
  const { rows } = await db.query<{ role: Role }>(
    'SELECT role FROM center_members WHERE center_id = $1 AND user_id = $2',
    [centerId, userId],
  );
  const role = rows[0]?.role;
  if (!role) throw notFound('Centre introuvable.');
  return role;
}

export async function requireOwner(db: Queryable, userId: string, centerId: string): Promise<void> {
  if ((await roleInCenter(db, userId, centerId)) !== 'owner') {
    throw forbidden('Réservé au propriétaire du centre.');
  }
}

/** Centre auquel appartient un véhicule, uniquement s'il est accessible à l'utilisateur. */
export async function vehicleCenter(db: Db, userId: string, vehicleId: string): Promise<string> {
  const { rows } = await db.query<{ center_id: string }>(
    `SELECT v.center_id FROM vehicles v
       JOIN center_members m ON m.center_id = v.center_id AND m.user_id = $2
      WHERE v.id = $1`,
    [vehicleId, userId],
  );
  const id = rows[0]?.center_id;
  if (!id) throw notFound('Véhicule introuvable.');
  return id;
}
