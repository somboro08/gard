# Remise sécurisée du véhicule — protocole (à implémenter : phase propriétaire)

Objectif : qu'un véhicule ne soit remis qu'à son propriétaire, même si le ticket est perdu ou
copié, y compris **sans réseau** côté agent.

## Principe
1. **Au dépôt**, l'application du propriétaire génère une paire de clés (clé privée dans le
   Keystore/Keychain, non exportable). La clé **publique** est envoyée au dépôt (QR/saisie) et
   stockée avec le véhicule (`vehicles.owner_pubkey`).
2. **À la remise**, l'agent affiche un **défi** (nonce aléatoire + code véhicule + heure). Le
   téléphone du propriétaire le **signe** (après biométrie/PIN) et renvoie la signature par QR.
   L'agent vérifie avec la clé publique **hors-ligne**. Défi à usage unique, valable 2 minutes.
3. **QR tournant** (alternative) : le téléphone du propriétaire affiche un QR signé contenant
   `code | fenêtre de 30 s`, vérifiable hors-ligne par l'agent.

## Repli si le téléphone est perdu / sans batterie
- **OTP SMS** envoyé au numéro du propriétaire enregistré au dépôt (nécessite le réseau côté
  propriétaire seulement), saisi par l'agent.
- Sinon : contrôle manuel actuel (plaque + pièce) avec **journal d'audit** renforcé
  (`pickup_check = 'skipped'`, agent, heure) — visible du propriétaire du centre.

## Modèle de menaces couvert
Ticket volé/photographié (inutile sans la clé), agent malveillant (ne peut pas fabriquer une
signature, remises tracées), rejeu (nonce + expiration), collision de codes (clé publique liée
au véhicule).

## Travail restant
Colonne `owner_pubkey`, endpoints d'enrôlement et de vérification (miroir serveur), écrans agent
(scanner/afficher défi), application propriétaire, gestion de la rotation/révocation des clés.
