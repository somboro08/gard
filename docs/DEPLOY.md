# Déployer l'API Garde

L'API est un conteneur Node + une base PostgreSQL. Les tables se créent/mettent à jour toutes seules
au démarrage (migrations). Deux voies : **VPS avec Docker** (le plus simple à maîtriser) ou un
**hébergeur géré** (Render, Railway, Fly.io… qui fournit déjà HTTPS et PostgreSQL).

## Variables d'environnement

| Variable | Obligatoire | Rôle |
|---|---|---|
| `DATABASE_URL` | oui | `postgres://utilisateur:mot_de_passe@hôte:5432/base` |
| `JWT_SECRET` | oui en production | 32 caractères minimum : `openssl rand -base64 48`. **Le changer déconnecte tout le monde.** |
| `NODE_ENV` | oui | `production` |
| `PORT` | non | 3000 par défaut |
| `ACCESS_TTL_SECONDS` / `REFRESH_TTL_DAYS` | non | 900 s / 30 jours |

## Voie 1 — VPS (Docker + HTTPS automatique)

1. Louez un petit VPS Linux (1 Go de RAM suffit pour commencer) et installez Docker.
2. Pointez un nom de domaine (ex. `api.votredomaine.com`) vers l'IP du VPS (enregistrement DNS **A**).
3. Sur le VPS :
   ```bash
   git clone https://github.com/somboro08/gard && cd gard/server
   export DOMAIN=api.votredomaine.com
   export JWT_SECRET=$(openssl rand -base64 48)
   export POSTGRES_PASSWORD=$(openssl rand -hex 24)
   docker compose -f docker-compose.prod.yml up -d --build
   ```
   **Notez `JWT_SECRET` et `POSTGRES_PASSWORD` dans un gestionnaire de mots de passe** (ou mettez-les
   dans un fichier `.env` à côté du compose, jamais dans Git), sinon le prochain redémarrage échouera.
4. Vérifiez : `curl https://api.votredomaine.com/health` doit répondre `{"status":"ok",…}`.
5. Pare-feu : n'ouvrez que 22 (SSH), 80 et 443.

Mise à jour : `git pull && docker compose -f docker-compose.prod.yml up -d --build`.

## Voie 2 — Hébergeur géré

Créez une base PostgreSQL et un service « Docker » pointant sur le dossier `server/` (il contient le
`Dockerfile`). Renseignez les variables ci-dessus (`DATABASE_URL` fournie par l'hébergeur). L'hébergeur
place l'API derrière son propre HTTPS ; vérifiez `/health`.

## Test de bout en bout (à faire avant d'utiliser l'app)

```bash
cd server
node scripts/smoke.mjs https://api.votredomaine.com
```
Il crée deux comptes jetables et un centre de test, puis vérifie : comptes, ajout d'un agent, dépôt
fait hors-ligne (code et heures conservés), paiement rejoué sans doublon, remise, flux de
synchronisation, rotation des jetons. 15 lignes `✓` = le serveur est prêt. (Ces données de test
restent en base ; elles n'affectent pas les vrais centres.)

## Brancher l'application

- Au build : `flutter build apk --dart-define=API_URL=https://api.votredomaine.com`
- Ou dans l'app : Réglages › Compte et synchronisation › Serveur.

Première utilisation : créer le compte (Compte et synchronisation) → les centres et véhicules déjà
enregistrés sur le téléphone sont envoyés automatiquement (barre de progression). L'agent crée son
compte sur son téléphone, puis le propriétaire l'ajoute dans **Réglages › Équipe du centre**.

## Sauvegardes et surveillance

- Sauvegarde quotidienne (à mettre en `cron`) :
  `docker compose -f docker-compose.prod.yml exec -T db pg_dump -U garde garde | gzip > garde-$(date +%F).sql.gz`
  puis copiez le fichier **hors du serveur**. Testez une restauration au moins une fois.
- Surveillance gratuite de `/health` (UptimeRobot, Better Stack…) avec alerte SMS/e-mail.
- Journaux : `docker compose -f docker-compose.prod.yml logs -f api`.

## Sécurité — rappels

- Ne jamais exposer le port 3000 directement : le serveur fait confiance à l'en-tête du proxy pour
  l'adresse IP (limitation de débit), donc il doit rester derrière Caddy/l'hébergeur.
- HTTPS obligatoire : les jetons de connexion circulent dans les requêtes.
- Pas de fournisseur SMS branché : pas de récupération de mot de passe par SMS pour l'instant
  (à ajouter avec la remise sécurisée).
