-- +goose Up

-- Every sense a reader could see was frozen into app/assets/corpus.db, which
-- ships inside the app binary, so publishing a correction cost a store
-- release. The app already ships a thumb asking the reader whether a sense is
-- right, so corrections arrive continuously against a publishing path measured
-- in weeks. docs/adr/0010 moves the authorship line: what Wird wrote is
-- served, what came from an upstream source stays bundled. This table is the
-- served half, and it is the single source of truth for a root's sense.
--
-- The primary key IS the last-row-per-root rule. The drafting log carries 2,306
-- rows for 1,642 roots — 553 roots were drafted more than once — and its own
-- rule is that the last row for a root wins. server/cmd/senseseed inserts in
-- file order with ON CONFLICT (root_letters) DO UPDATE, so the rule is the key
-- rather than selection code. One statement per row, because a single
-- multi-row INSERT with ON CONFLICT DO UPDATE refuses to touch the same key
-- twice ("cannot affect row a second time") and would die on the 554th.
--
-- No Arabic-range CHECK. The seeder validates every root against the 1,642 in
-- the roots table of corpus.db and refuses an unknown one by name, which is a
-- better check than a code-point range: a root that is Arabic and not in the
-- corpus is a sense no caller could ever reach.
--
-- No `reviewed` column. The signing workflow is deferred (ADR 0010, Out of
-- scope), and a boolean carrying one value in every row teaches nothing while
-- every client has to learn to ignore it. The honest statement lives once, as
-- the pack-level `basis` beside the handler that serves it.
--
-- poetic_en and poetic_fr are stored and never served. 1,642 model calls
-- produced that register and nothing else holds it, but the app has no column
-- and no widget for it, and jidhr/pkg/root/meaning_test.go already fails any
-- corpus carrying one — it is gated separately and has its own battery to
-- write. Stored here so the drafting is not thrown away; absent from the route,
-- which is where the gate would have to be re-argued.
CREATE TABLE root_senses (
  root_letters text PRIMARY KEY CHECK (root_letters <> '' AND length(root_letters) <= 32),
  sense_en     text NOT NULL CHECK (sense_en <> ''),
  sense_fr     text NOT NULL CHECK (sense_fr <> ''),
  poetic_en    text,
  poetic_fr    text,
  updated_at   timestamptz NOT NULL DEFAULT now()
);

-- The other half of the same decision, and it is not tidying. A report says
-- `corpus_version` and report.dart calls that "what says WHICH sense was
-- judged". The moment senses arrive over HTTP that is false: two readers on
-- the same bundle can judge two different sentences and both report 3. The
-- verdict loop exists to produce an attributable judgement of a particular
-- piece of prose, so without this column every thumb collected after the route
-- ships is data nobody can act on.
--
-- It goes on both tables a report passes through, because the inbox holds the
-- same text for a sweep interval and a column missing there is the value
-- dropped on the way to reports.
--
-- text rather than an int: the pack version is a revision prefix and a content
-- hash, not a counter. '' is a device that did not say — the same reading
-- corpus_version gives 0 — because refusing the report over a missing version
-- would throw away the reader's words, which are the part that matters.
ALTER TABLE reports      ADD COLUMN sense_version text NOT NULL DEFAULT ''
  CHECK (length(sense_version) <= 64);
ALTER TABLE report_inbox ADD COLUMN sense_version text NOT NULL DEFAULT ''
  CHECK (length(sense_version) <= 64);

-- +goose Down

ALTER TABLE report_inbox DROP COLUMN sense_version;
ALTER TABLE reports      DROP COLUMN sense_version;
DROP TABLE root_senses;
