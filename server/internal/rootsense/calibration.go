package rootsense

import (
	"fmt"
	"io"
	"sort"
	"text/tabwriter"
)

// The calibration set exists to set the threshold by measurement rather than
// by taste. It pairs roots whose meaning is not in doubt with senses known to
// be right and senses known to be wrong, and the wrong ones are chosen to be
// hard: a plausible-sounding opposite, a sense lifted from a different root, a
// sense that is true of everything and so predicts nothing, and one that keeps
// the true core but adds false elaboration.
//
// Senses here are written as a lexicographer would write them — plain sense,
// no verse, nothing attributed to anyone. They are calibration inputs, not
// shippable content.

type Case struct {
	Root  string
	Sense string
	Right bool
	Why   string // for the wrong ones: which failure mode this is
}

var Calibration = []Case{
	{Root: "صبر", Sense: "to hold fast; to be steadfast; to endure", Right: true},
	{Root: "كتب", Sense: "to write; to inscribe; to prescribe", Right: true},
	{Root: "علم", Sense: "to know; to have knowledge", Right: true},
	{Root: "رحم", Sense: "to be merciful; to show mercy", Right: true},
	{Root: "قول", Sense: "to say; to speak", Right: true},
	{Root: "نزل", Sense: "to descend; to send down", Right: true},
	{Root: "سمع", Sense: "to hear; to listen", Right: true},
	{Root: "غفر", Sense: "to forgive; to cover over", Right: true},
	{Root: "عبد", Sense: "to serve; to worship", Right: true},
	{Root: "حكم", Sense: "to judge; to decide; to rule", Right: true},
	{Root: "ظلم", Sense: "to wrong; to do injustice", Right: true},
	{Root: "شكر", Sense: "to thank; to be grateful", Right: true},
	{Root: "كفر", Sense: "to disbelieve; to reject; to cover over", Right: true},
	{Root: "خلق", Sense: "to create; to bring into being", Right: true},
	{Root: "رزق", Sense: "to provide; to grant provision", Right: true},

	{Root: "صبر", Sense: "to be sad; to grieve", Why: "plausible opposite"},
	{Root: "كتب", Sense: "to ride; to mount", Why: "borrowed from another root"},
	{Root: "علم", Sense: "to eat; to consume", Why: "borrowed from another root"},
	{Root: "رحم", Sense: "to strike; to beat", Why: "borrowed from another root"},
	{Root: "عبد", Sense: "to write; to inscribe", Why: "borrowed from another root"},
	{Root: "حكم", Sense: "to travel; to journey", Why: "borrowed from another root"},
	{Root: "ظلم", Sense: "to thank; to be grateful", Why: "borrowed from another root"},
	{Root: "شكر", Sense: "to wrong; to do injustice", Why: "borrowed from another root"},
	{Root: "خلق", Sense: "to provide; to grant provision", Why: "borrowed from another root"},
	{Root: "رزق", Sense: "to create; to bring into being", Why: "borrowed from another root"},
	{Root: "كفر", Sense: "to hear; to listen", Why: "borrowed from another root"},
	{Root: "سمع", Sense: "to see; to look", Why: "adjacent sense, wrong sense"},
	{Root: "قول", Sense: "to be; to become; to exist", Why: "true of everything, predicts nothing"},
	{Root: "غفر", Sense: "to do; to make; to act", Why: "true of everything, predicts nothing"},
	{Root: "نزل", Sense: "a thing; a matter; an affair", Why: "true of everything, predicts nothing"},
	{Root: "نزل", Sense: "Allah; the Lord; the believers", Why: "names the context, not the word"},
	{Root: "كتب", Sense: "to send down a book", Why: "true core plus false elaboration"},
	{Root: "رحم", Sense: "to be merciful to those who travel", Why: "true core plus false elaboration"},
}

