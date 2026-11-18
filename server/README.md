# Garde — API

API REST (Fastify + TypeScript) sur **PostgreSQL**. Elle remplace la base locale SQLite de l'appli
quand tu es prêt : mêmes concepts (centres, véhicules, paiements), plus **comptes**, **agents par
centre**, **journal d'audit** et un flux de **synchronisation** pour le mode hors-ligne.

## Démarrer

```bash
cd server
cp .env.example .env            # puis renseigner DATABASE_URL et JWT_SECRET
npm install
npm run migrate                 # crée/met à jour les tables
npm run dev                     # http://localhost:3000/health
```

Avec Docker : `JWT_SECRET=$(openssl rand -base64 48) docker compose up --build`.
Tests : `DATABASE_URL=postgres://user:mdp@localhost:5432/garde_test npm test`
(⚠ le schéma `public` de cette base est **effacé** à chaque lancement : base de test dédiée uniquement).

## Modèle d'accès

- Un **compte** = numéro de téléphone (normalisé, indicatif 229) + mot de passe (scrypt).
- Un **centre** a des **membres** : `owner` (gère centre, tarifs, agents, suppressions) et `agent`
  (enregistre, encaisse, remet). Un utilisateur peut avoir plusieurs centres, avec un rôle par centre.
- Tout est cloisonné par centre : un centre/véhicule qui n'est pas le tien répond **404** (jamais 403),
  pour ne pas révéler son existence.
- Jeton d'accès JWT de 15 min + jeton de rafraîchissement opaque de 30 jours, **rotatif** : le rejouer
  révoque toute la session (vol probable).

## Endpoints

Tous (sauf `/health` et `/auth/*`) exigent `Authorization: Bearer <accessToken>`.
Dates en ISO 8601 UTC, montants en FCFA entiers.

| Méthode | Route | Rôle |
|---|---|---|
| POST | `/auth/register` · `/auth/login` · `/auth/refresh` · `/auth/logout` | comptes |
| GET | `/auth/me` | profil |
| GET/POST | `/centers` | mes centres / créer (id client optionnel → idempotent) |
| GET/PATCH/DELETE | `/centers/:id` | lire / modifier (owner) / supprimer (owner) |
| GET/POST/DELETE | `/centers/:id/members[/:userId]` | agents (ajout par numéro, owner) |
| POST | `/centers/:id/vehicles` | dépôt : tarif, échéance et code 6 chiffres calculés côté serveur |
| GET | `/centers/:id/vehicles?from&to` · `/active` · `/search?q` · `/by-plate/:key` · `/by-code/:code` | consultation |
| GET/PATCH/DELETE | `/vehicles/:id` | lire / modifier / supprimer (owner) |
| POST | `/vehicles/:id/collect` | remise, une seule fois (`409 already_collected`) |
| POST | `/vehicles/:id/payments` | encaissement (jamais au-delà du solde : `409 overpayment`) |
| GET | `/centers/:id/payments?from&to` · `/pending` | revenus / reste à encaisser |
| GET | `/centers/:id/changes?since=` | changements pour la synchro (véhicules, paiements, suppressions) |

Erreurs : `{ "error": "code_machine", "message": "texte lisible" }`.

## Hors-ligne et synchronisation

Les créations (`centers`, `vehicles`, `payments`) acceptent un `id` UUID généré par l'appli et sont
**idempotentes** : rejouer la même requête après une coupure réseau ne crée pas de doublon.
`depositedAt` / `paidAt` permettent d'envoyer l'heure réelle d'une opération faite hors-ligne
(dépôt : entre 30 jours dans le passé et 1 h dans le futur).
Pour se synchroniser : `GET /centers/:id/changes?since=<serverTime précédent − 5 s>` (la marge de 5 s
absorbe les transactions longues ; le rejeu est sans danger).

## Sécurité — ce qui est fait, ce qui reste

Fait : mots de passe scrypt, comparaison à temps constant, pas d'énumération de comptes, limitation de
débit (connexion : 10/min, recherche par code : 30/min, global : 300/min), validation stricte des
entrées (zod), requêtes paramétrées, recherche sans injection de motif LIKE, verrous contre les
encaissements simultanés, journal d'audit (`audit_log`), 0 vulnérabilité connue (`npm audit`).

À faire avant la production : HTTPS (reverse proxy : Caddy/nginx), sauvegardes PostgreSQL,
vérification du numéro par SMS (OTP) et récupération de mot de passe, limitation par compte
en plus de l'IP, et le **retrait sécurisé par clé** (voir la feuille de route : le code à 6 chiffres
seul reste devinable ; la limite de 30 essais/min le rend impraticable à force brute mais ne remplace
pas la preuve de possession du téléphone du propriétaire).
