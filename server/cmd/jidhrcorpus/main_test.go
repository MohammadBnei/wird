package main

import (
	"database/sql"
	"encoding/json"
	"path/filepath"
	"testing"

	_ "modernc.org/sqlite"
)

// corpusDB is the shape jidhrcorpus reads out of app/assets/corpus.db, filled with
// the cases the real corpus has 1,642 of: a root whose sense was written, a root
// whose sense the check refused, and a form attested under two roots.
func corpusDB(t *testing.T, statements ...string) *sql.DB {
	t.Helper()
	db, err := sql.Open("sqlite", filepath.Join(t.TempDir(), "corpus.db"))
	if err != nil {
		t.Fatalf("open: %v", err)
	}
	t.Cleanup(func() { db.Close() })

	schema := []string{
		`CREATE TABLE roots (letters TEXT PRIMARY KEY, display TEXT NOT NULL, translit TEXT NOT NULL, quran_occurrences INTEGER NOT NULL, sources TEXT NOT NULL DEFAULT '')`,
		`CREATE TABLE words (id INTEGER PRIMARY KEY, text_ar TEXT NOT NULL, root_letters TEXT)`,
		`CREATE TABLE root_notes (root_letters TEXT NOT NULL, word_id INTEGER, note TEXT NOT NULL, note_fr TEXT, source TEXT, basis TEXT, evidence TEXT)`,
	}
	for _, s := range append(schema, statements...) {
		if _, err := db.Exec(s); err != nil {
			t.Fatalf("%s: %v", s, err)
		}
	}
	return db
}

const (
	written = `INSERT INTO roots VALUES ('وصي','و ص ي','w-ṣ-y',32,''), ('صبر','ص ب ر','ṣ-b-r',103,'')`
	senses  = `INSERT INTO root_notes VALUES ('وصي',NULL,'to enjoin, to charge','enjoindre, charger','Wird','read from the root''s own words','وَتَوَاصَوْا')`
)

func built(t *testing.T, db *sql.DB) map[string]any {
	t.Helper()
	c, err := build(db)
	if err != nil {
		t.Fatalf("build: %v", err)
	}
	body, err := json.Marshal(corpusFile{Note: note, Corpus: c})
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	var out map[string]any
	if err := json.Unmarshal(body, &out); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	return out
}

func meanings(t *testing.T, corpus map[string]any, letters string) map[string]any {
	t.Helper()
	by, _ := corpus["meanings"].(map[string]any)
	m, _ := by[letters].(map[string]any)
	return m
}

func TestARootNobodyWroteASenseForIsCarriedWithNoMeaningAtAll(t *testing.T) {
	corpus := built(t, corpusDB(t, written, senses))

	if _, present := meanings(t, corpus, "صبر")["en"]; present {
		t.Error("a root whose sense the check refused is shipped with a meaning anyway, so a reader is taught prose nothing bore out")
	}
	roots, _ := corpus["roots"].([]any)
	if len(roots) != 2 {
		t.Fatalf("the corpus carries %d roots, want both: a root with nothing written is still a root", len(roots))
	}
}

func TestASenseWrittenInFrenchReachesTheCorpusAsFrench(t *testing.T) {
	got := meanings(t, built(t, corpusDB(t, written, senses)), "وصي")

	fr, ok := got["fr"].(map[string]any)
	if !ok {
		t.Fatalf("the French sense never reached the corpus: %v — a caller asking for fr is answered with silence", got)
	}
	if fr["plain"] != "enjoindre, charger" {
		t.Errorf("fr.plain = %v, want the French sense and not the English one", fr["plain"])
	}
	if _, ar := got["ar"]; ar {
		t.Error("a meaning is shipped as Arabic, which nobody authored: the two languages written are en and fr")
	}
}

func TestNoMeaningIsBuiltWithAPoeticRegisterNobodyWrote(t *testing.T) {
	for lang, m := range meanings(t, built(t, corpusDB(t, written, senses)), "وصي") {
		if _, poetic := m.(map[string]any)["poetic"]; poetic {
			t.Errorf("%s carries a poetic register, so the screen renders a blank section instead of no section", lang)
		}
	}
}

func TestARootTheQuranNeverUsesCarriesNoOccurrenceCount(t *testing.T) {
	corpus := built(t, corpusDB(t, `INSERT INTO roots VALUES ('برمج','ب ر م ج','b-r-m-j',0,'')`))

	roots, _ := corpus["roots"].([]any)
	first, _ := roots[0].(map[string]any)
	if _, present := first["quran"]; present {
		t.Error("a root the Qur'an never uses ships an occurrence count, which reads as zero occurrences rather than as no measurement")
	}
}

func TestAMeaningForARootTheTableNeverRecordsStopsTheBuildRatherThanShipping(t *testing.T) {
	db := corpusDB(t, written, `INSERT INTO root_notes VALUES ('زبر',NULL,'to write down',NULL,'Wird','','')`)

	if _, err := build(db); err == nil {
		t.Error("a meaning was written for a root no caller can look up, and the build said nothing")
	}
}

func TestAFormAttestedUnderTwoRootsKeepsBothRatherThanTheFirst(t *testing.T) {
	db := corpusDB(t, `INSERT INTO roots VALUES ('أسر','أ س ر','ʾ-s-r',6,''), ('سري','س ر ي','s-r-y',4,'')`,
		`INSERT INTO words VALUES (1,'أَسْرَىٰ','أسر'), (2,'أَسْرَىٰ','سري')`)

	attested, _ := built(t, db)["attested"].(map[string]any)
	if got, _ := attested["أَسْرَىٰ"].([]any); len(got) != 2 {
		t.Errorf("the form is attested under %v, so a spelling the morphology leaves unsettled is settled by whichever root was read first", got)
	}
}

func TestAFormThatCarriesAPauseMarkShipsAsTheWordAndNotAsTheWordPlusTheMark(t *testing.T) {
	// corpus.db keeps the recitation marks glued to the word they follow, space
	// and all: 2,573 of the 19,805 form rows are written that way. Shipped
	// verbatim, they are keyed under a spelling with a space in it, and for 682 of
	// them no other row spells the same word cleanly — so no input a reader can
	// type reaches them at all.
	db := corpusDB(t, written,
		`INSERT INTO words VALUES (1,'صَبَرُوا ۚ','صبر'), (2,'وَتَوَاصَوْا ۩','وصي')`)

	attested, _ := built(t, db)["attested"].(map[string]any)
	for _, want := range []string{"صَبَرُوا", "وَتَوَاصَوْا"} {
		if _, ok := attested[want]; !ok {
			t.Errorf("the corpus ships %v, and a reader typing %s reaches none of it", keysOf(attested), want)
		}
	}
}

func TestTwoSpellingsThatDifferOnlyByAPauseMarkShipAsOneForm(t *testing.T) {
	db := corpusDB(t, written,
		`INSERT INTO words VALUES (1,'صَبَرُوا','صبر'), (2,'صَبَرُوا ۖ','صبر'), (3,'صَبَرُوا ۚ','صبر')`)

	attested, _ := built(t, db)["attested"].(map[string]any)
	roots, _ := attested["صَبَرُوا"].([]any)
	if len(attested) != 1 || len(roots) != 1 {
		t.Errorf("attested = %v, want the one form under the one root: cleaning merges the spellings, and a form listed under the same root three times is a corpus that counts punctuation as evidence", attested)
	}
}

func keysOf(m map[string]any) []string {
	out := make([]string, 0, len(m))
	for k := range m {
		out = append(out, k)
	}
	return out
}
