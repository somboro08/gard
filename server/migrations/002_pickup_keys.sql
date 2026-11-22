-- Remise sécurisée : clé publique Ed25519 (base64url, 32 octets) du téléphone du client,
-- enrôlée au dépôt, et moyen de vérification utilisé à la remise.
ALTER TABLE vehicles
  ADD COLUMN owner_key TEXT CHECK (owner_key IS NULL OR owner_key ~ '^[A-Za-z0-9_-]{43}$'),
  ADD COLUMN pickup_method TEXT CHECK (pickup_method IN ('key', 'manual'));
