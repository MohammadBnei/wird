package rootsense

import (
	"fmt"
	"io"
	"math"
	"sort"
	"text/tabwriter"
)

// The Calibration set exists to set the threshold by measurement rather than
// by taste. It pairs roots whose meaning is not in doubt with senses known to
// be right and senses known to be wrong, and the wrong ones are chosen to be
// hard: a plausible-sounding opposite, a sense lifted from a different root, a
// sense that is true of everything and so predicts nothing, and one that keeps
// the true core but adds false elaboration.
//
// Senses here are written as a lexicographer would write them — plain sense,
// no verse, nothing attributed to anyone. They are Calibration inputs, not
// shippable content.

type Case struct {
	Root  string
	Sense string
	Right bool
	Why   string // for the wrong ones: which failure mode this is
	Axis  string // which term this case is a fixture for; empty means the score
}

// The three axes. A wrong sense is a fixture for exactly one of them, because
// each family was chosen to defeat the other two: a minority-branch sense has a
// genuinely attested core and scores well, and a doctrinal elaboration scores
// well and covers well. Calibrating a floor against a family it was never meant
// to catch is how a multi-part bar collapses back into one number — the score
// floor, fitted against all 44 wrong senses at once, lands at 0.933 and takes
// twelve of the fifteen right senses with it.
const (
	axisCoverage   = "coverage"
	axisDispersion = "dispersion"
	axisBranch     = "branch"
	axisLead       = "lead"
)

