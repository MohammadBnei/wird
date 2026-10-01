-- +goose Up

-- Where the reader is in each sūra: the word the reading screen last stood on.
-- One row per sūra, so another device opens a sūra where it was left, and the
-- home screen can offer every sūra in progress. A position is not progress:
-- what the reader understood stays in ayah_understood (ADR 0015).
--
-- The id is the row's, kept across moves, because the change stream needs a
-- uuid per row and (user_id, surah_id) is not one.
CREATE TABLE reading_positions (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  surah_id   smallint NOT NULL CHECK (surah_id BETWEEN 1 AND 114),
  word_id    bigint NOT NULL,
  updated_at timestamptz NOT NULL,
  seq        bigint NOT NULL DEFAULT nextval('change_seq'),
  UNIQUE (user_id, surah_id)
);

CREATE INDEX reading_positions_seq ON reading_positions (user_id, seq);

-- +goose Down
DROP TABLE reading_positions;
