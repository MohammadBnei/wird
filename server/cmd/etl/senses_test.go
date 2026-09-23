package main

import (
	"database/sql"
	"errors"
	"os"
	"strings"
	"sync"
	"testing"

	_ "modernc.org/sqlite"

	"github.com/MohammadBnei/wird/server/internal/rootsense"
)

// The gate tests read the shipped corpus rather than the small fixture: a sense
// is checked against the glosses of the whole Qur'an, and a corpus holding three
// suras cannot answer whether one holds up.
const shippedCorpus = "../../../app/assets/corpus.db"

var (
	shippedOnce sync.Once
	shipped     *Corpus
	shippedErr  error
)

// fromShipped rebuilds just the parts of a Corpus the sense gate reads, out of
// the database a previous build wrote.
func fromShipped(t *testing.T) *Corpus {
	t.Helper()
	shippedOnce.Do(func() {
		if _, err := os.Stat(shippedCorpus); err != nil {
			shippedErr = err
			return
		}
		db, err := sql.Open("sqlite", "file:"+shippedCorpus+"?mode=ro")
		if err != nil {
			shippedErr = err
			return
		}
		defer db.Close()
		c := &Corpus{}
		rows, err := db.Query(`SELECT text_ar, COALESCE(gloss_en,''), COALESCE(root_letters,''),
			COALESCE(form,''), COALESCE(morphology,'') FROM words`)
		if err != nil {
			shippedErr = err
			return
		}
		for rows.Next() {
			var w Word
			if shippedErr = rows.Scan(&w.TextAr, &w.GlossEn, &w.RootLetters, &w.Form, &w.Morphology); shippedErr != nil {
				rows.Close()
				return
			}
			c.Words = append(c.Words, w)
		}
		rows.Close()
		if shippedErr = loadInto(db, `SELECT letters FROM roots`, func(sc func(...any) error) error {
			var r Root
			if err := sc(&r.Letters); err != nil {
				return err
			}
			c.Roots = append(c.Roots, r)
			return nil
		}); shippedErr != nil {
			return
		}
		if shippedErr = loadInto(db, `SELECT name_en FROM surahs`, func(sc func(...any) error) error {
			var s Surah
			if err := sc(&s.NameEn); err != nil {
				return err
			}
			c.Surahs = append(c.Surahs, s)
			return nil
		}); shippedErr != nil {
			return
		}
		shipped = c
	})
	if shippedErr != nil {
		t.Skipf("no shipped corpus to check senses against: %v", shippedErr)
	}
	copied := *shipped
	return &copied
}

func loadInto(db *sql.DB, query string, scan func(func(...any) error) error) error {
	rows, err := db.Query(query)
	if err != nil {
		return err
	}
	defer rows.Close()
	for rows.Next() {
		if err := scan(rows.Scan); err != nil {
			return err
		}
	}
	return rows.Err()
}

// good is a sense the corpus does bear out, so each test below changes exactly
// one thing and the failure it reports is the thing it changed.
func good() Sense {
	return Sense{
		Root: "صبر", SenseEn: "to hold fast; to be steadfast; to endure",
		SenseFr: "tenir ferme ; être constant ; endurer",
		Support: []rootsense.Support{{Word: "ٱلصَّـٰبِرِينَ", Gloss: "the steadfast", Slot: "act-pcpl"}},
	}
}

func withSense(t *testing.T, s Sense) error {
	t.Helper()
	c := fromShipped(t)
	c.Senses = &Senses{Attribution: "Wird's own wording.", Senses: []Sense{s}}
	return errors.Join(c.checkSenses()...)
}

func TestASenseTheCorpusBearsOutIsLetThrough(t *testing.T) {
	if err := withSense(t, good()); err != nil {
		t.Fatalf("a checked sense was rejected: %v", err)
	}
}

// Without provenance nothing records which of the root's own words the sense
// was ever checked against, and an unsourced claim is exactly what this project
// had to delete once already.
func TestASenseWithNoProvenanceStopsTheBuild(t *testing.T) {
	s := good()
	s.Support = nil
	mustReject(t, withSense(t, s), "no provenance")
}

// The senses were checked against one build of the corpus. If a later build
// changes the glosses out from under them, the sense has to stop shipping
// rather than ride along on a score measured against data that is gone.
func TestASenseThisCorpusNoLongerBearsOutStopsTheBuild(t *testing.T) {
	s := good()
	s.SenseEn = "to be sad; to grieve"
	mustReject(t, withSense(t, s), "does not bear it out")
}

// A verse reference inside a root's sense is the tafsir boundary crossed in
// machine-readable form: the sense has stopped being about the word.
func TestASenseCitingAVerseStopsTheBuild(t *testing.T) {
	s := good()
	s.SenseEn = "to hold fast; to be steadfast; to endure, as at 2:153"
	mustReject(t, withSense(t, s), "cites verse")
	s = good()
	s.SenseFr = "tenir ferme ; voir 103:3"
	mustReject(t, withSense(t, s), "cites verse")
}

// The same boundary, named rather than numbered.
func TestASenseNamingASuraStopsTheBuild(t *testing.T) {
	s := good()
	s.SenseEn = "to hold fast; to be steadfast, as Al-Baqarah has it"
	mustReject(t, withSense(t, s), "names the sura")
}

// Lower-case English that happens to spell a transliterated sura is a word, not
// a citation. If the check could not tell them apart it would refuse true
// senses, and the silence would look like an absence of evidence.
func TestAnOrdinaryEnglishWordThatSpellsASuraIsNotACitation(t *testing.T) {
	c := fromShipped(t)
	c.Senses = &Senses{Attribution: "Wird's own wording.", Senses: []Sense{{
		Root: "حزن", SenseEn: "to grieve; grief", SenseFr: "s'affliger ; l'affliction",
		Support: []rootsense.Support{{Word: "حَزَنًۭا", Gloss: "grief", Slot: "noun"}},
	}}}
	if err := errors.Join(c.checkSenses()...); err != nil {
		t.Fatalf("a plain English sense was read as a citation: %v", err)
	}
}

// French is a translation of the verified English and inherits its evidence.
// Shipping the English alone would leave a French reader with a heading and no
// sense under it.
func TestAVerifiedSenseWithNoFrenchStopsTheBuild(t *testing.T) {
	s := good()
	s.SenseFr = ""
	mustReject(t, withSense(t, s), "no French")
}

// The attribution is the only thing in corpus.db that tells a reader this prose
// is Wird's own and not a lexicon's.
func TestSensesWithNoAttributionStopTheBuild(t *testing.T) {
	c := fromShipped(t)
	c.Senses = &Senses{Senses: []Sense{good()}}
	mustReject(t, errors.Join(c.checkSenses()...), "no attribution")
}

// The file that actually ships has to pass the gate that guards it, or the gate
// is guarding a file nobody builds.
func TestTheShippedSenseFilePassesTheGate(t *testing.T) {
	s, err := LoadSenses("../../../data/root_senses.json")
	if err != nil {
		t.Fatal(err)
	}
	if len(s.Senses) == 0 {
		t.Fatal("the shipped sense file is empty")
	}
	c := fromShipped(t)
	c.Senses = s
	if err := errors.Join(c.checkSenses()...); err != nil {
		t.Fatalf("the shipped senses do not pass their own gate: %v", err)
	}
}

func mustReject(t *testing.T, err error, want string) {
	t.Helper()
	if err == nil {
		t.Fatalf("the build was not stopped; wanted a failure mentioning %q", want)
	}
	if !strings.Contains(err.Error(), want) {
		t.Fatalf("stopped for the wrong reason: %v, wanted %q", err, want)
	}
}