var Calibration = []Case{
	// Senses known to be right. Each names every branch of its root the corpus
	// actually realises, not only the branch a dictionary would lead with: كتب
	// is met as كِتَاب far more often than as "he wrote", and a sense that says
	// only "to write" leaves the word a reader meets unexplained. Six of these
	// were phrased that second way when the check had no coverage term, and the
	// term is what made the difference visible.
	{Root: "صبر", Sense: "to be patient; to be steadfast; to endure", Right: true},
	{Root: "كتب", Sense: "a book, a writ; to write; to prescribe", Right: true},
	{Root: "علم", Sense: "to know; to have knowledge", Right: true},
	{Root: "رحم", Sense: "to be merciful; to show mercy", Right: true},
	{Root: "قول", Sense: "to say; to speak; a word, a saying", Right: true},
	{Root: "نزل", Sense: "to send down; to reveal; to descend", Right: true},
	{Root: "سمع", Sense: "to hear; to listen", Right: true},
	{Root: "غفر", Sense: "to forgive; to cover over", Right: true},
	{Root: "عبد", Sense: "to worship; to serve; a slave, a servant", Right: true},
	{Root: "حكم", Sense: "to be wise; to judge; to decide", Right: true},
	{Root: "ظلم", Sense: "to wrong; to do injustice", Right: true},
	{Root: "شكر", Sense: "to be grateful; to thank", Right: true},
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
	// Not a dispersion fixture: "send" is glossed under 18 roots and the right
	// senses' own least common word, "cover", under 15, so no floor parts them.
	// What rejects this is the cross-form demand — it hits one slot of seven.
	{Root: "كتب", Sense: "to send down a book", Why: "elaboration borrowed from another root"},
	{Root: "رحم", Sense: "to be merciful to those who travel", Why: "true core plus false elaboration", Axis: axisDispersion},

	// Senses that name a real but minority branch of their root. Every one of
	// these shipped once and every one passed a check that scored distinct
	// glosses and never counted occurrences. They are true of a few words and
	// silent about the word a reader meets: غير shipped as "to change" while
	// most of its 154 occurrences are the particle غَيْر, "other than", the one
	// in Al-Fatiha. This family is what the coverage term exists for; the score
	// cannot reject them, because their cores really are attested.
	{Root: "غير", Sense: "to change; to alter", Why: "minority branch; mostly غَيْر, other than", Axis: axisCoverage},
	{Root: "قوم", Sense: "to stand; to rise; to stand firm", Why: "minority branch; mostly قَوْم, a people", Axis: axisCoverage},
	{Root: "قبل", Sense: "to face; to accept; to receive", Why: "minority branch; mostly قَبْل, before", Axis: axisCoverage},
	{Root: "بعد", Sense: "to be far; to be distant", Why: "minority branch; mostly بَعْد, after", Axis: axisCoverage},
	{Root: "بني", Sense: "to build; to construct", Why: "minority branch; mostly ٱبْن, son", Axis: axisCoverage},
	{Root: "ملأ", Sense: "to fill; to be full", Why: "minority branch; mostly ٱلْمَلَأ, the chiefs", Axis: axisCoverage},
	{Root: "سمو", Sense: "to name; to give a name", Why: "minority branch; mostly سَمَاء, the heavens", Axis: axisCoverage},
	{Root: "دنو", Sense: "to be near; to draw near; to be low", Why: "minority branch; mostly ٱلدُّنْيَا, the world", Axis: axisCoverage},
	{Root: "أخر", Sense: "to put back; to delay; to come last", Why: "minority branch; mostly ٱلْءَاخِرَة, the hereafter", Axis: axisCoverage},
	{Root: "ملك", Sense: "to own; to possess; to have power over", Why: "minority branch; mostly مَلَٰئِكَة, the angels", Axis: axisCoverage},
	{Root: "سور", Sense: "a wall; an enclosure", Why: "minority branch; mostly سُورَة, a sura", Axis: axisCoverage},
	{Root: "برر", Sense: "to be dutiful; to do good", Why: "minority branch; mostly بَرّ, the land", Axis: axisCoverage},
	{Root: "قرن", Sense: "to join together; a companion", Why: "minority branch; mostly قَرْن, the generations", Axis: axisCoverage},
	{Root: "صبح", Sense: "morning; to enter upon morning", Why: "minority branch; mostly أَصْبَحَ, became", Axis: axisCoverage},
	{Root: "ربو", Sense: "to grow; to increase; to swell", Why: "minority branch; mostly رِبَوٰا۟, usury", Axis: axisCoverage},
	{Root: "ضرب", Sense: "to strike; to beat", Why: "minority branch; much of it ضَرَبَ مَثَلًا, sets forth a parable", Axis: axisCoverage},

	// A true core with a doctrinal clause bolted on. The core is attested, so
	// the score is high and the coverage is high; the rider is not attested at
	// all, and nothing in either term looks at it. This is how a claim about
	// doctrine enters a field that is supposed to be a claim about a word, and
	// it is what the dispersion term exists for: every one of these riders is a
	// word the corpus glosses under one or two OTHER roots.
	{Root: "صلو", Sense: "to pray; to pray five times", Why: "doctrinal elaboration", Axis: axisDispersion},
	{Root: "علم", Sense: "to know; to have knowledge of the unseen future", Why: "doctrinal elaboration", Axis: axisDispersion},
	{Root: "رزق", Sense: "to provide; to grant provision to the believers", Why: "doctrinal elaboration", Axis: axisDispersion},
	{Root: "صوم", Sense: "to fast; to fast from dawn to sunset in Ramadan", Why: "doctrinal elaboration", Axis: axisDispersion},
	{Root: "حجج", Sense: "to argue; to dispute; to make the pilgrimage to Mecca", Why: "doctrinal elaboration", Axis: axisDispersion},
	{Root: "شهد", Sense: "to witness; to testify that there is no god but Allah", Why: "doctrinal elaboration", Axis: axisDispersion},
	{Root: "غفر", Sense: "to forgive; to cover over; to forgive every sin but idolatry", Why: "doctrinal elaboration", Axis: axisDispersion},
	{Root: "رحم", Sense: "to be merciful; to show mercy to the believers alone", Why: "doctrinal elaboration", Axis: axisDispersion},
	{Root: "طهر", Sense: "to be pure; to purify by ablution before prayer", Why: "doctrinal elaboration", Axis: axisDispersion},
	{Root: "هدي", Sense: "to guide; to show the way; to guide only whom he wills to paradise", Why: "doctrinal elaboration", Axis: axisDispersion},

	// An invented clause carrying no attested word at all. The rule these
	// defeat asked whether a clause contained an attested word and waved
	// through every clause that did not, which is the shape of pure invention
	// as much as of an alternative phrasing. What separates the two is company:
	// somewhere in the corpus a root is glossed both "rule" and "judge", and no
	// root is ever glossed both "qiblah" and "pray" or both "Ramadan" and
	// "fast".
	{Root: "صلو", Sense: "a prayer; to pray; to face the qiblah five times each day", Why: "invented clause, no attested word to ride on", Axis: axisDispersion},
	{Root: "صوم", Sense: "to fast; to abstain from dawn until sunset in Ramadan", Why: "invented clause, no attested word to ride on", Axis: axisDispersion},

	// A root whose dominant branch is glossed in stopwords alone. جمع's
	// جَمِيع is "all" and كثر's أَكْثَرُهُمْ is "most", and a gloss made of
	// nothing but stopwords used to be dropped before the denominator, so both
	// roots cleared a majority of a count their own majority was missing from.
	{Root: "جمع", Sense: "to gather; to collect", Why: "minority branch; 51 occurrences glossed \"all\"", Axis: axisCoverage},
	{Root: "كثر", Sense: "to be many; to be much; to increase", Why: "minority branch; 73 occurrences glossed \"most\"", Axis: axisCoverage},

	// A sense that explains a majority of its root and still leaves one word
	// of it unexplained. Coverage is a total and a total can be a majority
	// while a third of the root sits in a single branch nobody named: a reader
	// tapping مُنَافِقُونَ, the title word of Sūrah 63, is told about spending.
	{Root: "نفق", Sense: "to spend; to spend out", Why: "34 of 111 occurrences are the hypocrites", Axis: axisBranch},
	{Root: "عود", Sense: "to return; to go back; to repeat", Why: "23 of 63 occurrences are the tribe 'Aad", Axis: axisBranch},
	{Root: "سجد", Sense: "to prostrate", Why: "22 of 92 occurrences are Al-Masjid", Axis: axisBranch},
	{Root: "حجج", Sense: "to argue; to dispute", Why: "8 of 33 occurrences are the Hajj", Axis: axisBranch},
	{Root: "ثوب", Sense: "to reward; a recompense", Why: "7 of 28 occurrences are garments", Axis: axisBranch},
	{Root: "طوي", Sense: "to fold; to fold up", Why: "2 of 5 occurrences are the valley Tuwa", Axis: axisBranch},

	// A sense that names every branch and reads them out in the wrong order.
	// Coverage is indifferent to order; a reader is not, and stops at the first
	// clause: ملأ is met as ٱلْمَلَأ, the chiefs, three times for every time it
	// is met as filling.
	{Root: "ملأ", Sense: "to fill; full; the chiefs, the assembly", Why: "leads with the minority branch", Axis: axisLead},
	{Root: "بني", Sense: "to build; a son, children", Why: "leads with the minority branch", Axis: axisLead},
	{Root: "سبح", Sense: "to swim; to glide; to glorify", Why: "leads with the minority branch", Axis: axisLead},
}

