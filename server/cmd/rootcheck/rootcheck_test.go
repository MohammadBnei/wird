package main

import (
	"os"
	"path/filepath"
	"sync"
	"testing"
)

const corpusPath = "../../../app/assets/corpus.db"

var (
	once   sync.Once
	loaded map[string]*Root
	lodErr error
)

func corpus(t *testing.T) map[string]*Root {
	t.Helper()
	once.Do(func() {
		p, err := filepath.Abs(corpusPath)
		if err != nil {
			lodErr = err
			return
		}
		if _, err := os.Stat(p); err != nil {
			lodErr = err
			return
		}
		loaded, lodErr = LoadRoots(p)
	})
	if lodErr != nil {
		t.Fatalf("load corpus: %v", lodErr)
	}
	return loaded
}

// A check that cannot reject a sense known to be wrong is not a check. These
// are the deliberate wrong senses: a plausible opposite, senses lifted from
// other roots, and senses too general to predict anything.
func TestSenseKnownToBeWrongDoesNotReachTheThreshold(t *testing.T) {
	roots := corpus(t)
	sep, err := Calibrate(roots)
	if err != nil {
		t.Fatal(err)
	}
	for _, c := range calibration {
		if c.Right || c.Why == "true core plus false elaboration" {
			continue
		}
		res := Check(roots[c.Root], c.Sense)
		if res.Verified(sep.Threshold) {
			t.Errorf("%s %q (%s) passed at %.3f, threshold %.3f",
				c.Root, c.Sense, c.Why, res.Score, sep.Threshold)
		}
	}
}

// The other half of the same failure: a threshold strict enough to reject
// everything would also be useless, so senses known to be right must pass.
func TestSenseKnownToBeRightIsNotRejected(t *testing.T) {
	roots := corpus(t)
	sep, err := Calibrate(roots)
	if err != nil {
		t.Fatal(err)
	}
	for _, c := range calibration {
		if !c.Right {
			continue
		}
		res := Check(roots[c.Root], c.Sense)
		if !res.Verified(sep.Threshold) {
			t.Errorf("%s %q rejected at %.3f, threshold %.3f",
				c.Root, c.Sense, res.Score, sep.Threshold)
		}
	}
}

// The threshold must come from where the two populations part, not from a
// constant someone liked the look of. If the gap closes, the check has stopped
// discriminating and should fail loudly rather than keep passing.
func TestThresholdSitsInAGapBetweenTheTwoPopulations(t *testing.T) {
	sep, err := Calibrate(corpus(t))
	if err != nil {
		t.Fatal(err)
	}
	if sep.Threshold <= 0 {
		t.Fatal("no gap found between right and wrong senses")
	}
	lowestRight := sep.Right[0]
	if sep.Threshold >= lowestRight {
		t.Errorf("threshold %.3f is at or above the lowest right sense %.3f", sep.Threshold, lowestRight)
	}
	if len(sep.FalseFail) > 0 {
		t.Errorf("threshold rejects right senses: %v", sep.FalseFail)
	}
	// One wrong sense is known to sit inside the right band: it keeps the true
	// core and adds false elaboration, which this check cannot see. More than
	// one means the separation has degraded.
	if len(sep.FalsePass) > 1 {
		t.Errorf("wrong senses passing: %d, want at most 1: %v", len(sep.FalsePass), sep.FalsePass)
	}
}

// A root attested in one morphological shape offers nothing to predict across.
// Reporting a score for it would dress a single gloss up as cross-form
// agreement, so the verdict has to be an admission instead.
func TestRootWithOneSlotIsReportedAsUnverifiable(t *testing.T) {
	roots := corpus(t)
	var single *Root
	for _, r := range roots {
		if len(r.Slots) == 1 {
			single = r
			break
		}
	}
	if single == nil {
		t.Skip("corpus has no single-slot root")
	}
	// Even the root's own gloss, fed back in verbatim, must not verify it.
	res := Check(single, single.Slots[0].Glosses[0])
	if got := res.Verdict(0.127); got != "cannot verify" {
		t.Errorf("root %s verdict = %q, want %q", single.Letters, got, "cannot verify")
	}
	if res.Verified(0.127) {
		t.Errorf("root %s verified on one slot", single.Letters)
	}
}

// The wazn contributes English of its own. If a sense made only of pattern
// words could score, every Form X root would verify against "to seek" and the
// check would be measuring the pattern instead of the root.
func TestPatternWordsAloneEarnNoCredit(t *testing.T) {
	root := &Root{Letters: "test", Words: 4, Slots: []Slot{
		{Name: "form-X", Glosses: []string{"they seek forgiveness", "ask forgiveness"}},
		{Name: "form-I", Glosses: []string{"he forgave", "the forgiving"}},
	}}
	if res := Check(root, "to seek; to ask"); res.Score != 0 {
		t.Errorf("pattern-only sense scored %.3f, want 0 (slots %v)", res.Score, res.Slots)
	}
	if res := Check(root, "to forgive"); res.Score == 0 {
		t.Error("the root's own sense scored 0 once pattern words were stripped")
	}
}

// Glosses and dictionary senses inflect differently. A stemmer that splits
// them makes a true sense look unattested, which ships silence where the
// corpus actually agrees.
func TestInflectionDoesNotHideAgreement(t *testing.T) {
	pairs := [][2]string{
		{"know", "knowledge"}, {"forgive", "forgiveness"}, {"provide", "provision"},
		{"merciful", "mercy"}, {"patient", "patience"}, {"create", "creation"},
	}
	for _, p := range pairs {
		a, b := stem(p[0]), stem(p[1])
		if !related(a, b) && !related(b, a) {
			t.Errorf("%q and %q read as unrelated (%q / %q)", p[0], p[1], a, b)
		}
	}
	// Prefix tolerance is deliberately loose, but it must still be tolerance
	// and not a wildcard: unrelated words of similar length stay apart.
	for _, p := range [][2]string{{"write", "ride"}, {"judge", "journey"}, {"thank", "wrong"}} {
		if related(stem(p[0]), stem(p[1])) {
			t.Errorf("%q and %q read as related", p[0], p[1])
		}
	}
}

// An empty or stopword-only sense must not come back verified on a technicality.
func TestSenseWithNoContentIsNotVerified(t *testing.T) {
	roots := corpus(t)
	for _, s := range []string{"", "   ", "the and of it"} {
		res := Check(roots["صبر"], s)
		if res.Verified(0.127) || res.Score != 0 {
			t.Errorf("sense %q scored %.3f", s, res.Score)
		}
	}
}

// Every rule the scorer strips must be one the corpus actually supports.
// Adding a rule from a grammar book without measuring it would quietly remove
// real evidence from the glosses.
func TestEveryStrippedRuleIsMeasuredAsReliable(t *testing.T) {
	roots := corpus(t)
	for slot, ms := range markers {
		for _, m := range ms {
			var hits, total int
			for _, r := range roots {
				for _, s := range r.Slots {
					if s.Name != slot {
						continue
					}
					for _, g := range s.Glosses {
						total++
						for _, tok := range wordRe.FindAllString(g, -1) {
							if tok == m {
								hits++
								break
							}
						}
					}
				}
			}
			if total == 0 {
				t.Errorf("slot %s has no glosses", slot)
				continue
			}
			if cov := float64(hits) / float64(total); cov < 0.03 {
				t.Errorf("%s marker %q fires in %.2f%% of glosses; too rare to be a rule", slot, m, cov*100)
			}
		}
	}
}
