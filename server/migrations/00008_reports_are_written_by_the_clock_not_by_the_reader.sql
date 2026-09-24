-- +goose Up

-- The fourth channel, and the one that settled what kind of problem this is.
-- applyReport spent a transaction id of its own — a second one, beside the
-- op's — and the rewrite that followed left that id carried by no live row
-- anywhere in the schema. A gap in the sequence, sitting immediately above the
-- op_log row of the reader who caused it. Walking the gaps named three
-- reporters out of three against a real Postgres, off a plain SELECT, with no
-- statement log and no superuser. The daily regroup did not mitigate it, it
-- finished it: it turned the last report's transaction into a gap like the
-- rest, taking the walk from two of three to three of three.
--
-- Four channels, each one made by the fix before it, is not four careless
-- fixes. Every one was a patch on an observable left behind by writing a
-- report at the moment one particular reader was talking to the database. The
-- op id, the shared transaction, the position on disk, the clock and now the
-- gap are one fact in five costumes: the write happened when the reader did.
--
-- So the write stops happening then. A report lands in report_inbox inside the
-- op's own transaction — no second transaction, nothing minted, nothing spent
-- that the op_log row does not already account for, so no gap — and a sweep on
-- a fixed clock moves it into reports under a transaction that belongs to the
-- schedule. The sweep runs on its tick whether or not anything arrived, so the
-- transaction id every report row carries is a fact about the clock and about
-- nothing else, and the id below it is whoever happened to be writing at the
-- tick rather than necessarily a reporter.
--
-- What is NOT closed, stated here rather than discovered a sixth time: a row
-- sitting in report_inbox carries its author's transaction id, openly, because
-- it is written in the author's transaction. That window is one sweep interval
-- wide and somebody with a SQL prompt inside it can attribute what is sitting
-- there. It is the price of not spending a transaction to hide in. Nothing in
-- reports can be attributed; report_inbox is not read by the operations view
-- and holds only what has not been swept yet. docs/adr/0004 carries the whole
-- of it, including what an operator with raw SQL can still do.
--
-- The checks are the same as reports', so a report nobody triages is still
-- refused where the reader can be told about it rather than at the sweep,
-- where there is nobody left to tell.
--
-- There is no id column. An id minted in the reader's transaction would be one
-- more thing from that moment surviving into the table an operator reads; the
-- sweep mints it instead.
CREATE TABLE report_inbox (
  kind           text NOT NULL CHECK (kind IN ('bug', 'request', 'improvement')),
  body           text NOT NULL CHECK (body <> '' AND length(body) <= 4000),
  app_version    text NOT NULL CHECK (length(app_version) <= 40),
  platform       text NOT NULL CHECK (platform IN ('android', 'ios', 'macos')),
  screen         text NOT NULL CHECK (length(screen) <= 60),
  corpus_version int NOT NULL DEFAULT 0,
  written_on     date NOT NULL DEFAULT current_date
);

-- The reports already here were each written in a transaction of their own,
-- and those ids are gaps now. A gap cannot be filled, so what goes instead is
-- the thing that made it say a name: the row directly below it. Every row a
-- reader's writes left behind is given a new version under this migration's
-- transaction id, which puts all of them at one id and leaves no user-bearing
-- row sitting under any historical gap.
--
-- SET col = col rather than a DELETE and re-INSERT: sets cascades to
-- set_prayers, so deleting a row to write it back would take its children with
-- it. An update of a column nothing references rewrites the row version and
-- touches no key and no foreign key.
UPDATE users           SET created_at    = created_at;
UPDATE op_log          SET applied_at    = applied_at;
UPDATE sets            SET created_at    = created_at;
UPDATE set_prayers     SET prayed_at     = prayed_at;
UPDATE ayah_understood SET understood_at = understood_at;
UPDATE root_known      SET learned_at    = learned_at;
UPDATE kept_items      SET updated_at    = updated_at;
UPDATE user_prefs      SET updated_at    = updated_at;

-- +goose Down

-- Anything not yet swept is lost with the table, which is the honest shape of
-- a down migration over a queue: the reports that were swept are in reports,
-- and the ones in flight were never anywhere else.
DROP TABLE report_inbox;
