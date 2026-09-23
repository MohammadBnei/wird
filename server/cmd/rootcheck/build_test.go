package main

import (
	"encoding/json"
	"os"
	"strings"
	"sync"
	"testing"

	"github.com/MohammadBnei/wird/server/internal/rootsense"
)

const (
	corpusPath = "../../../app/assets/corpus.db"
	sensesPath = "../../../data/root_senses.json"
	authored   = "../../../data/root_senses.tsv"
)

var (
	once   sync.Once
	roots  map[string]*rootsense.Root
	lodErr error
)

func corpus(t *testing.T) map[string]*rootsense.Root {
	t.Helper()
	once.Do(func() {
		if _, err := os.Stat(corpusPath); err != nil {
			lodErr = err
			return
		}
		roots, lodErr = rootsense.LoadRoots(corpusPath)
	})
	if lodErr != nil {
		t.Skipf("no corpus to check against: %v", lodErr)
	}
	return roots
}

func shipped(t *testing.T) Bundle {
	t.Helper()
	body, err := os.ReadFile(sensesPath)
	if err != nil {
		t.Skipf("no shipped sense file: %v", err)
	}
	var b Bundle
	if err := json.Unmarshal(body, &b); err != nil {
		t.Fatal(err)
	}
	if len(b.Senses) == 0 {
		t.Fatal("the shipped sense file is empty")
	}
	return b
}

// The provenance is the argument for the sense: it held in more than one
// morphological shape. Provenance drawn entirely from one shape would show the
// reader a claim that looks unsupported by the very evidence that carried it.
func TestProvenanceShowsMoreThanOneMorphologicalShape(t *testing.T) {
	for _, s := range shipped(t).Senses {
		slots := map[string]bool{}
		for _, sup := range s.Support {
			slots[sup.Slot] = true
		}
		if len(slots) < 2 {
			t.Errorf("%s %q: provenance covers %d shape(s), but the sense was kept because it "+
				"held in %d", s.Root, s.SenseEn, len(slots), s.SlotsHit)
		}
	}
}

// A sense that fits dozens of unrelated roots is not a sense, it is English
// general enough to fit anything. The bar is what senses known to be right
// actually do, measured here rather than written down, so this fails if the
// shipped file was edited by hand past what the method allows.
func TestNoShippedSenseFitsMoreRootsThanASenseKnownToBeRight(t *testing.T) {
	if testing.Short() {
		t.Skip("scores every shipped sense against every root")
	}
	rs := corpus(t)
	b := shipped(t)
	sep, err := rootsense.Calibrate(rs)
	if err != nil {
		t.Fatal(err)
	}
	letters := make([]string, 0, len(rs))
	for k := range rs {
		letters = append(letters, k)
	}
	bar := specificityBar(rs, letters, sep.Threshold)
	if bar <= 0 {
		t.Fatal("no sense known to be right verifies any other root; the bar is unmeasurable")
	}
	for _, s := range b.Senses {
		if n := otherRootsVerified(rs, letters, s.Root, s.SenseEn, sep.Threshold); n > bar {
			t.Errorf("%s %q also verifies %d other roots, above the measured bar of %d",
				s.Root, s.SenseEn, n, bar)
		}
	}
}

// Every shipped sense must be one that was actually authored. A row that
// appears in the certified file and nowhere in the written one arrived by some
// route other than a person writing it down.
func TestEveryShippedSenseAppearsInTheAuthoredFile(t *testing.T) {
	cands, err := ReadCandidates(authored)
	if err != nil {
		t.Skipf("no authored file: %v", err)
	}
	written := map[string]string{}
	for _, c := range cands {
		written[c.Root] = c.En
	}
	for _, s := range shipped(t).Senses {
		if written[s.Root] != s.SenseEn {
			t.Errorf("%s ships %q, which the authored file does not carry", s.Root, s.SenseEn)
		}
	}
}

// Silence is a correct answer and has to stay reachable. If everything proposed
// passed, the check would be agreeing rather than deciding.
func TestSomeAuthoredSensesAreRefused(t *testing.T) {
	cands, err := ReadCandidates(authored)
	if err != nil {
		t.Skipf("no authored file: %v", err)
	}
	if len(shipped(t).Senses) >= len(cands) {
		t.Errorf("all %d authored senses shipped; the check refused nothing", len(cands))
	}
}

// The authored file is what a person writes and the certified file is what the
// check allows. Neither may carry a verse citation, and catching it here says
// so at the source rather than only at the build.
func TestNoAuthoredSenseCitesAVerse(t *testing.T) {
	cands, err := ReadCandidates(authored)
	if err != nil {
		t.Skipf("no authored file: %v", err)
	}
	for _, c := range cands {
		for _, text := range []string{c.En, c.Fr} {
			if strings.ContainsAny(text, "0123456789") {
				t.Errorf("%s %q contains a digit; a sense is about the word, not a reference", c.Root, text)
			}
		}
	}
}
