-- +goose Up

-- Reports used to be read once, on a page, and forgotten. Now an operator — or
-- an agent working through them — sorts each one and says what became of it,
-- and the sense verdicts are counted per root instead of read one by one.
-- docs/adr/0026 records the decision; this is the shape it needs.
--
-- locale and sense_hash travel with the report, so they go on both tables a
-- report passes through, for the reason sense_version did in 00009: a column
-- missing from the inbox is the value dropped on the way to reports. locale is
-- the language the reader saw the app in, which is what says whether a bad
-- verdict was about the English sentence or the French one. sense_hash is the
-- first twelve hex characters of the sha256 of the sense text the reader
-- judged, so a verdict can be told apart as being about the text we serve today
-- or about one we have since corrected. Neither one identifies a reader: a
-- language is shared by everybody who reads in it, and the hash is of our text,
-- not theirs. '' is a device that did not say. A locale other than en or fr, or
-- an over-long hash, is blanked in applyReport rather than refused, because a
-- refusal is permanent and would lose the reader's words.
--
-- The triage columns go on reports alone. Nothing triages an inbox row, and a
-- sweep carries them across its rewrite with the rest of the row. They are the
-- operator's words about a report, never the reader's, and nothing in them
-- travels back to a device. issue_url is held to GitHub because it is rendered
-- as a link on the operator's page, and a link whose scheme a stranger's report
-- could influence is a link nobody should click.
ALTER TABLE reports      ADD COLUMN locale text NOT NULL DEFAULT '' CHECK (length(locale) <= 10);
ALTER TABLE report_inbox ADD COLUMN locale text NOT NULL DEFAULT '' CHECK (length(locale) <= 10);
ALTER TABLE reports      ADD COLUMN sense_hash text NOT NULL DEFAULT '' CHECK (length(sense_hash) <= 64);
ALTER TABLE report_inbox ADD COLUMN sense_hash text NOT NULL DEFAULT '' CHECK (length(sense_hash) <= 64);

ALTER TABLE reports ADD COLUMN category text
  CHECK (category IN ('sense', 'bug', 'ux', 'content', 'request', 'noise'));
ALTER TABLE reports ADD COLUMN status text NOT NULL DEFAULT 'new'
  CHECK (status IN ('new', 'issued', 'dismissed'));
ALTER TABLE reports ADD COLUMN issue_url text
  CHECK (issue_url ~ '^https://github\.com/');

-- +goose Down

ALTER TABLE reports DROP COLUMN issue_url, DROP COLUMN status, DROP COLUMN category,
                    DROP COLUMN sense_hash, DROP COLUMN locale;
ALTER TABLE report_inbox DROP COLUMN sense_hash, DROP COLUMN locale;
