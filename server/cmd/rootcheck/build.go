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

// Build runs every authored sense through the check and writes out only the
// ones the corpus bears out, each carrying the glosses that bore it out.
//
// Nothing here edits a sense to make it pass. A sense either predicts the
// root's own glosses across its morphological shapes or it ships nothing, and
// the report says how many fell each way.

// Candidate is one line of the authored file: a root, a plain English sense,
// and its French, which is a translation of the English and never written
// independently — there is no French gloss in the corpus to check it against.
type Candidate struct {
	Root, En, Fr string
}

// Sense is one shipped row. The support list is the provenance: the words whose
// glosses the sense predicted, which is the only thing that licenses shipping it.
type Sense struct {
	Root     string              `json:"root"`
	SenseEn  string              `json:"sense_en"`
	SenseFr  string              `json:"sense_fr,omitempty"`
	Score    float64             `json:"score"`
	SlotsHit int                 `json:"slots_hit"`
	Slots    int                 `json:"slots"`
	Others   int                 `json:"also_verifies"`
	Support  []rootsense.Support `json:"support"`
}

type Bundle struct {
	Attribution string  `json:"attribution"`
	Method      string  `json:"method"`
	Threshold   float64 `json:"threshold"`
	SpecificBar int     `json:"specificity_bar"`
	Senses      []Sense `json:"senses"`
}

// specificityBar is the most other roots any sense known to be right also
// verifies. A candidate above it is not wrong so much as unspecific: English
// general enough to fit roots it has nothing to do with. The number is measured
// from the calibration set every run, never written down here, so it moves if
// the evidence moves.
func specificityBar(roots map[string]*rootsense.Root, letters []string, threshold float64) int {
	bar := 0
	for _, c := range rootsense.Calibration {
		if !c.Right {
			continue
		}
		n := 0
		for _, l := range letters {
			if l != c.Root && rootsense.Check(roots[l], c.Sense).Verified(threshold) {
				n++
			}
		}
		if n > bar {
			bar = n
		}
	}
	return bar
}

func otherRootsVerified(roots map[string]*rootsense.Root, letters []string, own, sense string, threshold float64) int {
	n := 0
	for _, l := range letters {
		if l != own && rootsense.Check(roots[l], sense).Verified(threshold) {
			n++
		}
	}
	return n
}

const attribution = "Wird's own wording. Each sense was written from the root's own words in " +
	"the bundled corpus and kept only where it predicted those words' English glosses across " +
	"more than one morphological shape. It is not quoted from, attributed to, or derived from " +
	"any lexicon or scholar, and it is a claim about the word, never about a verse."

const method = "rootcheck: a proposed sense is matched against every distinct gloss of the root, " +
	"bucketed by morphological shape, after the shape's own English has been stripped out. " +
	"recall is the mean per-shape agreement, precision the share of the sense's content words the " +
	"root attests, score their harmonic mean. The threshold is the midpoint of the gap between " +
	"known-right and known-wrong senses in the calibration set, recomputed at every run."

// The provenance kept per sense: at most a few glosses from each morphological
// shape, at most a dozen in all. Spreading it across shapes is the point — the
// argument for a sense is that it held in more than one shape, so the evidence
// shown has to be the evidence that made that argument.
const (
	supportPerSlot = 3
	supportCap     = 12
)

