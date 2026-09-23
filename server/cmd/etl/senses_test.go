package main

import (
	"database/sql"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/MohammadBnei/wird/server/internal/rootsense"
)

// The senses are the only prose in corpus.db that Wird wrote rather than
// received. Every test here names a way that prose could reach a reader as
// something it is not: a sense this corpus does not bear out, a sense that
// explains a branch of the root the reader will rarely meet, a doctrinal clause
// riding on an attested one, a claim about a verse, or authored prose arriving
// with nothing beside it to say whose reading it is.

const (
	rawDir     = "../../../data/raw"
	rawTimings = "Husary_Muallim_128kbps"
)

var (
	rawOnce sync.Once
	rawCorp *Corpus
	rawErr  error
)

// wholeCorpus loads the real ingest, because the bar the gate applies is
// calibrated against the whole corpus and a fixture of a few ayas cannot
// calibrate anything.
func wholeCorpus(t *testing.T) *Corpus {
	t.Helper()
	rawOnce.Do(func() {
		if _, err := os.Stat(filepath.Join(rawDir, "chapters.json")); err != nil {
			return
		}
		rawCorp, rawErr = Load(rawDir, testRecitation.Slug, rawTimings)
	})
	if rawCorp == nil {
		t.Skip("data/raw is not present")
	}
	if rawErr != nil {
		t.Fatalf("load %s: %v", rawDir, err(rawErr))
	}
	return rawCorp
}

func err(e error) error { return e }

// sense returns a Senses carrying one sense for one root, with the provenance
// and byline a shipped file has, so a test can take exactly one of them away.
func sense(root, en, fr string) *Senses {
	s := &Senses{
		Attribution: "Wird's own wording.",
		Source:      "Wird",
		Basis:       "Wird's own reading of this root.",
		Senses: []Sense{{
			Root: root, SenseEn: en, SenseFr: fr,
			Support: []rootsense.Support{{Word: "كَلِمَة", Gloss: "a word", Slot: "noun"}},
		}},
	}
	return s
}

func rejection(t *testing.T, c *Corpus, s *Senses, full bool) string {
	t.Helper()
	was := c.Senses
	c.Senses = s
	defer func() { c.Senses = was }()
	e := c.Check(full)
	if e == nil {
		return ""
	}
	return e.Error()
}

// The failure that shipped: غير means "to change" in two of its words and
// "other than" in most of the rest, including the one in Al-Fatiha. A check
// with no coverage term passed it, and the sense printed under the word a
// reader meets said nothing about that word.
func TestASenseNamingAMinorityBranchOfItsRootStopsTheBuild(t *testing.T) {
	c := wholeCorpus(t)
	got := rejection(t, c, sense("غير", "to change; to alter", "changer ; altérer"), true)
	if !strings.Contains(got, "does not bear it out") || !strings.Contains(got, "غير") {
		t.Errorf("the minority-branch sense was not rejected: %q", got)
	}
}

// The other failure that shipped: a true core with a clause the corpus attests
// for nobody, or for one other root. The score and the coverage are both high,
// because the core really is attested, and only the dispersion term looks at
// the clause riding on it.
func TestADoctrinalClauseRidingOnAnAttestedSenseStopsTheBuild(t *testing.T) {
	c := wholeCorpus(t)
	got := rejection(t, c,
		sense("علم", "to know; to have knowledge; to know the unseen future", "savoir"), true)
	if !strings.Contains(got, "does not bear it out") {
		t.Errorf("the doctrinal rider was not rejected: %q", got)
	}
}

// A sense the corpus does bear out still ships nothing without the words it was
// checked against: provenance is what separates a tested claim from a stated
// one, and a row with no provenance cannot be re-checked by anyone.
func TestASenseWithNoProvenanceStopsTheBuild(t *testing.T) {
	c := load(t, fixtureDir)
	s := sense(c.Roots[0].Letters, "to say; to speak", "dire ; parler")
	s.Senses[0].Support = nil
	if got := rejection(t, c, s, false); !strings.Contains(got, "no provenance") {
		t.Errorf("a sense with no provenance was accepted: %q", got)
	}
}

