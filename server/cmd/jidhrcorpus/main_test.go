package main

import (
	"database/sql"
	"encoding/json"
	"path/filepath"
	"testing"

	_ "modernc.org/sqlite"

	"github.com/MohammadBnei/wird/server/internal/store"
)

// corpusDB is the shape jidhrcorpus reads out of app/assets/corpus.db: the roots,
// the attested spellings and the forms recorded under no root, and nothing else.
//
// root_notes is gone from it, and that is the change rather than an omission. The
// meanings no longer come from corpus.db — they come from the server's Postgres,
// which is why build takes them as an argument. So the fixture for a sense is a Go
// slice, and these tests need no database at all: the SQL read they used to exercise
// is store.Senses now, and server/internal/store/senses_test.go tests it against a
// real Postgres. Wiring testenv into server/cmd/ to re-test it here would buy a
// second copy of that coverage and a docker dependency for eight table-shape tests.
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
	}
	for _, s := range append(schema, statements...) {
		if _, err := db.Exec(s); err != nil {
			t.Fatalf("%s: %v", s, err)
		}
	}
	return db
}

// written is two roots the morphology records; senses is what the server holds for
// one of them. The pair is the case the real data has 1,642 of on one side and
// however many the log carries on the other: the two halves come from two databases
// and nothing makes them cover each other.
const written = `INSERT INTO roots VALUES ('وصي','و ص ي','w-ṣ-y',32,''), ('صبر','ص ب ر','ṣ-b-r',103,'')`

var senses = []store.Sense{{Root: "وصي", En: "to enjoin, to charge", Fr: "enjoindre, charger"}}

func built(t *testing.T, db *sql.DB, senses ...store.Sense) map[string]any {
	t.Helper()
	c, err := build(db, senses)
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
	corpus := built(t, corpusDB(t, written), senses...)

	if _, present := meanings(t, corpus, "صبر")["en"]; present {
		t.Error("a root the server holds no sense for is shipped with a meaning anyway, so a reader is taught prose nobody wrote")
	}
	roots, _ := corpus["roots"].([]any)
	if len(roots) != 2 {
		t.Fatalf("the corpus carries %d roots, want both: a root with nothing written is still a root", len(roots))
	}
}

func TestASenseWrittenInFrenchReachesTheCorpusAsFrench(t *testing.T) {
	got := meanings(t, built(t, corpusDB(t, written), senses...), "وصي")

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

// The poetic register is stored in Postgres and store.Sense carries both columns,
// so "it is not exported" has to be measured rather than remembered: this is the
// export side of the gate jidhr/pkg/root/meaning_test.go holds on the read side.
func TestNoMeaningIsBuiltWithAPoeticRegisterNobodyWrote(t *testing.T) {
	poetic := []store.Sense{{Root: "وصي", En: "to enjoin, to charge", Fr: "enjoindre, charger",
		PoeticEn: "the charge laid on a departing tongue", PoeticFr: "la charge laissée par une langue qui s'en va"}}

	for lang, m := range meanings(t, built(t, corpusDB(t, written), poetic...), "وصي") {
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

// Two databases with nothing joining them: the morphology is in corpus.db and the
// senses are in Postgres, so a root that leaves one and not the other is now a real
// state rather than a foreign-key violation. This is the only thing that catches it.
func TestAMeaningForARootTheTableNeverRecordsStopsTheBuildRatherThanShipping(t *testing.T) {
	db := corpusDB(t, written)

	if _, err := build(db, []store.Sense{{Root: "زبر", En: "to write down", Fr: "écrire"}}); err == nil {
		t.Error("the server holds a sense for a root no caller can look up, and the build said nothing")
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
	// and all: 2,573 of the 19,805 rooted form rows are written with a space in
	// them. Shipped verbatim they are keyed under a spelling that carries the
	// space, and no input a reader can type reaches them.
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

func TestAParticleTheMorphologyGivesNoRootIsShippedRatherThanLeftOutOfTheCorpus(t *testing.T) {
	// 1,492 of the form rows carry no root: the particles and the pronouns, which
	// come from no triliteral root and which the morphology records that way on
	// purpose. Leaving them out is what made the engine answer مِنْ with منن — the
	// root of مَنَّ, which is the same letters once the diacritics are gone — instead
	// of with the fact the corpus already held.
	db := corpusDB(t, `INSERT INTO roots VALUES ('منن','م ن ن','m-n-n',27,'')`,
		`INSERT INTO words VALUES (1,'مَنَّ','منن'), (2,'مِنْ',NULL), (3,'مِنْ ۚ',''), (4,'هُوَ',NULL)`)

	corpus := built(t, db)
	got, _ := corpus["rootless"].([]any)
	if len(got) != 2 {
		t.Fatalf("the corpus ships %v as rootless, want مِنْ and هُوَ once each: a spelling the morphology denies a root is a fact the engine has no other way to learn", got)
	}
	if attested, _ := corpus["attested"].(map[string]any); len(attested) != 1 {
		t.Errorf("attested = %v, want only the form that has a root: a rootless spelling listed as attested is the guess this fixes", attested)
	}
}

func keysOf(m map[string]any) []string {
	out := make([]string, 0, len(m))
	for k := range m {
		out = append(out, k)
	}
	return out
}
