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

// stem strips the English suffixes that separate a gloss from a dictionary
// sense ("forgiving" / "forgive", "patience" / "patient", "mercy" /
// "merciful"). It is cruder than Porter on purpose: the vocabulary here is a
// few thousand short gloss words, and over-stripping costs less than a
// stemmer that splits "know" from "knowledge".
var suffixes = []string{
	"ledge", "ness", "ment", "tion", "sion", "ence", "ance", "ings", "ing",
	"edly", "ful", "ous", "ity", "ive", "ent", "ant", "ers", "ors", "est",
	"ed", "er", "or", "ly",
}

// plural strips the English plural before anything else, because stripping it
// as though it were any other suffix splits a word from itself: "faces" lost
// two letters and became "fac" while "face" kept all four, so a sense saying
// "a face" read as disagreeing with a gloss saying "their faces". The rules are
// the ordinary English ones — "es" only after a sibilant, "ies" leaving the i
// that "mercy" also lands on.
func plural(w string) string {
	switch {
	case strings.HasSuffix(w, "ies") && len(w) >= 5:
		return w[:len(w)-3] + "i"
	case strings.HasSuffix(w, "sses"), strings.HasSuffix(w, "xes"),
		strings.HasSuffix(w, "zes"), strings.HasSuffix(w, "ches"), strings.HasSuffix(w, "shes"):
		return w[:len(w)-2]
	case strings.HasSuffix(w, "s") && !strings.HasSuffix(w, "ss") && len(w) >= 4:
		return w[:len(w)-1]
	}
	return w
}

// irregular maps the English strong verbs to their base form. It is a fact
// about English, not about this corpus: "he said" and "to say" are the same
// word, and a matcher that reads them as different is measuring its own
// stemmer rather than what the glosses say. The list is the ordinary irregular
// paradigm, closed and written without looking at which senses it would help.
//
// "left" is deliberately absent: it is the past of "leave" and also a side, and
// mapping it would let a sense about leaving agree with "the left hand".
var irregular = map[string]string{
	"said": "say", "made": "make", "gave": "give", "given": "give",
	"took": "take", "taken": "take", "came": "come", "went": "go", "gone": "go",
	"saw": "see", "seen": "see", "knew": "know", "known": "know",
	"told": "tell", "brought": "bring", "sent": "send", "held": "hold",
	"heard": "hear", "kept": "keep", "felt": "feel", "found": "find",
	"forgave": "forgive", "forgiven": "forgive", "forgot": "forget",
	"forgotten": "forget", "grew": "grow", "grown": "grow", "led": "lead",
	"lost": "lose", "meant": "mean", "met": "meet", "paid": "pay",
	"rose": "rise", "risen": "rise", "ran": "run", "sat": "sit",
	"sold": "sell", "shown": "show", "spoke": "speak", "spoken": "speak",
	"stood": "stand", "struck": "strike", "swore": "swear", "sworn": "swear",
	"taught": "teach", "thought": "think", "threw": "throw", "thrown": "throw",
	"understood": "understand", "wrote": "write", "written": "write",
	"drew": "draw", "drawn": "draw", "drove": "drive", "driven": "drive",
	"fell": "fall", "fallen": "fall", "fed": "feed", "fought": "fight",
	"flew": "fly", "flown": "fly", "hid": "hide", "hidden": "hide",
	"rode": "ride", "ridden": "ride", "sank": "sink", "sunk": "sink",
	"slept": "sleep", "spent": "spend", "stole": "steal", "stolen": "steal",
	"tore": "tear", "torn": "tear", "won": "win", "bore": "bear",
	"born": "bear", "borne": "bear", "became": "become", "begun": "begin",
	"began": "begin", "bound": "bind", "blew": "blow", "blown": "blow",
	"broke": "break", "broken": "break", "built": "build", "bought": "buy",
	"caught": "catch", "chose": "choose", "chosen": "choose", "dealt": "deal",
	"done": "do", "drank": "drink", "drunk": "drink", "ate": "eat", "eaten": "eat",
	"lay": "lie", "lain": "lie", "sought": "seek", "shook": "shake",
	"shaken": "shake", "stricken": "strike", "swept": "sweep", "wept": "weep",
	"woke": "wake", "woven": "weave", "wound": "wind",
}

