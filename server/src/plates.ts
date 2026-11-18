// Portage fidèle de lib/core/plates.dart (clé de comparaison des plaques).

/** « ab-1234  rb » → « AB1234RB » */
export const plateKey = (raw: string): string => raw.toUpperCase().replace(/[^A-Z0-9]/g, '');

/** « ab-1234  rb » → « AB 1234 RB » */
export const plateDisplay = (raw: string): string =>
  raw.toUpperCase().replace(/[^A-Z0-9]+/g, ' ').trim();

/**
 * Numéro normalisé (indicatif Bénin 229 ajouté si absent) — même règle que Phones.waNumber.
 * Retourne '' si le numéro est vide ou invalide.
 */
export function normalizePhone(raw: string): string {
  let d = raw.replace(/[^0-9]/g, '');
  if (d.startsWith('00')) d = d.slice(2);
  if (!d) return '';
  if (d.startsWith('229') && d.length >= 11) return d;
  if (d.length <= 10) return `229${d}`;
  return d;
}
