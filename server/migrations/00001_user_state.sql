-- +goose Up

-- A reader is minted on first sight of a verified subject; nothing else creates one.
CREATE TABLE users (
  id           uuid PRIMARY KEY,
  oidc_subject text NOT NULL UNIQUE,
  created_at   timestamptz NOT NULL DEFAULT now()
);

-- Every user-owned id below is minted on the device, so a row created offline
-- already carries the identity the flush will be deduplicated by.
CREATE TABLE sets (
  id            uuid PRIMARY KEY,
  user_id       uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  ordinal       int NOT NULL,
  start_ayah_id int NOT NULL,
  end_ayah_id   int NOT NULL,
  reading_order text NOT NULL CHECK (reading_order IN ('nuzul', 'mushaf')),
  created_at    timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, ordinal)
);

CREATE TABLE user_prefs (
  user_id       uuid PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  reading_order text NOT NULL DEFAULT 'nuzul' CHECK (reading_order IN ('nuzul', 'mushaf')),
  updated_at    timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE set_prayers (
  id          uuid PRIMARY KEY,
  set_id      uuid NOT NULL REFERENCES sets(id) ON DELETE CASCADE,
  user_id     uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  prayer_name text NOT NULL,
  prayed_at   timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE ayah_understood (
  id            uuid PRIMARY KEY,
  user_id       uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  ayah_id       int NOT NULL,
  understood_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, ayah_id)
);

CREATE TABLE root_known (
  id           uuid PRIMARY KEY,
  user_id      uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  root_letters text NOT NULL,
  learned_at   timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, root_letters)
);

-- deleted_at is a tombstone. A hard delete here is a note the other device
-- hands straight back on the next pull.
CREATE TABLE kept_items (
  id           uuid PRIMARY KEY,
  user_id      uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  kind         text NOT NULL CHECK (kind IN ('aya', 'root', 'note')),
  ayah_id      int,
  root_letters text,
  body         text NOT NULL DEFAULT '',
  tags         text[] NOT NULL DEFAULT '{}',
  created_at   timestamptz NOT NULL,
  updated_at   timestamptz NOT NULL,
  deleted_at   timestamptz
);
CREATE INDEX kept_items_live ON kept_items (user_id, kind, created_at DESC) WHERE deleted_at IS NULL;

-- The op id is the key, not a column: a flush that timed out after the server
-- applied it replays onto the same row instead of counting a second prayer.
CREATE TABLE op_log (
  user_id      uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  client_op_id uuid NOT NULL,
  applied_at   timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, client_op_id)
);
CREATE INDEX op_log_applied_at ON op_log (applied_at);

-- +goose Down
DROP TABLE op_log, kept_items, root_known, ayah_understood, set_prayers, user_prefs, sets, users;
