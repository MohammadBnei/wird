-- +goose Up

-- The fetched half of the bundled/fetched split. No licensed tafsir, iʿrāb or
-- lexicon prose exists yet (data/SOURCES.md records the open question), so
-- every row seeded here carries is_placeholder and the payload says so. An
-- unseeded aya or root is a 404: an endpoint that answered with invented
-- commentary would teach something false about scripture to a reader who
-- cannot check it.
CREATE TABLE lexicon_entries (
  root_letters   text NOT NULL,
  source         text NOT NULL,
  body           text NOT NULL,
  is_placeholder boolean NOT NULL,
  PRIMARY KEY (root_letters, source)
);

CREATE TABLE tafsir_entries (
  ayah_id        int NOT NULL,
  author         text NOT NULL,
  death_note     text,
  body           text NOT NULL,
  is_placeholder boolean NOT NULL,
  PRIMARY KEY (ayah_id, author)
);

CREATE TABLE irab_entries (
  ayah_id        int NOT NULL,
  position       int NOT NULL,
  segment_ar     text NOT NULL,
  note           text NOT NULL,
  is_placeholder boolean NOT NULL,
  PRIMARY KEY (ayah_id, position)
);

-- The version the client matches its bundled corpus against before it syncs.
CREATE TABLE corpus_meta (
  id             int PRIMARY KEY CHECK (id = 1),
  corpus_version int NOT NULL,
  built_at       timestamptz NOT NULL DEFAULT now()
);
INSERT INTO corpus_meta (id, corpus_version) VALUES (1, 1);

-- The design's own mockup prose, under the one root it was written about, and
-- the design's own pending notices where it wrote none. Nothing here is
-- scholarship and nothing here is attributed to a scholar.
INSERT INTO lexicon_entries (root_letters, source, body, is_placeholder) VALUES
  ('صبر', 'Ibn Fāris · Maqāyīs al-Lugha',
   'Gives the root one governing sense — restraint and confinement — and derives the rest from it.', true),
  ('صبر', 'Lane · Arabic-English Lexicon',
   'Records the concrete senses beside the moral one: the aloe plant, stony ground, the edge of a vessel.', true);

INSERT INTO tafsir_entries (ayah_id, author, death_note, body, is_placeholder) VALUES
  (103003, 'Placeholder', NULL,
   'Tafsir is fetched per aya. Nothing is downloaded yet, so nothing is attributed here.', true);

INSERT INTO irab_entries (ayah_id, position, segment_ar, note, is_placeholder) VALUES
  (103003, 4, 'وَتَوَاصَوْا بِالصَّبْرِ',
   'The parsing of this phrase is fetched per aya, and no aya has been downloaded yet.', true);

-- +goose Down
DROP TABLE irab_entries, tafsir_entries, lexicon_entries, corpus_meta;
