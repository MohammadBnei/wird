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
CREATE TABLE root_notes (
  root_letters TEXT NOT NULL,
  word_id      INTEGER,
  note         TEXT NOT NULL
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