func stem(w string) string {
	if base, ok := irregular[w]; ok {
		w = base
	}
	w = plural(w)
	// Stripping once is not enough, because the result can itself carry a
	// suffix: "powerful" loses "ful" and stops at "power", while "power" loses
	// "er" and becomes "pow". A stemmer that lands two spellings of one word in
	// two places is measuring itself, so the rules run until nothing changes.
	for again := true; again; {
		again = false
		for _, suf := range suffixes {
			// "ly" needs a longer remainder than the rest: at three letters it
			// eats the noun it is not a suffix of, turning "belly" into "bel"
			// while "bellies" becomes "belli", and a root loses its own word.
			min := 3
			if suf == "ly" {
				min = 4
			}
			if strings.HasSuffix(w, suf) && len(w)-len(suf) >= min {
				w, again = w[:len(w)-len(suf)], true
				break
			}
		}
	}
	// mercy / merciful both land on "merci" once the suffix is gone.
	if strings.HasSuffix(w, "y") {
		w = w[:len(w)-1] + "i"
	}
	// The silent e goes the same way, and for the same reason: "saved" loses
	// "ed" and becomes "sav", so "save" has to lose its e to meet it.
	if strings.HasSuffix(w, "e") && len(w) > 3 {
		w = w[:len(w)-1]
	}
	return w
}

func tokens(s string) []string {
	var out []string
	for _, w := range WordRe.FindAllString(strings.ToLower(s), -1) {
		if len(w) > 2 && !stopWords[w] {
			out = append(out, stem(w))
		}
	}
	return out
}

// related reports whether a sense stem and a gloss stem name the same thing.
// Prefix tolerance covers what the stemmer leaves behind ("provide" reaching
// "provision"). Dropping it and relying on the stemmer alone was tried and
// measured: it cost twelve of the fifteen right senses in the Calibration set.
//
// It has a known cost. Any short word that is the prefix of a longer unrelated
// one matches it, so "hear" reads as related to "heart". The threshold is
// calibrated with that noise present rather than around it.
func related(sense, gloss string) bool {
	if sense == gloss {
		return true
	}
	if len(sense) >= 4 && strings.HasPrefix(gloss, sense) {
		return true
	}
	return len(gloss) >= 4 && strings.HasPrefix(sense, gloss)
}

// clauseRe splits a sense into the claims it makes. A sense is written as a
// list of phrasings separated by semicolons or commas, and each one is a
// separate claim about the root: "to pray" and "to pray five times" are not one
// claim made twice, they are a true claim and a further one.
var clauseRe = regexp.MustCompile(`[;,]`)

// Clause is one claim of a sense and the words in it the root does not attest.
type Clause struct {
	Text       string
	Ungrounded []Ungrounded
}

// Ungrounded is a sense word this root's glosses never show, with the number of
// roots the corpus does gloss with it. A high count is generic English
// ("bring", twenty-odd roots); a low count is a word the corpus reserves for
// somebody else ("unseen", one root), and putting it in this root's sense
// borrows that root's meaning without any evidence from this one.
//
// Rider says the word sits in a clause that ALSO contains a word the root does
// attest. That is the shape of a false elaboration and the shape a wholly
// unattested clause does not have: "to judge; to decide; to rule" offers "rule"
// INSTEAD of the attested words and is already paid for in precision, while
// "to pray; to pray five times" bolts "five times" ONTO the attested "pray",
// where nothing in the score notices it. Only riders are held to the floor.
type Ungrounded struct {
	Stem  string
	Roots int
	Rider bool
}

// NoUngrounded is the Dispersion of a sense whose every word the root attests.
// It sits above any real count so that the floor can be calibrated on one axis.
const NoUngrounded = 1 << 20

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

type Result struct {
	Root      string
	Sense     string
	Slots     []SlotResult
	SlotsHit  int     // slots where at least one gloss agreed
	Recall    float64 // mean per-slot agreement; the cross-form demand
	Precision float64 // share of the sense's own content words the root attests
	Score     float64 // harmonic mean of the two
	Unmatched []string

	// Coverage is the share of the root's glossed word OCCURRENCES the sense
	// explains. Recall counts distinct glosses, so a sense can describe a real
	// but minority branch of a root and score well: غير means "to change" in
	// two of its words and "other than / without" in a hundred and twenty.
	// Coverage is what tells those apart, because a reader meets occurrences.
	Coverage float64
	Tested   int // occurrences the coverage is out of

	// Support is the provenance: the root's own words whose glosses the sense
	// predicted. A sense ships with these attached, because the argument for
	// it is the words, not the number.
	Support []Support

	Clauses    []Clause
	Ungrounded []Ungrounded // every sense word the root does not attest
	Dispersion int          // fewest roots any ungrounded word is spread over
}

