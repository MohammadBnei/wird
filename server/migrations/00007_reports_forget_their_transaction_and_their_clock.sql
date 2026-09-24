-- +goose Up

-- Two more ways a report named its author, neither of them visible in the
-- column list, and both proved against a real database rather than argued.
--
-- What this migration decided has since been undone by 00008, and the rewrite
-- it describes below is no longer what a report write does: giving the report
-- a transaction of its own spent an id that the rewrite then left carried by
-- no live row, which is a gap in the sequence sitting directly above the
-- author's op_log row. Read 00008 for the shape that replaced it.
--
-- The first was the transaction. The report row and the op_log row that holds
-- its op id against its author were written in one transaction, so both row
-- versions carried the same xmin. xmin is a system column and any role that
-- can SELECT can read it, which platform-admins can, so
-- `JOIN op_log o ON o.xmin = r.xmin` named the author of every report.
-- Writing them in two transactions is not enough on its own: transaction ids
-- are handed out in order, so a report committed between two of a reader's ops
-- still sits next to them. So every report write now rewrites the whole table
-- in one transaction — every row deleted and written again together — and all
-- of them end up carrying that one transaction id. No report's xmin is nearer
-- its author's op_log row than any other report's is.
--
-- The rewrite is ordered by id, which is a random uuid, because a heap appends
-- and the order rows sit in on disk would otherwise be the order they arrived
-- in, which an operator can walk beside op_log's timestamps.
--
-- The second was the clock. created_at was the device's own time to the
-- microsecond, and a report written online is flushed within two minutes, so
-- the op_log row nearest it in time was its author's. An operator reads
-- reports by day, so the column becomes a date and is renamed for what it now
-- holds. What is lost is the time of day, which no one was reading.
ALTER TABLE reports RENAME COLUMN created_at TO written_on;
ALTER TABLE reports ALTER COLUMN written_on TYPE date USING (written_on AT TIME ZONE 'UTC')::date;
ALTER TABLE reports ALTER COLUMN written_on SET DEFAULT current_date;

-- The rows already here were written inside their author's transaction, and a
-- fix applied only to new inserts would leave that standing. Rewriting them
-- together puts every one of them under this migration's transaction id.
WITH gone AS (DELETE FROM reports RETURNING *)
INSERT INTO reports (id, kind, body, app_version, platform, screen, corpus_version, written_on)
SELECT id, kind, body, app_version, platform, screen, corpus_version, written_on
  FROM gone ORDER BY id;

-- +goose Down

-- The times of day are gone and midnight is the best this can do.
ALTER TABLE reports ALTER COLUMN written_on TYPE timestamptz USING written_on::timestamptz;
ALTER TABLE reports ALTER COLUMN written_on SET DEFAULT now();
ALTER TABLE reports RENAME COLUMN written_on TO created_at;
