package main

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"time"

	_ "modernc.org/sqlite"
)

// Postgres types are mapped explicitly, not "mirrored": jsonb and text[] become TEXT
// holding JSON, uuid becomes TEXT, timestamptz becomes ISO-8601 TEXT.
const schema = `
CREATE TABLE surahs (
  id               INTEGER PRIMARY KEY,
  name_ar          TEXT NOT NULL,
  name_en          TEXT NOT NULL,
  ayah_count       INTEGER NOT NULL,
  revelation_order INTEGER NOT NULL,
  revelation_place TEXT NOT NULL
);
CREATE TABLE ayahs (
  id           INTEGER PRIMARY KEY,
  surah_id     INTEGER NOT NULL REFERENCES surahs(id),
  number       INTEGER NOT NULL,
  text_uthmani TEXT NOT NULL
);
-- One whole-ayah translation per row, in its own table rather than a column on
-- ayahs. There is no French word-by-word gloss to be had, so this is the only
-- shape French reaches a reader in; and the licence position on it is the one
-- data/SOURCES.md rates "could not determine", so taking the French back out
-- should be a DROP TABLE and not a schema migration. resource_id is quran.com's
-- own number for the translation, kept so a row says which rendering it is
-- rather than only which language.
CREATE TABLE ayah_translations (
  ayah_id     INTEGER NOT NULL REFERENCES ayahs(id),
  resource_id INTEGER NOT NULL,
  lang        TEXT NOT NULL,
  text        TEXT NOT NULL,
  PRIMARY KEY (ayah_id, resource_id)
);
CREATE TABLE words (
  id           INTEGER PRIMARY KEY,
  ayah_id      INTEGER NOT NULL REFERENCES ayahs(id),
  position     INTEGER NOT NULL,
  text_ar      TEXT NOT NULL,
  translit     TEXT,
  gloss_en     TEXT,
  root_letters TEXT,
  form         TEXT,
  morphology   TEXT
);
CREATE TABLE roots (
  letters           TEXT PRIMARY KEY,
  display           TEXT NOT NULL,
  translit          TEXT NOT NULL,
  quran_occurrences INTEGER NOT NULL,
  sources           TEXT NOT NULL
);
-- note is authored prose. source and basis say whose, and evidence names the
-- root's own words the note was checked against, so a screen can show the
-- reader that this is Wird's reading and not a lexicon it is quoting. A note
-- with no source is the defect this project deleted once already.
CREATE TABLE root_notes (
  root_letters TEXT NOT NULL,
  word_id      INTEGER,
  note         TEXT NOT NULL,
  note_fr      TEXT,
  source       TEXT,
  basis        TEXT,
  evidence     TEXT
);
CREATE TABLE recitations (
  slug         TEXT PRIMARY KEY,
  reciter_name TEXT NOT NULL,
  style        TEXT
);
-- No duration: the recordings are fetched from a third-party origin at playback
-- time and Wird neither hosts nor indexes them, so their length is not ours to
-- state. rel_path is relative for the same reason — see data/SOURCES.md.
CREATE TABLE ayah_audio (
  ayah_id         INTEGER NOT NULL REFERENCES ayahs(id),
  recitation_slug TEXT NOT NULL REFERENCES recitations(slug),
  rel_path        TEXT NOT NULL,
  PRIMARY KEY (ayah_id, recitation_slug)
);
CREATE TABLE word_segments (
  word_id         INTEGER NOT NULL REFERENCES words(id),
  recitation_slug TEXT NOT NULL REFERENCES recitations(slug),
  start_ms        INTEGER NOT NULL,
  end_ms          INTEGER NOT NULL
);
-- The parsing vocabulary: one row per code the morphology file writes, named in
-- both languages. A code per segment and a lookup, rather than two prose strings
-- on each of 128,219 segments — which is the same words written 128,219 times,
-- around 10 MB of them, and a both-languages rule nothing could check.
CREATE TABLE irab_roles (
  code    TEXT PRIMARY KEY,
  role_en TEXT NOT NULL,
  role_fr TEXT NOT NULL
);
-- One row per segment of one word, in the order the word is written. Case and
-- mood are assigned by the syntax of the verse, so this is per occurrence and
-- never per spelling: a screen showing it has to say which occurrence it means.
CREATE TABLE irab (
  word_id  INTEGER NOT NULL REFERENCES words(id),
  position INTEGER NOT NULL,
  code     TEXT NOT NULL REFERENCES irab_roles(code),
  -- The segment's remaining codes, space-joined, each one a row of irab_roles.
  features TEXT NOT NULL,
  PRIMARY KEY (word_id, position)
);
CREATE TABLE corpus_meta (
  corpus_version INTEGER NOT NULL,
  built_at       TEXT NOT NULL,
  notice         TEXT NOT NULL
);
CREATE INDEX words_ayah ON words(ayah_id);
CREATE INDEX words_root ON words(root_letters);
CREATE INDEX ayahs_surah ON ayahs(surah_id);
CREATE INDEX segments_word ON word_segments(word_id, recitation_slug);
CREATE INDEX root_notes_root ON root_notes(root_letters);
`

type Recitation struct {
	Slug, ReciterName, Style string
}