// majority is the coverage floor, and it is stated rather than fitted. The
// other two floors are placed where the populations part, because nothing but
// the corpus says where they belong. Coverage is different: the reason the term
// exists supplies its own number. A sense explaining fewer than half of its
// root's occurrences is, for the reader who meets that word, wrong more often
// than right, and no separation measured on thirty fixtures can make 0.4 an
// acceptable answer to that. What the Calibration does here is check the claim
// rather than set it: CoverageGap reports where the two populations actually
// part, and the test fails if the majority line does not fall inside that gap.
const majority = 0.5

type Separation struct {
	Right, Wrong []float64
	Bar          Bar
	CoverageGap  float64 // where the populations part on coverage, for the test
	FalsePass    []Case  // wrong senses the bar lets through
	FalseFail    []Case  // right senses the bar rejects
}

// unnamed turns a branch share into the same shape as every other axis, where
// more is better, so one gap function places every floor.
func unnamed(shares []float64) []float64 {
	out := make([]float64, len(shares))
	for i, v := range shares {
		out[i] = 1 - v
	}
	return out
}

// gap places a floor at the midpoint of the widest gap between a wrong value
// and the next right value above it. A floor chosen by taste is a check that
// always passes; this one is chosen by where the two populations part. It
// returns 0 when they do not part at all, which is the honest answer that the
// axis discriminates nothing.
func gap(right, wrong []float64) float64 {
	sort.Float64s(right)
	sort.Float64s(wrong)
	best, lo, hi := 0.0, 0.0, 0.0
	for _, w := range wrong {
		for _, r := range right {
			if r <= w {
				continue
			}
			higherWrong := false
			for _, w2 := range wrong {
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
	return (lo + hi) / 2
}

// Calibrate scores every Calibration case and places the threshold at the
// midpoint of the widest gap between a wrong score and the next right score
// above it. A threshold chosen by taste is a check that always passes; this
// one is chosen by where the two populations actually part.
func Calibrate(roots map[string]*Root) (Separation, error) {
	var sep Separation
	type scored struct {
		c   Case
		res Result
		s   float64
	}
	var all []scored
	var rScore, wScore, rCov, wCov, rDisp, wDisp, rBranch, wBranch []float64
	for _, c := range Calibration {
		r, ok := roots[c.Root]
		if !ok {
			return sep, fmt.Errorf("Calibration root %q not in corpus", c.Root)
		}
		res := Check(r, c.Sense)
		s := res.Score
		if res.SlotsHit < 2 { // the cross-form demand, applied before the bar
			s = 0
		}
		all = append(all, scored{c, res, s})
		// A sense with no rider says nothing about where the dispersion floor
		// belongs, so it is left out of that axis. Including it would place the
		// floor between the wrong senses and the sentinel, which is a number
		// about the sentinel and not about the corpus.
		if c.Right {
			sep.Right = append(sep.Right, s)
			rScore = append(rScore, s)
			rCov = append(rCov, res.Coverage)
			rBranch = append(rBranch, res.Branch)
			if res.Dispersion != NoUngrounded {
				rDisp = append(rDisp, float64(res.Dispersion))
			}
			continue
		}
		sep.Wrong = append(sep.Wrong, s)
		switch c.Axis {
		case axisCoverage:
			wCov = append(wCov, res.Coverage)
		case axisDispersion:
			if res.Dispersion != NoUngrounded {
				wDisp = append(wDisp, float64(res.Dispersion))
			}
		case axisBranch:
			wBranch = append(wBranch, res.Branch)
		case axisLead:
			// The lead is a comparison between a sense's own clauses, so it has
			// no threshold to place: a sense either leads with the branch a
			// reader meets or it does not.
		default:
			wScore = append(wScore, s)
		}
	}
	sort.Float64s(sep.Right)
	sort.Float64s(sep.Wrong)

	sep.Bar = Bar{
		Score:      gap(rScore, wScore),
		Coverage:   majority,
		Dispersion: int(math.Ceil(gap(rDisp, wDisp))),
		Branch:     1 - gap(unnamed(rBranch), unnamed(wBranch)),
	}
	sep.CoverageGap = gap(rCov, wCov)

	for _, s := range all {
		s.res.Score = s.s
		switch {
		case !s.c.Right && s.res.Verified(sep.Bar):
			sep.FalsePass = append(sep.FalsePass, s.c)
		case s.c.Right && !s.res.Verified(sep.Bar):
			sep.FalseFail = append(sep.FalseFail, s.c)
		}
	}
	return sep, nil
}

func (s Separation) Report(w io.Writer, roots map[string]*Root) {
	tw := tabwriter.NewWriter(w, 0, 0, 2, ' ', 0)
	fmt.Fprintln(tw, "verdict\troot\tscore\tcover\tdisp\tbranch\tleads\tslots\tsense\twhy")
	for _, c := range Calibration {
		res := Check(roots[c.Root], c.Sense)
		if res.SlotsHit < 2 {
			res.Score = 0
		}
		label := "WRONG"
		if c.Right {
			label = "right"
		}
		fmt.Fprintf(tw, "%s\t%s\t%.3f\t%.3f\t%s\t%.3f\t%v\t%d/%d\t%s\t%s\n",
			label, c.Root, res.Score, res.Coverage, Disp(res.Dispersion),
			res.Branch, res.Leads, res.SlotsHit, len(res.Slots), c.Sense, c.Why)
	}
	tw.Flush()

	fmt.Fprintf(w, "\nright senses  n=%d  score min %.3f  max %.3f\n", len(s.Right), s.Right[0], s.Right[len(s.Right)-1])
	fmt.Fprintf(w, "wrong senses  n=%d  score min %.3f  max %.3f\n", len(s.Wrong), s.Wrong[0], s.Wrong[len(s.Wrong)-1])
	fmt.Fprintf(w, "bar           score %.3f   coverage %.3f   dispersion %d   branch %.3f   leads\n",
		s.Bar.Score, s.Bar.Coverage, s.Bar.Dispersion, s.Bar.Branch)
	fmt.Fprintf(w, "              score and dispersion sit where the populations part; coverage is\n")
	fmt.Fprintf(w, "              stated at a majority, and the populations part at %.3f\n", s.CoverageGap)
	fmt.Fprintf(w, "right passing %d/%d   wrong rejected %d/%d\n",
		len(s.Right)-len(s.FalseFail), len(s.Right), len(s.Wrong)-len(s.FalsePass), len(s.Wrong))
	for _, c := range s.FalsePass {
		fmt.Fprintf(w, "  wrong sense passes: %s  %q  (%s)\n", c.Root, c.Sense, c.Why)
	}
	for _, c := range s.FalseFail {
		res := Check(roots[c.Root], c.Sense)
		fmt.Fprintf(w, "  right sense fails:  %s  %q  (score %.3f cover %.3f disp %s branch %.3f leads %v)\n",
			c.Root, c.Sense, res.Score, res.Coverage, Disp(res.Dispersion), res.Branch, res.Leads)
	}
}

func Disp(n int) string {
	if n == NoUngrounded {
		return "-"
	}
	return fmt.Sprint(n)
}
