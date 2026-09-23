-- +goose Up

-- A report is a write like any other: it arrives through the outbox, under a
-- client-minted op id, and op_log deduplicates it exactly as it does a prayer.
--
-- The column list is the whole promise. A reader's notes, their progress and
-- the corpus they were reading have no column here, and the op decoder refuses
-- a body carrying a key this table has no room for, so "a report must not
-- carry their practice" is a shape rather than a habit.
--
-- There is no user_id, and that is the point: a report is what somebody chose
-- to send, and an operator reading it cannot turn it into a person. Nothing is
-- answered back, so nothing needs a reader to answer to.
--
-- There is no seq either. Reports are one-way, so they never join the change
-- stream and never take a number out of change_seq: a device that flushes a
-- report is told it landed and hears nothing more about it, and its cursor —
-- a position in change_seq — does not move.
CREATE TABLE reports (
  id             uuid PRIMARY KEY,
  kind           text NOT NULL CHECK (kind IN ('bug', 'request', 'improvement')),
  body           text NOT NULL CHECK (body <> '' AND length(body) <= 4000),
  app_version    text NOT NULL CHECK (length(app_version) <= 40),
  platform       text NOT NULL CHECK (platform IN ('android', 'ios', 'macos')),
  screen         text NOT NULL CHECK (length(screen) <= 60),
  -- What the device had bundled, so a report can be tied to a build. Zero is a
  -- device that did not say; refusing the report over it would throw away the
  -- text, which is the part that matters.
  corpus_version int NOT NULL DEFAULT 0,
  created_at     timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX reports_newest ON reports (created_at DESC);

-- The writes the server told a device it could not keep, counted and nothing
-- more: the day, the kind of op, and which of the two words was answered.
-- `refused` is a write the device parks at once; `failed` is one it retries
-- and parks only when its budget runs out. No user_id, so a failure storm can
-- be seen but never followed back to whose prayer was lost.
--
-- ponytail: one row per day, kind and status, so concurrent failures serialise
-- briefly on that row. Count by hour if a storm ever makes that the bottleneck.
CREATE TABLE sync_outcomes (
  day    date NOT NULL DEFAULT current_date,
  kind   text NOT NULL,
  status text NOT NULL,
  ops    bigint NOT NULL,
  PRIMARY KEY (day, kind, status)
);

-- +goose Down
DROP TABLE sync_outcomes, reports;
