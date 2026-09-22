-- +goose Up
-- The morphology of the Qur'anic corpus: one row for every written form the
-- corpus attests, under the root it attests it to. This is not surface_forms and
-- must not be folded into it: a surface form is a lexicon entry carrying a lemma
-- and a form label, while a row here is the bare fact that the corpus wrote this
-- spelling under this root, and that fact is the only thing the pattern rung is
-- allowed to assert from.
--
-- The form is stored normalised and only normalised. Rung five is reached with a
-- word the ladder has already normalised, and an exact-spelling match is what
-- rung one is for.
CREATE TABLE jidhr.form_roots (
    normalized   text NOT NULL,
    root_letters text NOT NULL REFERENCES jidhr.roots (letters) ON DELETE CASCADE,
    -- Leading column of the primary key, so Attests is one index scan for the
    -- whole form rather than one lookup per reading the templates proposed.
    PRIMARY KEY (normalized, root_letters)
);

-- +goose Down
DROP TABLE jidhr.form_roots;
