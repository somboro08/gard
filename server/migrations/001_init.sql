-- Garde — schéma initial (PostgreSQL 13+)
-- Les identifiants sont des UUID générés par le client OU par le serveur
-- (le client hors-ligne peut créer ses lignes puis les synchroniser).
-- Argent : entiers en FCFA (pas de décimales).

CREATE TABLE users (
  id            UUID PRIMARY KEY,
  phone         TEXT NOT NULL UNIQUE,            -- format E.164 sans « + » (ex. 22901234567)
  name          TEXT NOT NULL,
  password_hash TEXT NOT NULL,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE refresh_tokens (
  id          UUID PRIMARY KEY,
  user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  family_id   UUID NOT NULL,                     -- une famille = une session d'appareil
  token_hash  TEXT NOT NULL UNIQUE,              -- SHA-256 du jeton (jamais le jeton lui-même)
  expires_at  TIMESTAMPTZ NOT NULL,
  revoked_at  TIMESTAMPTZ,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_refresh_user ON refresh_tokens(user_id);
CREATE INDEX idx_refresh_family ON refresh_tokens(family_id);

CREATE TABLE centers (
  id            UUID PRIMARY KEY,
  name          TEXT NOT NULL,
  location      TEXT NOT NULL DEFAULT '',
  guard_hours   INTEGER NOT NULL CHECK (guard_hours BETWEEN 1 AND 720),
  price_moto    INTEGER NOT NULL DEFAULT 0 CHECK (price_moto >= 0),
  price_velo    INTEGER NOT NULL DEFAULT 0 CHECK (price_velo >= 0),
  price_voiture INTEGER NOT NULL DEFAULT 0 CHECK (price_voiture >= 0),
  price_autre   INTEGER NOT NULL DEFAULT 0 CHECK (price_autre >= 0),
  created_by    UUID REFERENCES users(id) ON DELETE SET NULL,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Qui a accès à quel centre : « owner » gère le centre et ses agents,
-- « agent » enregistre / encaisse / remet les véhicules.
CREATE TABLE center_members (
  center_id  UUID NOT NULL REFERENCES centers(id) ON DELETE CASCADE,
  user_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  role       TEXT NOT NULL CHECK (role IN ('owner', 'agent')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (center_id, user_id)
);
CREATE INDEX idx_members_user ON center_members(user_id);

CREATE TABLE vehicles (
  id              UUID PRIMARY KEY,
  center_id       UUID NOT NULL REFERENCES centers(id) ON DELETE CASCADE,
  code            TEXT NOT NULL CHECK (code ~ '^[0-9]{6}$'),
  plate           TEXT NOT NULL DEFAULT '',
  plate_key       TEXT NOT NULL DEFAULT '',
  type            TEXT NOT NULL CHECK (type IN ('moto', 'velo', 'voiture', 'autre')),
  owner_name      TEXT NOT NULL,
  owner_phone     TEXT NOT NULL DEFAULT '',
  note            TEXT NOT NULL DEFAULT '',
  deposited_at    TIMESTAMPTZ NOT NULL,
  due_at          TIMESTAMPTZ NOT NULL,
  collected_at    TIMESTAMPTZ,
  pickup_check    TEXT CHECK (pickup_check IN ('exact', 'close', 'different', 'skipped')),
  ticket_verified BOOLEAN NOT NULL DEFAULT false,
  price           INTEGER NOT NULL DEFAULT 0 CHECK (price >= 0),
  paid_amount     INTEGER NOT NULL DEFAULT 0 CHECK (paid_amount >= 0),
  created_by      UUID REFERENCES users(id) ON DELETE SET NULL,
  collected_by    UUID REFERENCES users(id) ON DELETE SET NULL,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
-- Un code à 6 chiffres est unique parmi les véhicules encore en garde d'un centre.
CREATE UNIQUE INDEX uq_vehicles_active_code
  ON vehicles(center_id, code) WHERE collected_at IS NULL;
CREATE INDEX idx_vehicles_center_day ON vehicles(center_id, deposited_at);
CREATE INDEX idx_vehicles_plate ON vehicles(center_id, plate_key);
CREATE INDEX idx_vehicles_changes ON vehicles(center_id, updated_at);

CREATE TABLE payments (
  id         UUID PRIMARY KEY,
  vehicle_id UUID NOT NULL REFERENCES vehicles(id) ON DELETE CASCADE,
  center_id  UUID NOT NULL REFERENCES centers(id) ON DELETE CASCADE,
  amount     INTEGER NOT NULL CHECK (amount > 0),
  method     TEXT NOT NULL CHECK (method IN ('cash', 'wallet')),
  paid_at    TIMESTAMPTZ NOT NULL,
  created_by UUID REFERENCES users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_payments_center_day ON payments(center_id, paid_at);
CREATE INDEX idx_payments_vehicle ON payments(vehicle_id);
CREATE INDEX idx_payments_changes ON payments(center_id, created_at);

-- Journal d'audit : qui a fait quoi (remises, encaissements, suppressions…).
-- Volontairement sans clé étrangère : il survit à la suppression d'un véhicule.
CREATE TABLE audit_log (
  id        BIGSERIAL PRIMARY KEY,
  center_id UUID NOT NULL,
  user_id   UUID,
  action    TEXT NOT NULL,
  entity    TEXT NOT NULL,
  entity_id UUID,
  details   JSONB NOT NULL DEFAULT '{}'::jsonb,
  at        TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_audit_center ON audit_log(center_id, at DESC);

-- Suppressions de véhicules, pour que les clients hors-ligne les apprennent.
CREATE TABLE deleted_vehicles (
  id         UUID PRIMARY KEY,
  center_id  UUID NOT NULL,
  deleted_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_deleted_vehicles ON deleted_vehicles(center_id, deleted_at);
