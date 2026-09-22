-- +goose Up
CREATE SCHEMA IF NOT EXISTS jidhr;

CREATE TABLE jidhr.roots (
    letters           text PRIMARY KEY,
    display           text NOT NULL,
    translit          text NOT NULL DEFAULT '',
    -- Null, not zero: a root that never occurs in the Qur'an has no Qur'anic
    -- statistic, and a caller outside Wird must not be handed a count of nothing.
    quran_occurrences integer,
    sources           text[] NOT NULL DEFAULT '{}'
);

-- A form is stored twice over: as written, and normalised. Rung one matches the
-- written spelling exactly and rung two matches the normalised one, so collapsing
-- these into a single column would make every result claim to be an attested
-- lexicon hit.
CREATE TABLE jidhr.surface_forms (
    surface      text NOT NULL,
    normalized   text NOT NULL,
    lemma        text NOT NULL DEFAULT '',
    form         text NOT NULL DEFAULT '',
    root_letters text NOT NULL REFERENCES jidhr.roots (letters) ON DELETE CASCADE,
    PRIMARY KEY (surface, root_letters)
);

CREATE INDEX surface_forms_normalized_idx ON jidhr.surface_forms (normalized);
CREATE INDEX surface_forms_root_idx ON jidhr.surface_forms (root_letters);

CREATE TABLE jidhr.lemmas (
    lemma        text NOT NULL,
    normalized   text NOT NULL,
    root_letters text NOT NULL REFERENCES jidhr.roots (letters) ON DELETE CASCADE,
    PRIMARY KEY (lemma, root_letters)
);

CREATE INDEX lemmas_normalized_idx ON jidhr.lemmas (normalized);

-- One row per root per language per register. The register is a key rather than a
-- second text column, so adding a language or a third register is data rather than
-- a migration.
CREATE TABLE jidhr.meanings (
    root_letters text NOT NULL REFERENCES jidhr.roots (letters) ON DELETE CASCADE,
    language     text NOT NULL,
    register     text NOT NULL CHECK (register IN ('plain', 'poetic')),
    body         text NOT NULL CHECK (body <> ''),
    updated_at   timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (root_letters, language, register)
);

-- +goose Down
DROP TABLE jidhr.meanings;
DROP TABLE jidhr.lemmas;
DROP TABLE jidhr.surface_forms;
DROP TABLE jidhr.roots;
DROP SCHEMA jidhr;
