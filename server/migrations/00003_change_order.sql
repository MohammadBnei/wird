-- +goose Up

-- What the change stream is ordered by, and what a sync cursor is a position
-- in. The device's own clock cannot do this job: a write made on a plane on
-- Monday and flushed on Friday carries Monday's instant, so a tablet that
-- synced on Wednesday is already past it and would never be told the write
-- exists. This number is assigned by the server, in the order writes land.
--
-- Client timestamps stay as data: they are what last-write-wins compares.
-- They no longer decide what a reader is told about.
CREATE SEQUENCE change_seq;

ALTER TABLE ayah_understood ADD COLUMN seq bigint NOT NULL DEFAULT nextval('change_seq');
ALTER TABLE kept_items      ADD COLUMN seq bigint NOT NULL DEFAULT nextval('change_seq');
ALTER TABLE sets            ADD COLUMN seq bigint NOT NULL DEFAULT nextval('change_seq');
ALTER TABLE set_prayers     ADD COLUMN seq bigint NOT NULL DEFAULT nextval('change_seq');
ALTER TABLE user_prefs      ADD COLUMN seq bigint NOT NULL DEFAULT nextval('change_seq');

CREATE INDEX ayah_understood_seq ON ayah_understood (user_id, seq);
CREATE INDEX kept_items_seq      ON kept_items (user_id, seq);
CREATE INDEX sets_seq            ON sets (user_id, seq);
CREATE INDEX set_prayers_seq     ON set_prayers (user_id, seq);

-- +goose Down
DROP INDEX set_prayers_seq, sets_seq, kept_items_seq, ayah_understood_seq;
ALTER TABLE user_prefs      DROP COLUMN seq;
ALTER TABLE set_prayers     DROP COLUMN seq;
ALTER TABLE sets            DROP COLUMN seq;
ALTER TABLE kept_items      DROP COLUMN seq;
ALTER TABLE ayah_understood DROP COLUMN seq;
DROP SEQUENCE change_seq;
