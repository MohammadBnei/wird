package main

import (
	"bufio"
	"fmt"
	"github.com/MohammadBnei/wird/server/internal/rootsense"
	"io"
	"os"
	"sort"
	"strings"
	"text/tabwriter"
)

// Cost reads a TSV of root and proposed sense and reports what each part of
// the bar keeps and what it takes away. A bar that rejects a wrong sense also
// rejects right senses phrased in English the corpus does not use, and the
// number of senses left is the only honest way to say whether the method still
// reaches enough of the Qur'an to be worth shipping.
func Cost(w io.Writer, roots map[string]*rootsense.Root, tsv string, bar rootsense.Bar) error {
	f, err := os.Open(tsv)
	if err != nil {
		return err
	}
	defer f.Close()

	type cand struct {
		root, sense string
		res         rootsense.Result
	}
	var cands []cand
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		line := sc.Text()
		if strings.HasPrefix(line, "#") || strings.TrimSpace(line) == "" {
			continue
		}
		col := strings.Split(line, "\t")
		if len(col) < 2 {
			continue
		}
		r, ok := roots[col[0]]
		if !ok {
			continue
		}
		cands = append(cands, cand{col[0], col[1], rootsense.Check(r, col[1])})
	}
	if err := sc.Err(); err != nil {
		return err
	}

	twice := map[string][]string{}
	for _, c := range cands {
		if k := strings.Join(rootsense.Content(c.sense), " "); k != "" {
			twice[k] = append(twice[k], c.root)
		}
	}

	var passedOld, passedNew []cand
	var misordered []cand
	byScore, byCover, byDisp, byBranch, bySame := 0, 0, 0, 0, 0
	for _, c := range cands {
		if !c.res.BorneOut(bar) {
			byScore++
			continue
		}
		passedOld = append(passedOld, c)
		switch {
		case c.res.Coverage <= bar.Coverage:
			byCover++
		case c.res.Dispersion < bar.Dispersion:
			byDisp++
		case c.res.Branch > bar.Branch:
			byBranch++
		case !c.res.Leads:
			misordered = append(misordered, c)
		case len(twice[strings.Join(rootsense.Content(c.sense), " ")]) > 1:
			bySame++
		default:
			passedNew = append(passedNew, c)
		}
	}

	// The last bar the shipped set was held to, recomputed rather than quoted: a
	// sense may not fit more roots that are not its own than a sense known to be
	// right does. It is the only part of the ship gate that looks outside the
	// root being checked, and leaving it out of this report would overstate what
	// survives.
	letters := sortedLetters(roots)
	widest := specificityBar(roots, letters, bar)
	var shipped []cand
	byFit := 0
	for _, c := range passedNew {
		if otherRootsVerified(roots, letters, c.root, c.sense, bar) > widest {
			byFit++
			continue
		}
		shipped = append(shipped, c)
	}

	occ := func(cs []cand) int {
		n, seen := 0, map[string]bool{}
		for _, c := range cs {
			if !seen[c.root] {
				seen[c.root] = true
				n += roots[c.root].Words
			}
		}
		return n
	}
	corpus := 0
	for _, r := range roots {
		corpus += r.Words
	}

	fmt.Fprintf(w, "candidates read        %d\n", len(cands))
	fmt.Fprintf(w, "the old bar kept       %d  (score only)\n", len(passedOld))
	fmt.Fprintf(w, "coverage removes       %d  (the sense explains a minority of its root's occurrences)\n", byCover)
	fmt.Fprintf(w, "dispersion removes     %d  (a word the root never shows and the corpus reserves for others)\n", byDisp)
	fmt.Fprintf(w, "branch removes         %d  (one branch of the root is over %.1f%% of it and the sense is silent)\n", byBranch, 100*bar.Branch)
	fmt.Fprintf(w, "order removes          %d  (a later clause explains more than the one a reader reads first)\n", len(misordered))
	fmt.Fprintf(w, "same prose removes     %d  (two roots handed the same words)\n", bySame)
	fmt.Fprintf(w, "the new bar keeps      %d\n", len(passedNew))
	fmt.Fprintf(w, "specificity removes   %d  (fits more roots that are not its own than any known-right sense, %d)\n", byFit, widest)
	fmt.Fprintf(w, "shippable             %d\n\n", len(shipped))

	fmt.Fprintf(w, "glossed word occurrences in the corpus        %d\n", corpus)
	fmt.Fprintf(w, "occurrences under a root the old bar kept     %d  (%.1f%%)\n", occ(passedOld), 100*float64(occ(passedOld))/float64(corpus))
	fmt.Fprintf(w, "occurrences under a root the new bar keeps    %d  (%.1f%%)\n", occ(passedNew), 100*float64(occ(passedNew))/float64(corpus))
	fmt.Fprintf(w, "occurrences under a root that is shippable    %d  (%.1f%%)\n", occ(shipped), 100*float64(occ(shipped))/float64(corpus))

	// The order term is the only one whose cost is recoverable without new
	// evidence. Every sense it takes has already passed every other term, so
	// what it is missing is not a claim but the order of the claims it makes,
	// and whoever wrote it can put the branch a reader meets first. Reporting
	// that cost next to the others would read as though the method covers less
	// than it does.
	fmt.Fprintf(w, "\nof those removed, the %d the order term takes fail nothing else; they need reordering,\n", len(misordered))
	fmt.Fprintf(w, "not evidence, and would bring the reach to %d occurrences (%.1f%%)\n",
		occ(shipped)+occ(misordered), 100*float64(occ(shipped)+occ(misordered))/float64(corpus))
	tw2 := tabwriter.NewWriter(w, 0, 0, 2, ' ', 0)
	fmt.Fprintln(tw2, "\nroot\tleads with\tx\tbehind\tx")
	sort.Slice(misordered, func(i, j int) bool { return roots[misordered[i].root].Words > roots[misordered[j].root].Words })
	for i, c := range misordered {
		if i >= 25 {
			break
		}
		lead, best, text := c.res.Clauses[0], 0, ""
		for _, cl := range c.res.Clauses {
			if cl.Covered > best {
				best, text = cl.Covered, cl.Text
			}
		}
		fmt.Fprintf(tw2, "%s\t%s\t%d\t%s\t%d\n", c.root, lead.Text, lead.Covered, text, best)
	}
	tw2.Flush()

	sort.Slice(passedOld, func(i, j int) bool {
		return passedOld[i].res.Coverage < passedOld[j].res.Coverage
	})
	fmt.Fprintln(w, "\nthe senses the coverage term takes, worst first: the majority branch the sense leaves unexplained")
	tw := tabwriter.NewWriter(w, 0, 0, 2, ' ', 0)
	fmt.Fprintln(tw, "root\tcover\tocc\tsense\tcommonest gloss it misses")
	shown := 0
	for _, c := range passedOld {
		if c.res.Coverage >= bar.Coverage || shown >= 60 {
			break
		}
		shown++
		fmt.Fprintf(tw, "%s\t%.3f\t%d\t%s\t%s\n", c.root, c.res.Coverage, c.res.Tested, c.sense, rootsense.BiggestMiss(roots[c.root], c.sense))
	}
	tw.Flush()
	return nil
}
