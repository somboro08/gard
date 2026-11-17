# Garde — MVP

Application Flutter pour gérer et sécuriser un **centre de garde de motos, vélos et véhicules** :
enregistrement par scan de plaque, ticket QR / code à 6 chiffres, vérification à la sortie,
liste des véhicules par jour. Base **SQLite** locale (hors-ligne), prête pour PostgreSQL.

## Démarrer (5 minutes)

Ce zip contient le code (`lib/`, `test/`, `pubspec.yaml`) mais pas les dossiers `android/` et `ios/`,
qui doivent être générés par votre propre SDK Flutter :

```bash
cd garde
flutter create --platforms=android,ios --project-name garde --org bj.mrl .
dart run tool/setup_platforms.dart     # caméra, WhatsApp/appel, minSdk 24, iOS 15.5
flutter pub get
flutter analyze                        # doit être propre ; voir « Si l'analyse signale… »
flutter test                           # tests de la logique (plaques, tickets, statuts)
flutter run                            # sur un vrai téléphone (la caméra est nécessaire)
```

`flutter create .` ne touche pas à `lib/`, `pubspec.yaml` ni `test/` qui existent déjà.

> **Important** — ce code a été écrit sans pouvoir être compilé dans l'environnement de génération
> (pas d'accès au SDK Flutter ni à pub.dev). Il a été relu avec soin, mais le premier
> `flutter analyze` peut signaler de petits écarts (noms d'icônes Iconsax, signature d'un paquet
> dont la version a évolué). Voir plus bas comment les corriger vite.

## Parcours

| Écran | Rôle |
|---|---|
| **Premier lancement** | Créer le 1er centre : nom, lieu, durée de garde (6 h, 12 h, 24 h, 48 h ou personnalisée) |
| **Retrouver** (onglet 1) | Semaine en onglets (LUN…DIM), filtres Tous / En cours / Récupérés / Non récupérés, recherche (plaque, nom, téléphone, code), bouton **scan** : QR du ticket, code à 6 chiffres ou plaque |
| **Enregistrer** (onglet 2) | Type (moto/vélo/voiture/autre), plaque (scan caméra + correction), propriétaire, téléphone, remarque → ticket |
| **Ticket** | QR + code à 6 chiffres, copier, envoi WhatsApp |
| **Fiche véhicule** | Infos, **vérification à la sortie** : ticket (QR/code) + plaque scannée comparée caractère par caractère → *Confirmer la remise* |
| **Centres** | Titre de l'écran → feuille : changer de centre, modifier, ajouter (autant que nécessaire) |

Statuts : **En cours** · **Récupéré** (date + heure) · **Non récupéré** (délai de garde du centre dépassé,
calculé automatiquement).

### Vérification de la plaque
`Plates.compare` renvoie :
- **exact** — mêmes caractères ;
- **close** — écart dû aux confusions de l'OCR (O/0, I/1, B/8, S/5…) ou 1 caractère d'écart → l'agent doit valider ;
- **different** — plaque différente → confirmation d'alerte obligatoire pour forcer la remise.

Chaque remise enregistre le résultat (`pickup_check`) et si le ticket a été validé (`ticket_verified`).

## Architecture

```
lib/
  core/     theme (palette or/noir clair+sombre), icônes (Iconsax), formats FR, plaques/tickets
  data/     models, ParkingRepository (interface), SqliteParkingRepository
  state/    AppController (ChangeNotifier) + AppScope (InheritedNotifier)
  ui/
    widgets/  boutons, champs, feuilles, transitions, tuiles, overlays de scan
    pages/    shell (2 onglets), find, register, vehicle, ticket, center_form, scan_qr, scan_plate
    flows.dart  parcours de recherche (QR → fiche, code → fiche, plaque → fiche)
  router.dart  go_router : shell à 2 branches + routes plein écran
tool/setup_platforms.dart   configure android/ et ios/
test/widget_test.dart       tests de logique pure
```

- **Navigation** : `go_router`, `StatefulShellRoute` (onglets conservés en mémoire, transition
  fondu + glissement), pages plein écran avec transitions personnalisées (`slidePage`, `risePage`).
- **Design** : typographie système (Roboto / SF, comme WhatsApp) mais plus grande (18 px de base,
  titres 23–26 px), accent or `#F5B800`, fond noir en sombre, blanc chaud en clair. Tout passe par
  `AppPalette` (`lib/core/theme.dart`) : changer une couleur se fait à un seul endroit.
- **Icônes** : Iconsax, centralisées dans `lib/core/icons.dart` (les types de véhicule moto/vélo
  utilisent les icônes Material car Iconsax n'a pas de moto).

## Base de données

Tables `centers`, `vehicles`, `settings` (schéma dans `sqlite_repository.dart`).
Identifiants en **UUID v4** générés côté appareil → compatibles PostgreSQL sans conversion.
Dates en millisecondes epoch.

### Passer à PostgreSQL plus tard
Tous les écrans passent par l'interface `ParkingRepository` (`lib/data/repository.dart`).
1. Créer une API REST (par ex. Node/Fastify ou FastAPI) avec les mêmes opérations ;
2. écrire `ApiParkingRepository implements ParkingRepository` ;
3. changer **une ligne** dans `main.dart` (`SqliteParkingRepository()` → `ApiParkingRepository(...)`).

Pour un mode hors-ligne + synchronisation : garder SQLite comme cache local et synchroniser par
lots (les UUID évitent les collisions d'identifiants).

## Si l'analyse signale…

- **Nom d'icône Iconsax inconnu** → corriger la ligne dans `lib/core/icons.dart` (un seul fichier).
- **Paramètre inconnu dans `mobile_scanner`, `camera` ou `google_mlkit_text_recognition`** →
  les versions sont indiquées dans `pubspec.yaml`. Ces paquets évoluent vite ; leurs appels sont
  isolés dans `scan_qr_page.dart` et `scan_plate_page.dart`.
- **Thème** : si votre Flutter est très récent et refuse un paramètre de `ThemeData`, tout est dans
  `buildTheme` (`lib/core/theme.dart`).

## Limites connues du MVP (à traiter ensuite)

- **Sécurité du ticket** : le code à 6 chiffres est devinable (1 chance sur 900 000 par essai). Il
  n'est sûr que combiné à la vérification de plaque. Pour la suite : jeton signé côté serveur,
  limitation des essais, puis biométrie (cf. document de cadrage).
- Pas de compte agent / rôles / synchronisation multi-téléphones : les données restent sur
  l'appareil (perdre le téléphone = perdre la base tant qu'il n'y a pas de sauvegarde serveur).
- Pas de tarification ni de paiement Mobile Money (prévu après validation du flux de garde).
- L'OCR (ML Kit) doit être testé sur de vraies plaques béninoises : poussière, boue, angle, nuit.
  Les plaques absentes ou illisibles sont gérées (plaque facultative pour vélos/autres, saisie
  manuelle, validation par le ticket seul avec avertissement).
- Orientation portrait uniquement.

## Build de l'APK avec GitHub Actions

Ce dépôt ne commite pas les dossiers `android/` et `ios/` : ils sont régénérés à chaque build par `flutter create`.

À chaque push sur `main` (ou lancement manuel depuis l'onglet **Actions**), GitHub Actions :

1. installe Flutter (stable) + JDK 17 ;
2. régénère `android/` avec `flutter create --platforms=android --org bj.mrl` ;
3. applique `tool/setup_platforms.dart` (caméra, minSdk 24, etc.) ;
4. lance `flutter pub get`, `flutter analyze` et `flutter test` ;
5. build l'APK **debug** (`flutter build apk`) — pas de keystore nécessaire ;
6. dépose l'APK comme artefact téléchargeable (nom : `garde-apk-debug`, conservé 30 jours).

L'APK finale se trouve sur le runner à :
```
build/app/outputs/flutter-apk/app-debug.apk
```
et est jointe à l'exécution du workflow. Télécharge-la depuis l'onglet **Actions** → sélectionne le run → artefacts.

### Pour activer le CI

1. Crée le dépôt vide sur GitHub (ex. `https://github.com/somboro08/gard.git`).
2. Depuis la racine du projet :

```bash
git init
git add .
git commit -m "feat: add Flutter CI for APK build"
git branch -M main
git remote add origin https://github.com/somboro08/gard.git
git push -u origin main
```

3. Le premier run se lance automatiquement à la fin du push.

