package rootsense

import (
	"regexp"
	"sort"
	"strings"
)

// The check asks one question: does a proposed English sense predict the
// English glosses the corpus already carries for that root's words, across the
// morphological shapes those words appear in?
//
// It is a falsification test. It cannot confirm that a sense is true; it can
// only report that the corpus does, or does not, bear the sense out. A root
// whose sense the corpus cannot bear out ships nothing.

var stopWords = map[string]bool{}

func init() {
	for _, w := range strings.Fields(`a an the and or but so then of to in on at for from by with
		is are was were be been being it its he she they them him her you we i my your their his
		not no nor if that this those these there which who whom what when where will would shall
		may might can could do does did done has have had o ye thee thou thy as into upon than
		very more most such all any some one two ones out up down about again ever never us our me
		also upon`) {
		stopWords[w] = true
	}
}

var WordRe = regexp.MustCompile(`[a-z]+`)

// Stem strips the English suffixes that separate a gloss from a dictionary
// sense ("forgiving" / "forgive", "patience" / "patient", "mercy" /
// "merciful"). It is cruder than Porter on purpose: the vocabulary here is a
// few thousand short gloss words, and over-stripping costs less than a
// stemmer that splits "know" from "knowledge".
var suffixes = []string{
	"ledge", "ness", "ment", "tion", "sion", "ence", "ance", "ings", "ing",
	"edly", "ful", "ous", "ity", "ive", "ent", "ant", "ers", "ors", "est",
	"ies", "ed", "er", "or", "ly", "es", "s",
}

func Stem(w string) string {
	for _, suf := range suffixes {
		if strings.HasSuffix(w, suf) && len(w)-len(suf) >= 3 {
			w = w[:len(w)-len(suf)]
			break
		}
	}
	// mercy / merciful both land on "merci" once the suffix is gone.
	if strings.HasSuffix(w, "y") {
		w = w[:len(w)-1] + "i"
	}
	return w
}

func tokens(s string) []string {
	var out []string
	for _, w := range WordRe.FindAllString(strings.ToLower(s), -1) {
		if len(w) > 2 && !stopWords[w] {
			out = append(out, Stem(w))
		}
	}
	return out
}

// Related reports whether a sense stem and a gloss stem name the same thing.
// Prefix tolerance covers what the stemmer leaves behind ("provide" reaching
// "provision"). Dropping it and relying on the stemmer alone was tried and
// measured: it cost twelve of the fifteen right senses in the calibration set.
//
// It has a known cost. Any short word that is the prefix of a longer unrelated
// one matches it, so "hear" reads as related to "heart". The threshold is
// calibrated with that noise present rather than around it.
func Related(sense, gloss string) bool {
	if sense == gloss {
		return true
	}
	if len(sense) >= 4 && strings.HasPrefix(gloss, sense) {
		return true
	}
	return len(gloss) >= 4 && strings.HasPrefix(sense, gloss)
}

type SlotResult struct {
	Name     string
	Agreed   int
	Total    int
	Examples []string // glosses that did not agree, for the evidence report
}

func (s SlotResult) Recall() float64 {
	if s.Total == 0 {
		return 0
	}
	return float64(s.Agreed) / float64(s.Total)
}

// Support is one gloss that agreed with the sense, named by the word that
// carries it. It is the provenance a shipped sense has to be able to show.
type Support struct {
	Word  string `json:"word"`
	Gloss string `json:"gloss"`
	Slot  string `json:"slot"`
}

type Result struct {
	Root      string
	Sense     string
	Slots     []SlotResult
	SlotsHit  int     // slots where at least one gloss agreed
	Recall    float64 // mean per-slot agreement; the cross-form demand
	Precision float64 // share of the sense's own content words the root attests
	Score     float64 // harmonic mean of the two
	Unmatched []string
	Support   []Support // the glosses that agreed, one per agreeing gloss
}

// Verified is the ship gate. Both halves are load-bearing: the score says the
// sense predicts the glosses, the slot count says it did so in more than one
// morphological shape, which is what makes this a prediction rather than a
// coincidence.
func (r Result) Verified(threshold float64) bool {
	return r.SlotsHit >= 2 && r.Score >= threshold
}

func (r Result) Verdict(threshold float64) string {
	switch {
	case len(r.Slots) < 2:
		return "cannot verify"
	case r.Verified(threshold):
		return "verified"
	default:
		return "not borne out"
	}
}

// Check scores one candidate sense against one root.
func Check(root *Root, sense string) Result {
	res := Result{Root: root.Letters, Sense: sense}
	senseStems := tokens(sense)
	if len(senseStems) == 0 || root == nil {
		return res
	}
	used := map[string]bool{}

	for _, slot := range root.Slots {
		strip := map[string]bool{}
		for _, m := range Markers[slot.Name] {
			strip[Stem(m)] = true
		}
		sr := SlotResult{Name: slot.Name}
		for _, gloss := range slot.Glosses {
			var residue []string
			for _, t := range tokens(gloss) {
				if !strip[t] {
					residue = append(residue, t)
				}
			}
			if len(residue) == 0 {
				continue // the wazn explains the whole gloss; the root is not tested here
			}
			sr.Total++
			agreed := false
			for _, a := range senseStems {
				for _, b := range residue {
					if Related(a, b) {
						agreed, used[a] = true, true
					}
				}
			}
			if agreed {
				sr.Agreed++
				res.Support = append(res.Support, Support{Word: slot.Words[gloss], Gloss: gloss, Slot: slot.Name})
			} else if len(sr.Examples) < 4 {
				sr.Examples = append(sr.Examples, gloss)
			}
		}
		if sr.Total > 0 {
			res.Slots = append(res.Slots, sr)
		}
	}

	if len(res.Slots) == 0 {
		return res
	}
	var sum float64
	for _, s := range res.Slots {
		sum += s.Recall()
		if s.Agreed > 0 {
			res.SlotsHit++
		}
	}
	res.Recall = sum / float64(len(res.Slots))

	distinct := map[string]bool{}
	for _, t := range senseStems {
		distinct[t] = true
	}
	for t := range distinct {
		if !used[t] {
			res.Unmatched = append(res.Unmatched, t)
		}
	}
	sort.Strings(res.Unmatched)
	res.Precision = float64(len(distinct)-len(res.Unmatched)) / float64(len(distinct))

	if res.Recall+res.Precision > 0 {
		res.Score = 2 * res.Recall * res.Precision / (res.Recall + res.Precision)
	}
	return res
}
