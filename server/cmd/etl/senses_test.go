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
		rawCorp, rawErr = Load(rawDir, []Recitation{testRecitation})
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

// The bundle must ship NO senses. A sense is Wird's own sentence, corrected by
// the reader's thumb, so freezing it into this asset put every correction behind
// a store release; the server owns them now and the app fetches them
// (docs/adr/0010). The table stays because a fetched pack lands in it.
//
// This test replaced one asserting the opposite — that a sense reached
// root_notes with its byline and the words it was checked against. That was the
// right assertion under the old standard and is the wrong one now, so it is
// rewritten rather than deleted: the file should say which way the rule runs.
func TestTheBundleShipsNoSenseForAReaderToMistakeForOne(t *testing.T) {
	c := load(t, fixtureDir)
	out := filepath.Join(t.TempDir(), "corpus.db")
	if e := Write(out, c, 1, time.Now()); e != nil {
		t.Fatalf("write: %v", e)
	}
	db, e := sql.Open("sqlite", out)
	if e != nil {
		t.Fatal(e)
	}
	defer db.Close()

	var rows int
	if e := db.QueryRow(`SELECT COUNT(*) FROM root_notes`).Scan(&rows); e != nil {
		t.Fatalf("root_notes is gone, and a fetched pack has nowhere to land: %v", e)
	}
	if rows != 0 {
		t.Errorf("the bundle carries %d senses; every one of them is prose a correction "+
			"cannot reach, because it ships inside the binary", rows)
	}
}
