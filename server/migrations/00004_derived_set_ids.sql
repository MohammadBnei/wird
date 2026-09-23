-- +goose Up

-- A set's id is now derived from what the set is — uuidv5 over its reading
-- order and its range — rather than minted. Two readers who pray al-Fātiḥa
-- therefore derive the same uuid, so identity has to be per reader: with a
-- global primary key the second reader's set would collide, be refused, and
-- take that reader's prayer down with it.
ALTER TABLE set_prayers DROP CONSTRAINT set_prayers_set_id_fkey;
ALTER TABLE sets DROP CONSTRAINT sets_pkey;
ALTER TABLE sets ADD CONSTRAINT sets_pkey PRIMARY KEY (user_id, id);
ALTER TABLE set_prayers ADD CONSTRAINT set_prayers_set_id_fkey
  FOREIGN KEY (user_id, set_id) REFERENCES sets (user_id, id) ON DELETE CASCADE;

-- +goose Down
ALTER TABLE set_prayers DROP CONSTRAINT set_prayers_set_id_fkey;
ALTER TABLE sets DROP CONSTRAINT sets_pkey;
ALTER TABLE sets ADD CONSTRAINT sets_pkey PRIMARY KEY (id);
ALTER TABLE set_prayers ADD CONSTRAINT set_prayers_set_id_fkey
  FOREIGN KEY (set_id) REFERENCES sets (id) ON DELETE CASCADE;