// A verse reference inside a root's sense is the tafsir boundary crossed in
// machine-readable form: the claim has stopped being about the word.
func TestASenseCitingAVerseStopsTheBuild(t *testing.T) {
	c := load(t, fixtureDir)
	root := c.Roots[0].Letters
	for _, text := range []string{"to say; as in 2:255", "to say; 12 : 3"} {
		if got := rejection(t, c, sense(root, text, "dire"), false); !strings.Contains(got, "never about a verse") {
			t.Errorf("sense %q cited a verse and was accepted: %q", text, got)
		}
	}
	if got := rejection(t, c, sense(root, "to say", "dire ; comme en 2:255"), false); !strings.Contains(got, "never about a verse") {
		t.Errorf("a verse cited in the French was accepted: %q", got)
	}
}

// French is a translation of the English that passed, so a sense that ships in
// one language and not the other would leave a French reader either an empty
// section or an English one.
func TestAVerifiedSenseWithNoFrenchStopsTheBuild(t *testing.T) {
	c := wholeCorpus(t)
	got := rejection(t, c, sense("قول", "to say; to speak; a word, a saying", ""), true)
	if !strings.Contains(got, "no French") {
		t.Errorf("a verified sense with no French was accepted: %q", got)
	}
}

// Authored prose with no byline is the defect this project deleted once, when
// invented text shipped under Ibn Fāris's and Lane's names. A screen can only
// tell the reader whose reading this is if the byline reaches the database.
func TestASenseFileWithNoBylineStopsTheBuild(t *testing.T) {
	c := load(t, fixtureDir)
	for _, missing := range []string{"attribution", "source", "basis"} {
		s := sense(c.Roots[0].Letters, "to say", "dire")
		switch missing {
		case "attribution":
			s.Attribution = ""
		case "source":
			s.Source = ""
		case "basis":
			s.Basis = ""
		}
		if got := rejection(t, c, s, false); !strings.Contains(got, "no "+missing) {
			t.Errorf("a sense file with no %s was accepted: %q", missing, got)
		}
	}
}

// The byline and the evidence have to reach the database, not just the file: a
// screen reads root_notes, and prose arriving there bare is prose a reader can
// mistake for a lexicon entry.
func TestAShippedSenseReachesTheDatabaseWithItsBylineAndTheWordsItWasCheckedAgainst(t *testing.T) {
	c := load(t, fixtureDir)
	root := c.Roots[0].Letters
	c.Senses = sense(root, "to say; to speak", "dire ; parler")
	out := filepath.Join(t.TempDir(), "corpus.db")
	if e := Write(out, c, testRecitation, 1, time.Now()); e != nil {
		t.Fatalf("write: %v", e)
	}
	db, e := sql.Open("sqlite", out)
	if e != nil {
		t.Fatal(e)
	}
	defer db.Close()
	var note, fr, source, basis, evidence string
	if e := db.QueryRow(`SELECT note, note_fr, source, basis, evidence FROM root_notes
		WHERE root_letters = ? AND word_id IS NULL`, root).
		Scan(&note, &fr, &source, &basis, &evidence); e != nil {
		t.Fatalf("read back the sense: %v", e)
	}
	for _, want := range []struct{ name, got string }{
		{"the sense", note}, {"the French", fr}, {"the source", source},
		{"the basis", basis}, {"the evidence", evidence},
	} {
		if strings.TrimSpace(want.got) == "" {
			t.Errorf("%s did not reach root_notes", want.name)
		}
	}
	if !strings.Contains(evidence, "كَلِمَة") {
		t.Errorf("evidence %q does not name the word the sense was checked against", evidence)
	}
}
