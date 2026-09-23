package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"sort"
	"strings"

	"github.com/MohammadBnei/wird/server/internal/rootsense"
)

// Build runs every proposed sense through the whole bar and writes out only the
// ones the corpus bears out, each carrying the words that bore it out.
//
// Nothing here edits a sense to make it pass. A sense either predicts its
// root's own glosses across more than one morphological shape, explains the
// occurrences a reader actually meets, and rests on no word the corpus keeps
// for another root — or it ships nothing, and the report says which demand it
// failed.

// Candidate is one line of the proposed file: a root, a plain English sense,
// and its French, which is a translation of the English and never written
// independently — the corpus carries no French gloss to check it against.
type Candidate struct {
	Root, En, Fr string
}

// Sense is one shipped row.
type Sense struct {
	Root       string              `json:"root"`
	SenseEn    string              `json:"sense_en"`
	SenseFr    string              `json:"sense_fr"`
	Score      float64             `json:"score"`
	Coverage   float64             `json:"coverage"`
	Branch     float64             `json:"branch"`
	Dispersion int                 `json:"dispersion,omitempty"`
	SlotsHit   int                 `json:"slots_hit"`
	Slots      int                 `json:"slots"`
	Others     int                 `json:"also_verifies"`
	Support    []rootsense.Support `json:"support"`
}

// Bundle is the file the ETL reads. The attribution and the basis line travel
// with the senses because they have to reach a screen: a reader who cannot tell
// authored prose from a quoted lexicon has been told something false about
// where the words came from.
type Bundle struct {
	Attribution string  `json:"attribution"`
	Source      string  `json:"source"`
	Basis       string  `json:"basis"`
	Method      string  `json:"method"`
	Bar         barJSON `json:"bar"`
	SpecificBar int     `json:"specificity_bar"`
	Senses      []Sense `json:"senses"`
}

type barJSON struct {
	Score      float64 `json:"score"`
	Coverage   float64 `json:"coverage"`
	Dispersion int     `json:"dispersion"`
	Branch     float64 `json:"branch"`
}

const attribution = "Wird's own wording. Each sense was written from the root's own words in " +
	"the bundled corpus and kept only where it predicted those words' English glosses across " +
	"more than one morphological shape, explained most of the root's occurrences, left no branch of " +
	"the root unnamed, led with the branch a reader is likeliest to meet, and rested on no word the " +
	"corpus reserves for another root. It is not quoted from, attributed to, or " +
	"derived from any lexicon or scholar, and it is a claim about the word, never about a verse."

// source is the byline a screen puts beside the sense, and basis the line under
// it. Both are short enough to render and blunt enough that no reader mistakes
// the prose for a lexicon entry.
const (
	source = "Wird"
	basis  = "Wird's own reading of this root, written from the root's own words in this corpus " +
		"and kept only because their glosses bear it out. Not quoted from any lexicon."
)

const method = "rootcheck: a proposed sense is matched against every distinct gloss of the root, " +
	"bucketed by morphological shape, after the shape's own English has been stripped out. score " +
	"is the harmonic mean of the mean per-shape agreement and the share of the sense's own words " +
	"the root attests; coverage is the share of the root's word occurrences the sense explains; " +
	"dispersion is how many roots the corpus glosses with the least common word the sense adds to " +
	"an otherwise attested clause, counting only words that are wordings of nothing the root says; " +
	"branch is the share of the root's occurrences sitting in the single heaviest thing the sense " +
	"leaves unexplained; and the leading clause must explain at least as much as any later one. The " +
	"score, dispersion and branch floors sit where known-right and known-wrong senses part, " +
	"recomputed at every run; the coverage floor is a majority."

// The provenance kept per sense: a few words from each morphological shape, a
// dozen at most. Spreading it across shapes is the point — the argument for a
// sense is that it held in more than one shape, so the evidence shown has to be
// the evidence that made the argument.
const (
	supportPerSlot = 3
	supportCap     = 12
)

func trimSupport(all []rootsense.Support) []rootsense.Support {
	perSlot := map[string]int{}
	seen := map[string]bool{}
	out := make([]rootsense.Support, 0, supportCap)
	for _, s := range all {
		if perSlot[s.Slot] >= supportPerSlot || len(out) >= supportCap || seen[s.Word] {
			continue
		}
		seen[s.Word] = true
		perSlot[s.Slot]++
		out = append(out, s)
	}
	return out
}

