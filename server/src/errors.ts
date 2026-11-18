/** Erreur « métier » renvoyée telle quelle au client (code HTTP + message lisible). */
export class ApiError extends Error {
  constructor(
    public readonly status: number,
    public readonly code: string,
    message: string,
  ) {
    super(message);
  }
}

export const badRequest = (m: string) => new ApiError(400, 'bad_request', m);
export const unauthorized = (m = 'Authentification requise.') => new ApiError(401, 'unauthorized', m);
export const forbidden = (m = 'Accès refusé.') => new ApiError(403, 'forbidden', m);
// 404 aussi pour « existe mais pas à vous » : on ne révèle pas l'existence d'un centre/véhicule.
export const notFound = (m = 'Introuvable.') => new ApiError(404, 'not_found', m);
export const conflict = (code: string, m: string) => new ApiError(409, code, m);
