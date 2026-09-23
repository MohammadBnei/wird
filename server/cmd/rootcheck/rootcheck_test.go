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

func shipBar(t *testing.T) Bar {
	t.Helper()
	sep, err := Calibrate(corpus(t))
	if err != nil {
		t.Fatal(err)
	}
	return sep.Bar
}

// A check that cannot reject a sense known to be wrong is not a check. Every
// wrong sense must be rejected by the assembled bar, whichever term it was
// written to defeat: a plausible opposite, a sense lifted from another root, a
// sense too general to predict anything, a sense naming a minority branch of
// its own root, and a true core with a doctrinal clause bolted on.
func TestSenseKnownToBeWrongIsRejectedByTheWholeBar(t *testing.T) {
	roots, b := corpus(t), shipBar(t)
	for _, c := range calibration {
		if c.Right {
			continue
		}
		res := Check(roots[c.Root], c.Sense)
		if res.Verified(b) {
			t.Errorf("%s %q (%s) passed: score %.3f cover %.3f disp %s",
				c.Root, c.Sense, c.Why, res.Score, res.Coverage, disp(res.Dispersion))
		}
	}
}

// The two failures that actually shipped, each asserted against the term that
// was added for it. Without these the bar could quietly collapse back to the
// score alone and still pass every other test in this file.
func TestMinorityBranchSenseIsRejectedByCoverageAlone(t *testing.T) {
	roots, b := corpus(t), shipBar(t)
	for _, c := range calibration {
		if c.Axis != axisCoverage {
			continue
		}
		res := Check(roots[c.Root], c.Sense)
		if res.Score < b.Score {
			t.Errorf("%s %q scores %.3f, below the score floor; it is no longer a coverage fixture",
				c.Root, c.Sense, res.Score)
		}
		if res.Coverage >= b.Coverage {
			t.Errorf("%s %q explains %.3f of its root's occurrences, at or above the majority line",
				c.Root, c.Sense, res.Coverage)
		}
	}
}

func TestDoctrinalRiderIsRejectedByDispersionAlone(t *testing.T) {
	roots, b := corpus(t), shipBar(t)
	for _, c := range calibration {
		if c.Axis != axisDispersion {
			continue
		}
		res := Check(roots[c.Root], c.Sense)
		if res.Dispersion >= b.Dispersion {
			t.Errorf("%s %q has no rider under the floor: dispersion %s, floor %d",
				c.Root, c.Sense, disp(res.Dispersion), b.Dispersion)
		}
	}
}

// The dispersion floor is placed between the riders of right senses and the
// riders of wrong ones. With no right sense carrying a rider there is nothing
// above the wrong population, the floor collapses to zero, and every rider
// passes while the calibration still reports a clean separation.
func TestDispersionFloorHasARightSenseAnchoringItFromAbove(t *testing.T) {
	roots, b := corpus(t), shipBar(t)
	for _, c := range calibration {
		if !c.Right {
			continue
		}
		if d := Check(roots[c.Root], c.Sense).Dispersion; d != noUngrounded && d >= b.Dispersion {
			return
		}
	}
	t.Fatalf("no right sense carries a rider above the floor %d; the axis is unanchored", b.Dispersion)
}

// The other half of the same failure: a threshold strict enough to reject
// everything would also be useless, so senses known to be right must pass.
func TestSenseKnownToBeRightIsNotRejected(t *testing.T) {
	roots, b := corpus(t), shipBar(t)
	for _, c := range calibration {
		if !c.Right {
			continue
		}
		res := Check(roots[c.Root], c.Sense)
		if !res.Verified(b) {
			t.Errorf("%s %q rejected: score %.3f/%.3f cover %.3f/%.3f disp %s/%d",
				c.Root, c.Sense, res.Score, b.Score, res.Coverage, b.Coverage,
				disp(res.Dispersion), b.Dispersion)
		}
	}
}