func trimSupport(all []rootsense.Support) []rootsense.Support {
	perSlot := map[string]int{}
	out := make([]rootsense.Support, 0, supportCap)
	for _, s := range all {
		if perSlot[s.Slot] >= supportPerSlot || len(out) >= supportCap {
			continue
		}
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
	for line := 1; sc.Scan(); line++ {
		text := strings.TrimRight(sc.Text(), "\r")
		if text == "" || strings.HasPrefix(text, "#") {
			continue
		}
		parts := strings.Split(text, "\t")
		if len(parts) < 2 || strings.TrimSpace(parts[0]) == "" || strings.TrimSpace(parts[1]) == "" {
			return nil, fmt.Errorf("%s:%d: want root<tab>english[<tab>french]", path, line)
		}
		c := Candidate{Root: strings.TrimSpace(parts[0]), En: strings.TrimSpace(parts[1])}
		if len(parts) > 2 {
			c.Fr = strings.TrimSpace(parts[2])
		}
		out = append(out, c)
	}
	return out, sc.Err()
}

func Build(w io.Writer, roots map[string]*rootsense.Root, cands []Candidate, threshold float64, out string) error {
	letters := make([]string, 0, len(roots))
	for k := range roots {
		letters = append(letters, k)
	}
	sort.Strings(letters)
	bar := specificityBar(roots, letters, threshold)

	bundle := Bundle{Attribution: attribution, Method: method, Threshold: threshold, SpecificBar: bar}
	var refusedScore, refusedSlots, refusedVague, unknown int
	var scores []float64
	worst := make([]Sense, 0, 8)

	for _, c := range cands {
		root, ok := roots[c.Root]
		if !ok {
			unknown++
			fmt.Fprintf(w, "  no such root in the corpus: %s\n", c.Root)
			continue
		}
		res := rootsense.Check(root, c.En)
		if !res.Verified(threshold) {
			if res.SlotsHit < 2 {
				refusedSlots++
			} else {
				refusedScore++
			}
			continue
		}
		others := otherRootsVerified(roots, letters, c.Root, c.En, threshold)
		if others > bar {
			refusedVague++
			continue
		}
		support := trimSupport(res.Support)
		bundle.Senses = append(bundle.Senses, Sense{
			Root: c.Root, SenseEn: c.En, SenseFr: c.Fr,
			Score: res.Score, SlotsHit: res.SlotsHit, Slots: len(res.Slots),
			Others: others, Support: support,
		})
		scores = append(scores, res.Score)
	}

	sort.Slice(bundle.Senses, func(i, j int) bool { return bundle.Senses[i].Root < bundle.Senses[j].Root })
	sort.Float64s(scores)
	for _, s := range bundle.Senses {
		if len(worst) < 8 {
			worst = append(worst, s)
		}
	}
	sort.Slice(worst, func(i, j int) bool { return worst[i].Score < worst[j].Score })

	fmt.Fprintf(w, "proposed  %d\n", len(cands))
	fmt.Fprintf(w, "shipped   %d\n", len(bundle.Senses))
	fmt.Fprintf(w, "refused   %d below the threshold, %d agreed in fewer than two shapes, "+
		"%d verified more than %d other roots and so name nothing particular",
		refusedScore, refusedSlots, refusedVague, bar)
	if unknown > 0 {
		fmt.Fprintf(w, ", %d name no root in the corpus", unknown)
	}
	fmt.Fprintln(w)
	if len(scores) > 0 {
		fmt.Fprintf(w, "score     min %.3f  median %.3f  max %.3f  (threshold %.3f)\n",
			scores[0], scores[len(scores)/2], scores[len(scores)-1], threshold)
		histogram(w, scores, threshold)
	}

	if out == "" {
		return nil
	}
	body, err := json.MarshalIndent(bundle, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(out, append(body, '\n'), 0o644)
}

func histogram(w io.Writer, scores []float64, threshold float64) {
	const bands = 10
	counts := make([]int, bands)
	for _, s := range scores {
		b := int(s * bands)
		if b >= bands {
			b = bands - 1
		}
		counts[b]++
	}
	fmt.Fprintln(w, "\nshipped senses by score")
	for b, n := range counts {
		lo, hi := float64(b)/bands, float64(b+1)/bands
		mark := " "
		if threshold >= lo && threshold < hi {
			mark = "<- threshold"
		}
		fmt.Fprintf(w, "%.1f-%.1f  %4d  %s %s\n", lo, hi, n, strings.Repeat("#", n*40/len(scores)+1), mark)
	}
}
