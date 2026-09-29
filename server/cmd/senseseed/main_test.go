package main

import (
	"database/sql"
	"os"
	"path/filepath"
	"strings"
	"testing"

	_ "modernc.org/sqlite"
)

const header = "root\tsense_en\tsense_fr\tpoetic_en\tpoetic_fr\tlane\tprompt\tmodel\n"

func logFile(t *testing.T, rows ...string) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "root_senses_draft.tsv")
	if err := os.WriteFile(path, []byte(header+strings.Join(rows, "\n")+"\n"), 0o600); err != nil {
		t.Fatalf("write the fixture: %v", err)
	}
	return path
}

func row(fields ...string) string { return strings.Join(fields, "\t") }

func corpusOf(t *testing.T, roots ...string) map[string]bool {
	t.Helper()
	known := map[string]bool{}
	for _, r := range roots {
		known[r] = true
	}
	return known
}

// The failure: the header row is seeded as a root spelled "root", or — because
// the root check refuses a root the corpus does not record — the literal word
// "root" refuses the whole run and no sense is ever published. rootcheck's own
// reader does not skip it, so this is the one difference between the two.
func TestTheHeaderRowRefusesTheWholeRunAsARootCalledRoot(t *testing.T) {
	path := logFile(t, row("رحم", "to show mercy", "faire miséricorde", "", ""))

	senses, err := load(path, corpusOf(t, "رحم"))
	if err != nil {
		t.Fatalf("the log was refused: %v", err)
	}
	if len(senses) != 1 || senses[0].Root != "رحم" {
		t.Fatalf("read %#v", senses)
	}
}

// The failure: a misspelled root is seeded, and the sense sits in Postgres under
// letters no reader's root screen will ever ask for. It is silent — the row is
// valid, the route serves it, and nothing joins it to anything.
func TestARootTheCorpusDoesNotRecordIsSeededAndNeverRead(t *testing.T) {
	path := logFile(t,
		row("رحم", "to show mercy", "faire miséricorde", "", ""),
		row("رحمم", "a typo", "une faute", "", ""))

	_, err := load(path, corpusOf(t, "رحم"))
	if err == nil {
		t.Fatal("a root the corpus does not record was accepted")
	}
	if !strings.Contains(err.Error(), "رحمم") {
		t.Errorf("the refusal does not name the root, so nobody can fix it: %v", err)
	}
}

// The failure: the seeder dies on the 554th root. 553 roots carry more than one
// row in the log and its rule is that the last row wins. That rule belongs to
// the primary key and the order these are handed over in — so load does no
// selecting, and both rows come back, in file order. A load that quietly kept
// the first would publish the draft the log superseded.
func TestTheFirstDraftOfARootIsTheOneThatSurvives(t *testing.T) {
	path := logFile(t,
		row("رحم", "first draft", "premier jet", "", ""),
		row("صبر", "to endure", "endurer", "", ""),
		row("رحم", "to show mercy; the womb", "faire miséricorde ; la matrice", "", ""))

	senses, err := load(path, corpusOf(t, "رحم", "صبر"))
	if err != nil {
		t.Fatalf("the log was refused: %v", err)
	}
	if len(senses) != 3 {
		t.Fatalf("%d rows read, and selecting between them is the primary key's job", len(senses))
	}
	if senses[0].En != "first draft" || senses[2].En != "to show mercy; the womb" {
		t.Errorf("the rows are not in file order, so the last row for a root is not the one that wins: %#v", senses)
	}
}

// The failure: a sense that has stopped being about the word. A verse reference
// inside it is the tafsir boundary crossed in machine-readable form, and
// server/cmd/etl/check.go refuses one on the bundled path — so the served path
// refuses it too, or the guard is one the ETL used to have.
func TestASenseCitingAVerseIsPublishedAsAReadingOfTheWord(t *testing.T) {
	path := logFile(t, row("رحم", "the mercy of 2:163", "la miséricorde de 2:163", "", ""))

	err := errOf(load(path, corpusOf(t, "رحم")))
	if err == nil || !strings.Contains(err.Error(), "2:163") {
		t.Fatalf("a sense citing a verse was accepted: %v", err)
	}
}

// The failure: the clauses arrive reordered. 40 rows in the log have a different
// number of English and French clauses, and rootcheck's Order refuses exactly
// that pair — but its refusal protects a permutation, and this seeder permutes
// nothing. Clause order is one of the six terms of a bar these drafts never
// passed. Reordering them here would dress an unsigned draft in one term of a
// standard it has not met, so the prose must arrive byte for byte.
func TestTheClausesAreTidiedOnTheWayIn(t *testing.T) {
	const en = "to bind; to endure; to be patient"
	const fr = "se lier ; endurer" // one clause fewer, deliberately
	path := logFile(t, row("صبر", en, fr, "poetic", ""))

	senses, err := load(path, corpusOf(t, "صبر"))
	if err != nil {
		t.Fatalf("a row whose languages disagree on clause count was refused: %v", err)
	}
	if senses[0].En != en || senses[0].Fr != fr {
		t.Errorf("the prose was rewritten: %q / %q", senses[0].En, senses[0].Fr)
	}
	if senses[0].PoeticEn != "poetic" || senses[0].PoeticFr != "" {
		t.Errorf("the poetic register did not survive the read: %#v", senses[0])
	}
}

// The failure: a seed from an empty or wrong file empties the table, the route
// answers 200 with no senses, and every phone applies it. After the bundle stops
// carrying senses there is no floor to fall back to.
func TestASeedOfNothingUnpublishesEverySenseThereIs(t *testing.T) {
	path := filepath.Join(t.TempDir(), "empty.tsv")
	if err := os.WriteFile(path, []byte(header), 0o600); err != nil {
		t.Fatalf("write the fixture: %v", err)
	}

	if _, err := load(path, corpusOf(t, "رحم")); err == nil {
		t.Fatal("a file with no senses was accepted as a full replace")
	}
}

// The failure: the roots are read with a query the bundled corpus does not
// answer — a renamed table or column — and every root is refused as unknown, or
// none is checked at all. This reads the real asset for that reason.
func TestTheRootsAreReadWithAQueryTheCorpusDoesNotAnswer(t *testing.T) {
	known, err := knownRoots("../../../app/assets/corpus.db")
	if err != nil {
		t.Fatalf("read the bundled roots: %v", err)
	}
	if len(known) != 1642 {
		t.Errorf("%d roots, where the corpus records 1,642", len(known))
	}
	if !known["رحم"] {
		t.Error("the roots came back without رحم, so the letters are not spelled as the log spells them")
	}
}

// The failure: an empty roots table passes and every root is then refused as
// unknown, one error per row, with nothing saying why.
func TestAnEmptyRootsTableRefusesEverySenseOneByOne(t *testing.T) {
	path := filepath.Join(t.TempDir(), "corpus.db")
	db, err := sql.Open("sqlite", path)
	if err != nil {
		t.Fatalf("open the fixture: %v", err)
	}
	if _, err := db.Exec(`CREATE TABLE roots (letters TEXT PRIMARY KEY)`); err != nil {
		t.Fatalf("create the fixture: %v", err)
	}
	if err := db.Close(); err != nil {
		t.Fatalf("close the fixture: %v", err)
	}

	if _, err := knownRoots(path); err == nil {
		t.Fatal("an empty roots table was accepted")
	}
}

func errOf[T any](_ T, err error) error { return err }
