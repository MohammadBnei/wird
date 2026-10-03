-- +goose Up

-- A reader who deleted their account. Deleting the users row takes every row
-- they own with it (each user_id cascades), but EnsureUser mints a reader on
-- first sight of a verified subject, so the next request from a phone still
-- holding a token would bring the account straight back, and its outbox would
-- refill it.
--
-- So the deletion leaves this behind: the moment it happened, keyed by a hash
-- of the subject rather than the subject itself. The middleware refuses any
-- token for that subject whose sign-in (auth_time) came before the deletion. A
-- refresh keeps auth_time, so a refreshed token on a second device is refused
-- too; a fresh sign-in after the deletion starts a new, empty account.
CREATE TABLE deleted_readers (
  subject_hash bytea PRIMARY KEY,
  deleted_at   timestamptz NOT NULL DEFAULT now()
);

-- +goose Down
DROP TABLE deleted_readers;