func ReadCandidates(path string) ([]Candidate, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	var out []Candidate
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		line := sc.Text()
		if strings.HasPrefix(line, "#") || strings.TrimSpace(line) == "" {
			continue
		}
		col := strings.Split(line, "\t")
		if len(col) < 2 {
			return nil, fmt.Errorf("%q: want root<TAB>english<TAB>french", line)
		}
		c := Candidate{Root: strings.TrimSpace(col[0]), En: strings.TrimSpace(col[1])}
		if len(col) > 2 {
			c.Fr = strings.TrimSpace(col[2])
		}
		out = append(out, c)
	}
	return out, sc.Err()
}

func sortedLetters(roots map[string]*rootsense.Root) []string {
	letters := make([]string, 0, len(roots))
	for l := range roots {
		letters = append(letters, l)
	}
	sort.Strings(letters)
	return letters
}

// otherRootsVerified counts the roots a sense fits that are not its own. A
// sense that fits many is not a sense, it is English general enough to describe
// anything.
func otherRootsVerified(roots map[string]*rootsense.Root, letters []string, own, sense string, bar rootsense.Bar) int {
	n := 0
	for _, l := range letters {
		if l != own && rootsense.Check(roots[l], sense).Verified(bar) {
			n++
		}
	}
	return n
}

// specificityBar is the most other roots any sense known to be right also
// fits. It is measured from the calibration set every run rather than written
// down, so it moves when the evidence moves.
func specificityBar(roots map[string]*rootsense.Root, letters []string, bar rootsense.Bar) int {
	widest := 0
	for _, c := range rootsense.Calibration {
		if !c.Right {
			continue
		}
		if n := otherRootsVerified(roots, letters, c.Root, c.Sense, bar); n > widest {
			widest = n
		}
	}
	return widest
}

