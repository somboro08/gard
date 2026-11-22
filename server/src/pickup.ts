import { createPublicKey, verify } from 'node:crypto';

/**
 * Remise sécurisée : le client prouve qu'il détient la clé privée enrôlée au dépôt en signant
 * un défi (nonce) choisi par l'agent. Le téléphone de l'agent vérifie hors-ligne ; le serveur
 * revérifie la même preuve à la synchronisation (l'agent ne peut pas prétendre « vérifié »).
 *
 * Messages signés (identiques côté Dart, voir lib/security/pickup_crypto.dart) :
 *   enrôlement : "GARDE-ENROLL-1|<vehicleId>|<nonce>"
 *   remise     : "GARDE-PICKUP-1|<vehicleId>|<nonce>"
 */
export const B64URL_KEY = /^[A-Za-z0-9_-]{43}$/; // 32 octets
export const B64URL_SIG = /^[A-Za-z0-9_-]{86}$/; // 64 octets
export const B64URL_NONCE = /^[A-Za-z0-9_-]{22,64}$/; // 16 à 48 octets

export const enrollMessage = (vehicleId: string, nonce: string) => `GARDE-ENROLL-1|${vehicleId}|${nonce}`;
export const pickupMessage = (vehicleId: string, nonce: string) => `GARDE-PICKUP-1|${vehicleId}|${nonce}`;

// Préfixe DER (SPKI) d'une clé publique Ed25519 brute de 32 octets.
const SPKI_PREFIX = Buffer.from('302a300506032b6570032100', 'hex');

export function verifyEd25519(keyB64url: string, message: string, sigB64url: string): boolean {
  if (!B64URL_KEY.test(keyB64url) || !B64URL_SIG.test(sigB64url)) return false;
  try {
    const raw = Buffer.from(keyB64url, 'base64url');
    const key = createPublicKey({ key: Buffer.concat([SPKI_PREFIX, raw]), format: 'der', type: 'spki' });
    return verify(null, Buffer.from(message, 'utf8'), key, Buffer.from(sigB64url, 'base64url'));
  } catch {
    return false;
  }
}