// The threshold must come from where the two populations part, not from a
// constant someone liked the look of. If the gap closes, the check has stopped
// discriminating and should fail loudly rather than keep passing.
func TestEveryFloorSitsInAGapBetweenTheTwoPopulations(t *testing.T) {
	sep, err := Calibrate(corpus(t))
	if err != nil {
		t.Fatal(err)
	}
	if sep.Bar.Score <= 0 {
		t.Error("no gap found on the score axis")
	}
	if sep.Bar.Dispersion <= 0 {
		t.Error("no gap found on the dispersion axis")
	}
	if sep.Bar.Score >= sep.Right[0] {
		t.Errorf("score floor %.3f is at or above the lowest right sense %.3f", sep.Bar.Score, sep.Right[0])
	}
	// The coverage floor is stated at a majority rather than fitted, so the
	// calibration's job is to check the claim. If the populations stop parting
	// around the majority line, the number is no longer supported and saying so
	// is the point of the fixture set.
	if sep.CoverageGap <= 0 {
		t.Error("the coverage populations do not part at all")
	}
	for _, c := range calibration {
		res := Check(corpus(t)[c.Root], c.Sense)
		switch {
		case c.Right && res.Coverage < majority:
			t.Errorf("right sense %s %q covers %.3f, below the majority line", c.Root, c.Sense, res.Coverage)
		case c.Axis == axisCoverage && res.Coverage >= majority:
			t.Errorf("minority-branch sense %s %q covers %.3f, at or above the majority line",
				c.Root, c.Sense, res.Coverage)
		}
	}
	if len(sep.FalseFail) > 0 {
		t.Errorf("the bar rejects right senses: %v", sep.FalseFail)
	}
	if len(sep.FalsePass) > 0 {
		t.Errorf("the bar passes wrong senses: %v", sep.FalsePass)
	}
}

// Recall is a mean over distinct glosses, so a root whose minority branch is
// written many ways and whose majority branch is written one way scores well
// on a sense that explains only the minority. Counting occurrences is the whole
// difference between what the corpus holds and what a reader meets.
func TestCoverageCountsOccurrencesAndNotDistinctGlosses(t *testing.T) {
	root := &Root{Letters: "test", Words: 104, Slots: []Slot{
		{Name: "form-I", Glosses: []Gloss{{"he changed", 1}, {"they changed", 1}, {"and we changed", 1}}},
		{Name: "noun", Glosses: []Gloss{{"changing", 1}, {"other than him", 100}}},
	}}
	res := Check(root, "to change; to alter")
	if res.Recall < 0.5 {
		t.Fatalf("recall %.3f: the fixture no longer scores well on distinct glosses", res.Recall)
	}
	if res.Coverage > 0.1 {
		t.Errorf("coverage %.3f: the hundred occurrences of the branch the sense misses did not count",
			res.Coverage)
	}
}

// A clause offered INSTEAD of the attested words is an alternative phrasing and
// is already paid for in precision; a word bolted ONTO an attested clause is
// the doctrinal rider. Holding both to the dispersion floor would reject "to
// judge; to decide; to rule" for a word the corpus simply never uses.
func TestWhollyUnattestedClauseIsNotCountedAsARider(t *testing.T) {
	root := &Root{Letters: "test", Words: 4, Slots: []Slot{
		{Name: "form-I", Glosses: []Gloss{{"he prayed", 2}}},
		{Name: "noun", Glosses: []Gloss{{"the prayer", 2}}},
	}}
	if d := Check(root, "to pray; to supplicate").Dispersion; d != noUngrounded {
		t.Errorf("an unattested alternative phrasing read as a rider (dispersion %d)", d)
	}
	if d := Check(root, "to pray; to pray five times").Dispersion; d == noUngrounded {
		t.Error("a word bolted onto an attested clause was not read as a rider")
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
	res := Check(single, single.Slots[0].Glosses[0].Text)
	if got := res.Verdict(Bar{}); got != "cannot verify" {
		t.Errorf("root %s verdict = %q, want %q", single.Letters, got, "cannot verify")
	}
	if res.Verified(Bar{}) {
		t.Errorf("root %s verified on one slot", single.Letters)
	}
}

// The wazn contributes English of its own. If a sense made only of pattern
// words could score, every Form X root would verify against "to seek" and the
// check would be measuring the pattern instead of the root.
func TestPatternWordsAloneEarnNoCredit(t *testing.T) {
	root := &Root{Letters: "test", Words: 4, Slots: []Slot{
		{Name: "form-X", Glosses: []Gloss{{"they seek forgiveness", 1}, {"ask forgiveness", 1}}},
		{Name: "form-I", Glosses: []Gloss{{"he forgave", 1}, {"the forgiving", 1}}},
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
		if res.Verified(Bar{}) || res.Score != 0 {
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
						for _, tok := range wordRe.FindAllString(g.Text, -1) {
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