// Bar is the shipping rule. Every part is a separate failure it was added to
// catch, and none of them substitutes for another.
type Bar struct {
	Score      float64 // does the sense predict the glosses at all
	Coverage   float64 // does it explain the occurrences a reader actually meets
	Dispersion int     // is every word of it either attested here or generic English
}

// Verified is the ship gate.
func (r Result) Verified(bar Bar) bool {
	return r.SlotsHit >= 2 &&
		r.Score >= bar.Score &&
		r.Coverage > bar.Coverage &&
		r.Dispersion >= bar.Dispersion
}

func (r Result) Verdict(bar Bar) string {
	switch {
	case len(r.Slots) < 2:
		return "cannot verify"
	case r.Verified(bar):
		return "verified"
	case r.Score < bar.Score:
		return "not borne out"
	case r.Coverage <= bar.Coverage:
		return "minority branch"
	default:
		return "unattested clause"
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
	covered := 0

	for _, slot := range root.Slots {
		strip := map[string]bool{}
		for _, m := range Markers[slot.Name] {
			strip[stem(m)] = true
		}
		sr := SlotResult{Name: slot.Name}
		for _, gloss := range slot.Glosses {
			var residue []string
			for _, t := range tokens(gloss.Text) {
				if !strip[t] {
					residue = append(residue, t)
				}
			}
			if len(residue) == 0 {
				continue // the wazn explains the whole gloss; the root is not tested here
			}
			sr.Total++
			res.Tested += gloss.N
			agreed := false
			for _, a := range senseStems {
				for _, b := range residue {
					if related(a, b) {
						agreed, used[a] = true, true
					}
				}
			}
			if agreed {
				sr.Agreed++
				covered += gloss.N
				res.Support = append(res.Support, Support{Word: gloss.Word, Gloss: gloss.Text, Slot: slot.Name})
			} else if len(sr.Examples) < 4 {
				sr.Examples = append(sr.Examples, gloss.Text)
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
	if res.Tested > 0 {
		res.Coverage = float64(covered) / float64(res.Tested)
	}

	res.Dispersion = NoUngrounded
	for _, text := range clauseRe.Split(sense, -1) {
		c := Clause{Text: strings.TrimSpace(text)}
		if c.Text == "" {
			continue
		}
		grounded, seen := false, map[string]bool{}
		for _, t := range tokens(c.Text) {
			if seen[t] {
				continue
			}
			seen[t] = true
			if used[t] {
				grounded = true
				continue
			}
			c.Ungrounded = append(c.Ungrounded, Ungrounded{Stem: t, Roots: rootsUsing(t)})
		}
		for i := range c.Ungrounded {
			c.Ungrounded[i].Rider = grounded
			res.Ungrounded = append(res.Ungrounded, c.Ungrounded[i])
			if grounded && c.Ungrounded[i].Roots < res.Dispersion {
				res.Dispersion = c.Ungrounded[i].Roots
			}
		}
		res.Clauses = append(res.Clauses, c)
	}
	return res
}

// rootsUsing counts the roots the corpus glosses with a word. Matching goes
// through the same related() the scorer uses, so a word does not read as
// unheard-of merely because the stemmer landed a letter away from the corpus.
//
// ponytail: memoised linear scan of the stem index. A sense has a handful of
// words and the index a few thousand stems; a prefix tree would be faster and
// buy nothing measurable here.
var dispersionCache = map[string]int{}

func rootsUsing(stem string) int {
	if n, ok := dispersionCache[stem]; ok {
		return n
	}
	roots := map[string]bool{}
	for g, rs := range dispersion {
		if !related(stem, g) && !related(g, stem) {
			continue
		}
		for r := range rs {
			roots[r] = true
		}
	}
	dispersionCache[stem] = len(roots)
	return len(roots)
}