func Build(w io.Writer, roots map[string]*rootsense.Root, tsv, out string, bar rootsense.Bar) error {
	cands, err := ReadCandidates(tsv)
	if err != nil {
		return err
	}
	letters := sortedLetters(roots)
	specific := specificityBar(roots, letters, bar)

	bundle := Bundle{
		Attribution: attribution, Source: source, Basis: basis, Method: method,
		Bar:         barJSON{bar.Score, bar.Coverage, bar.Dispersion, bar.Branch},
		SpecificBar: specific,
	}
	// Two roots handed the same words is a signal that at least one of them is
	// wrong, and no term can see it: every term asks about one root at a time.
	// It is a refusal rather than a score, and it refuses both, because nothing
	// here says which of the two the prose belongs to.
	//
	// Only senses that clear every other term can collide. A proposal the
	// corpus does not bear out ships nothing whatever its words are, and
	// letting it take a sense that does hold down with it refuses a root over
	// prose no reader will ever be shown — which is how هلك, a root of 68
	// occurrences, was refused by وبق, a root of two that fails the score.
	// The ETL gate reads the shipped bundle and so has always been read this
	// way; this is the builder saying the same thing.
	twice := map[string][]string{}
	for _, c := range cands {
		k := strings.Join(rootsense.Content(c.En), " ")
		if k == "" || roots[c.Root] == nil {
			continue
		}
		if rootsense.Check(roots[c.Root], c.En).Verified(bar) {
			twice[k] = append(twice[k], c.Root)
		}
	}

	byScore, byCover, byDisp, byBranch, byLead, bySame, byFit, byFrench, unknown := 0, 0, 0, 0, 0, 0, 0, 0, 0
	for _, c := range cands {
		root := roots[c.Root]
		if root == nil {
			unknown++
			fmt.Fprintf(w, "no such root   %s  %q\n", c.Root, c.En)
			continue
		}
		res := rootsense.Check(root, c.En)
		switch {
		case !res.BorneOut(bar):
			byScore++
			fmt.Fprintf(w, "not borne out  %s  %.3f  %q  slots %d/%d\n",
				c.Root, res.Score, c.En, res.SlotsHit, len(res.Slots))
			continue
		case res.Coverage <= bar.Coverage:
			byCover++
			fmt.Fprintf(w, "minority       %s  %.3f  %q  misses %s\n",
				c.Root, res.Coverage, c.En, rootsense.BiggestMiss(root, c.En))
			continue
		case res.Dispersion < bar.Dispersion:
			byDisp++
			var riders []string
			for _, u := range res.Ungrounded {
				if u.Measured {
					riders = append(riders, fmt.Sprintf("%s(%d roots)", u.Stem, u.Roots))
				}
			}
			fmt.Fprintf(w, "rider          %s  %d    %q  <- %s\n",
				c.Root, res.Dispersion, c.En, strings.Join(riders, " "))
			continue
		case res.Branch > bar.Branch:
			byBranch++
			fmt.Fprintf(w, "unnamed branch %s  %.3f  %q  <- %q x%d of %d\n",
				c.Root, res.Branch, c.En, res.BranchStem, res.BranchN, res.Tested)
			continue
		case !res.Leads:
			byLead++
			lead, best, bestText := res.Clauses[0], 0, ""
			for _, cl := range res.Clauses {
				if cl.Covered > best {
					best, bestText = cl.Covered, cl.Text
				}
			}
			fmt.Fprintf(w, "wrong order    %s  %q  leads with %q x%d, behind %q x%d\n",
				c.Root, c.En, lead.Text, lead.Covered, bestText, best)
			continue
		}
		if others := twice[strings.Join(rootsense.Content(c.En), " ")]; len(others) > 1 {
			bySame++
			fmt.Fprintf(w, "same prose     %s  %q  also given to %v\n", c.Root, c.En, others)
			continue
		}
		others := otherRootsVerified(roots, letters, c.Root, c.En, bar)
		if others > specific {
			byFit++
			fmt.Fprintf(w, "unspecific     %s  fits %d others  %q\n", c.Root, others, c.En)
			continue
		}
		if c.Fr == "" {
			byFrench++
			fmt.Fprintf(w, "no french      %s  %q\n", c.Root, c.En)
			continue
		}
		d := res.Dispersion
		if d == rootsense.NoUngrounded {
			d = 0
		}
		bundle.Senses = append(bundle.Senses, Sense{
			Root: c.Root, SenseEn: c.En, SenseFr: c.Fr,
			Score: res.Score, Coverage: res.Coverage, Branch: res.Branch, Dispersion: d,
			SlotsHit: res.SlotsHit, Slots: len(res.Slots), Others: others,
			Support: trimSupport(res.Support),
		})
	}
	sort.Slice(bundle.Senses, func(i, j int) bool { return bundle.Senses[i].Root < bundle.Senses[j].Root })

	f, err := os.Create(out)
	if err != nil {
		return err
	}
	defer f.Close()
	enc := json.NewEncoder(f)
	enc.SetIndent("", "  ")
	if err := enc.Encode(bundle); err != nil {
		return err
	}

	fmt.Fprintf(w, "\ncandidates      %d\n", len(cands))
	fmt.Fprintf(w, "not borne out   %d\n", byScore)
	fmt.Fprintf(w, "minority branch %d\n", byCover)
	fmt.Fprintf(w, "riding clause   %d\n", byDisp)
	fmt.Fprintf(w, "unnamed branch  %d  (one branch of the root is more than %.1f%% of it and the sense is silent)\n", byBranch, 100*bar.Branch)
	fmt.Fprintf(w, "wrong order     %d  (a later clause explains more than the one a reader reads first)\n", byLead)
	fmt.Fprintf(w, "same prose      %d  (two roots handed the same words)\n", bySame)
	fmt.Fprintf(w, "unspecific      %d  (fits more than %d other roots)\n", byFit, specific)
	fmt.Fprintf(w, "no french       %d\n", byFrench)
	fmt.Fprintf(w, "unknown root    %d\n", unknown)
	fmt.Fprintf(w, "shipped         %d -> %s\n", len(bundle.Senses), out)
	occ, seen := 0, map[string]bool{}
	for _, s := range bundle.Senses {
		if !seen[s.Root] {
			seen[s.Root] = true
			occ += roots[s.Root].Words
		}
	}
	corpus := 0
	for _, r := range roots {
		corpus += r.Words
	}
	fmt.Fprintf(w, "reach           %d of %d glossed occurrences (%.1f%%)\n",
		occ, corpus, 100*float64(occ)/float64(corpus))
	return nil
}