type Separation struct {
	Right, Wrong []float64
	Threshold    float64
	FalsePass    []Case // wrong senses the threshold lets through
	FalseFail    []Case // right senses the threshold rejects
}

// Calibrate scores every calibration case and places the threshold at the
// midpoint of the widest gap between a wrong score and the next right score
// above it. A threshold chosen by taste is a check that always passes; this
// one is chosen by where the two populations actually part.
func Calibrate(roots map[string]*Root) (Separation, error) {
	var sep Separation
	type scored struct {
		c Case
		s float64
	}
	var all []scored
	for _, c := range Calibration {
		r, ok := roots[c.Root]
		if !ok {
			return sep, fmt.Errorf("calibration root %q not in corpus", c.Root)
		}
		res := Check(r, c.Sense)
		s := res.Score
		if res.SlotsHit < 2 { // the cross-form demand, applied before the threshold
			s = 0
		}
		all = append(all, scored{c, s})
		if c.Right {
			sep.Right = append(sep.Right, s)
		} else {
			sep.Wrong = append(sep.Wrong, s)
		}
	}
	sort.Float64s(sep.Right)
	sort.Float64s(sep.Wrong)

	// widest gap between the top of the wrong population and a right score
	// above it, ignoring wrong scores that already sit inside the right band.
	best, lo, hi := 0.0, 0.0, 0.0
	for _, w := range sep.Wrong {
		for _, r := range sep.Right {
			if r <= w {
				continue
			}
			higherWrong := false
			for _, w2 := range sep.Wrong {
				if w2 > w && w2 < r {
					higherWrong = true
				}
			}
			if higherWrong {
				continue
			}
			if r-w > best {
				best, lo, hi = r-w, w, r
			}
			break
		}
	}
	sep.Threshold = (lo + hi) / 2

	for _, s := range all {
		switch {
		case !s.c.Right && s.s >= sep.Threshold:
			sep.FalsePass = append(sep.FalsePass, s.c)
		case s.c.Right && s.s < sep.Threshold:
			sep.FalseFail = append(sep.FalseFail, s.c)
		}
	}
	return sep, nil
}

func (s Separation) Report(w io.Writer, roots map[string]*Root) {
	tw := tabwriter.NewWriter(w, 0, 0, 2, ' ', 0)
	fmt.Fprintln(tw, "verdict\troot\tscore\trecall\tprec\tslots\tsense")
	for _, c := range Calibration {
		res := Check(roots[c.Root], c.Sense)
		score := res.Score
		if res.SlotsHit < 2 {
			score = 0
		}
		label := "WRONG"
		if c.Right {
			label = "right"
		}
		fmt.Fprintf(tw, "%s\t%s\t%.3f\t%.3f\t%.3f\t%d/%d\t%s\n",
			label, c.Root, score, res.Recall, res.Precision, res.SlotsHit, len(res.Slots), c.Sense)
	}
	tw.Flush()

	fmt.Fprintf(w, "\nright senses  n=%d  min %.3f  max %.3f\n", len(s.Right), s.Right[0], s.Right[len(s.Right)-1])
	fmt.Fprintf(w, "wrong senses  n=%d  min %.3f  max %.3f\n", len(s.Wrong), s.Wrong[0], s.Wrong[len(s.Wrong)-1])
	fmt.Fprintf(w, "threshold     %.3f  (midpoint of the widest gap between the populations)\n", s.Threshold)
	fmt.Fprintf(w, "right passing %d/%d   wrong rejected %d/%d\n",
		len(s.Right)-len(s.FalseFail), len(s.Right), len(s.Wrong)-len(s.FalsePass), len(s.Wrong))
	for _, c := range s.FalsePass {
		fmt.Fprintf(w, "  wrong sense passes: %s  %q  (%s)\n", c.Root, c.Sense, c.Why)
	}
	for _, c := range s.FalseFail {
		fmt.Fprintf(w, "  right sense fails:  %s  %q\n", c.Root, c.Sense)
	}
}