func Write(path string, c *Corpus, rec Recitation, version int, builtAt time.Time) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	if err := os.Remove(path); err != nil && !os.IsNotExist(err) {
		return err
	}
	db, err := sql.Open("sqlite", path)
	if err != nil {
		return err
	}
	defer db.Close()

	for _, p := range []string{"PRAGMA journal_mode=OFF", "PRAGMA synchronous=OFF"} {
		if _, err := db.Exec(p); err != nil {
			return err
		}
	}
	if _, err := db.Exec(schema); err != nil {
		return err
	}

	tx, err := db.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()

	insert := func(query string, rows int, bind func(i int) []any) error {
		st, err := tx.Prepare(query)
		if err != nil {
			return fmt.Errorf("%s: %w", query, err)
		}
		defer st.Close()
		for i := 0; i < rows; i++ {
			if _, err := st.Exec(bind(i)...); err != nil {
				return fmt.Errorf("%s: %w", query, err)
			}
		}
		return nil
	}

	// The morphology file's own name. The corpus is named in full, with its
	// copyright block, in corpus_meta.notice.
	sources, err := json.Marshal([]string{"quranic-corpus-morphology"})
	if err != nil {
		return err
	}

	if _, err := tx.Exec(`INSERT INTO recitations VALUES (?,?,?)`, rec.Slug, rec.ReciterName, rec.Style); err != nil {
		return err
	}
	if _, err := tx.Exec(`INSERT INTO corpus_meta VALUES (?,?,?)`,
		version, builtAt.UTC().Format(time.RFC3339), c.Notice); err != nil {
		return err
	}
	if err := insert(`INSERT INTO surahs VALUES (?,?,?,?,?,?)`, len(c.Surahs), func(i int) []any {
		s := c.Surahs[i]
		return []any{s.ID, s.NameAr, s.NameEn, s.AyahCount, s.RevelationOrder, s.RevelationPlace}
	}); err != nil {
		return err
	}
	if err := insert(`INSERT INTO ayahs VALUES (?,?,?,?)`, len(c.Ayahs), func(i int) []any {
		a := c.Ayahs[i]
		return []any{a.ID, a.SurahID, a.Number, a.TextUthmani}
	}); err != nil {
		return err
	}
	fr := make([]Ayah, 0, len(c.Ayahs))
	for _, a := range c.Ayahs {
		if a.TextFr != "" {
			fr = append(fr, a)
		}
	}
	if err := insert(`INSERT INTO ayah_translations VALUES (?,?,?,?)`, len(fr), func(i int) []any {
		a := fr[i]
		return []any{a.ID, frenchTranslation, "fr", a.TextFr}
	}); err != nil {
		return err
	}

	if err := insert(`INSERT INTO words VALUES (?,?,?,?,?,?,?,?,?)`, len(c.Words), func(i int) []any {
		w := c.Words[i]
		return []any{w.ID, w.AyahID, w.Position, w.TextAr, w.Translit, w.GlossEn,
			nullable(w.RootLetters), nullable(w.Form), nullable(w.Morphology)}
	}); err != nil {
		return err
	}
	if err := insert(`INSERT INTO roots VALUES (?,?,?,?,?)`, len(c.Roots), func(i int) []any {
		r := c.Roots[i]
		return []any{r.Letters, r.Display, r.Translit, r.Occurrences, string(sources)}
	}); err != nil {
		return err
	}
	// root_notes is created and left EMPTY. The table stays because the app
	// still reads it — it is where a fetched pack of senses lands — but nothing
	// here fills it any more.
	//
	// A sense is Wird's own sentence and it is corrected by the reader's thumb,
	// so freezing it into this asset put every correction behind a store
	// release. The server owns the senses now and the app fetches them
	// (docs/adr/0010). What ships in this file is what came from an upstream
	// source and does not move: the Qur'an, Dukes's morphology, the timings and
	// a licensed translation.
	//
	// So a fresh install has a whole Qur'an and no senses, which is a state the
	// app was built for: CoreSense draws a notice for a root without one, and
	// since ADR 0010 it draws a different notice for a device that has not
	// fetched yet.
	roles := IrabRoles()
	if err := insert(`INSERT INTO irab_roles VALUES (?,?,?)`, len(roles), func(i int) []any {
		r := roles[i]
		return []any{r.Code, r.En, r.Fr}
	}); err != nil {
		return err
	}
	if err := insert(`INSERT INTO irab VALUES (?,?,?,?)`, len(c.Irab), func(i int) []any {
		s := c.Irab[i]
		return []any{s.WordID, s.Position, s.Code, s.Features}
	}); err != nil {
		return err
	}
	if err := insert(`INSERT INTO ayah_audio VALUES (?,?,?)`, len(c.Audio), func(i int) []any {
		a := c.Audio[i]
		return []any{a.AyahID, rec.Slug, a.RelPath}
	}); err != nil {
		return err
	}
	if err := insert(`INSERT INTO word_segments VALUES (?,?,?,?)`, len(c.Segments), func(i int) []any {
		s := c.Segments[i]
		return []any{s.WordID, rec.Slug, s.StartMS, s.EndMS}
	}); err != nil {
		return err
	}
	if err := tx.Commit(); err != nil {
		return err
	}
	_, err = db.Exec("VACUUM")
	return err
}

func nullable(s string) any {
	if s == "" {
		return nil
	}
	return s
}
