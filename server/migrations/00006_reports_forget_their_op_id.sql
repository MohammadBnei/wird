-- +goose Up

-- Reports written before this were stored under the op id they arrived with,
-- and op_log holds that id against the reader who sent it for the ninety days
-- of the replay window. Rows already here therefore still name their authors,
-- which a fix applied only to new inserts would leave standing. Nothing
-- references reports.id, so re-keying them costs nothing and ends the link for
-- the reports already sent.
UPDATE reports SET id = gen_random_uuid();

-- +goose Down

-- The op ids are gone, and inventing new ones would not bring the authors back.
SELECT 1;
