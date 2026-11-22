# Remise sécurisée du véhicule

**Statut : implémentée (v1).** Un véhicule « sécurisé » ne peut être remis avec preuve que si le
téléphone du client signe un défi choisi par l'agent. Tout fonctionne **hors-ligne** (QR dans les
deux sens) et le serveur **revérifie la même preuve** à la synchronisation.

## Principe

1. **Enrôlement (au dépôt).** L'agent ouvre le ticket › « Sécuriser avec le téléphone du client » et
   montre un QR. Le client, dans l'app (Espace client › Scanner un QR du centre), scanne et valide.
   Son téléphone crée une paire de clés **Ed25519 propre à ce véhicule** (clé secrète dans le
   Keystore/Keychain, jamais envoyée) et affiche un QR de réponse : clé publique + signature de
   `GARDE-ENROLL-1|<vehicleId>|<nonce>`. L'agent scanne, vérifie, et enregistre la clé publique.
2. **Remise (à la sortie).** L'agent ouvre la fiche › « Téléphone du client › Vérifier » : QR de défi
   avec un nonce frais (valable 3 min). Le client scanne et valide ; son téléphone répond avec la
   signature de `GARDE-PICKUP-1|<vehicleId>|<nonce>`. L'agent vérifie avec la clé publique enrôlée.
   Le ticket n'est alors plus nécessaire (client sans ticket, mais avec son téléphone : OK).
3. **Serveur.** La remise part avec `pickupMethod: "key"` et la preuve (`nonce`, `sig`). Le serveur
   la revérifie contre la clé enrôlée (422 `invalid_proof` sinon) : un agent ne peut pas écrire
   « vérifié par clé » sans preuve valable. Journal d'audit : méthode de remise.

## Repli (client sans son téléphone)
L'agent peut confirmer quand même (avertissement explicite) : la remise est enregistrée en
**« contrôle manuel »**, visible sur la fiche (« Remis SANS la clé du client ») et dans l'audit.
Pas de SMS pour l'instant (aucun fournisseur branché).

## Menaces couvertes
- Ticket volé, photographié ou partagé par WhatsApp : inutile sans le téléphone enrôlé.
- Rejeu d'une réponse enregistrée : le nonce est frais à chaque défi et lié au véhicule.
- Preuve d'enrôlement réutilisée comme preuve de remise : messages préfixés différemment.
- Agent qui prétend avoir vérifié : le serveur revérifie la signature.
- Un téléphone par véhicule : aucune corrélation entre deux centres ou deux dépôts.

## Limites connues (à traiter ensuite)
- Une seule clé par véhicule, jamais remplaçable (téléphone perdu → remise manuelle tracée).
- Pas de biométrie/code sur le téléphone du client : un téléphone déverrouillé suffit.
  (Prochaine étape : `local_auth` + clé protégée par le Keystore.)
- Un agent malveillant peut enrôler **sa propre clé** à la place de celle du client (collusion
  agent + voleur) : l'enrôlement doit se faire devant le client. Contre-mesure possible : envoyer
  au client un SMS/notification quand une clé est enrôlée.
- Le propriétaire du centre n'a pas encore d'écran d'audit des remises « manuelles » sur véhicules sécurisés.

## Fichiers
`lib/security/pickup_crypto.dart` (protocole, tests dans `test/pickup_crypto_test.dart`, vecteur
partagé avec Node), `server/src/pickup.ts`, `server/migrations/002_pickup_keys.sql`,
`lib/ui/pages/{exchange,client}_page.dart`.
