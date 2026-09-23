package main

import (
	"bufio"
	"fmt"
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
func Cost(w io.Writer, roots map[string]*Root, tsv string, bar Bar) error {
	f, err := os.Open(tsv)
	if err != nil {
		return err
	}
	defer f.Close()

	type cand struct {
		root, sense string
		res         Result
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
		cands = append(cands, cand{col[0], col[1], Check(r, col[1])})
	}
	if err := sc.Err(); err != nil {
		return err
	}

	old := Bar{Score: bar.Score}
	var passedOld, passedNew []cand
	byScore, byCover, byDisp := 0, 0, 0
	for _, c := range cands {
		if !c.res.Verified(old) {
			byScore++
			continue
		}
		passedOld = append(passedOld, c)
		switch {
		case c.res.Coverage < bar.Coverage:
			byCover++
		case c.res.Dispersion < bar.Dispersion:
			byDisp++
		default:
			passedNew = append(passedNew, c)
		}
	}

	// The last bar the shipped set was held to, recomputed rather than quoted: a
	// sense may not fit more roots that are not its own than a sense known to be
	// right does. It is the only part of the ship gate that looks outside the
	// root being checked, and leaving it out of this report would overstate what
	// survives.
	letters := make([]string, 0, len(roots))
	for l := range roots {
		letters = append(letters, l)
	}
	sort.Strings(letters)
	fits := func(c cand) int {
		n := 0
		for _, l := range letters {
			if l != c.root && Check(roots[l], c.sense).Verified(bar) {
				n++
			}
		}
		return n
	}
	widest := 0
	for _, k := range calibration {
		if !k.Right {
			continue
		}
		if n := fits(cand{k.Root, k.Sense, Check(roots[k.Root], k.Sense)}); n > widest {
			widest = n
		}
	}
	var shipped []cand
	byFit := 0
	for _, c := range passedNew {
		if fits(c) > widest {
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
	fmt.Fprintf(w, "the new bar keeps      %d\n", len(passedNew))
	fmt.Fprintf(w, "specificity removes   %d  (fits more roots that are not its own than any known-right sense, %d)\n", byFit, widest)
	fmt.Fprintf(w, "shippable             %d\n\n", len(shipped))

	fmt.Fprintf(w, "glossed word occurrences in the corpus        %d\n", corpus)
	fmt.Fprintf(w, "occurrences under a root the old bar kept     %d  (%.1f%%)\n", occ(passedOld), 100*float64(occ(passedOld))/float64(corpus))
	fmt.Fprintf(w, "occurrences under a root the new bar keeps    %d  (%.1f%%)\n", occ(passedNew), 100*float64(occ(passedNew))/float64(corpus))
	fmt.Fprintf(w, "occurrences under a root that is shippable    %d  (%.1f%%)\n", occ(shipped), 100*float64(occ(shipped))/float64(corpus))

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
		fmt.Fprintf(tw, "%s\t%.3f\t%d\t%s\t%s\n", c.root, c.res.Coverage, c.res.Tested, c.sense, biggestMiss(roots[c.root], c.sense))
	}
	tw.Flush()
	return nil
}

// biggestMiss names the gloss carrying the most occurrences that the sense does
// not explain: the branch of the root a reader would meet and the sense would
// not cover.
func biggestMiss(root *Root, sense string) string {
	res := Check(root, sense)
	if res.Tested == 0 {
		return ""
	}
	stems := tokens(sense)
	best, bestN := "", 0
	for _, slot := range root.Slots {
		for _, g := range slot.Glosses {
			if g.N <= bestN {
				continue
			}
			gs := tokens(g.Text)
			if len(gs) == 0 {
				continue
			}
			for _, a := range stems {
				for _, b := range gs {
					if related(a, b) {
						goto next
					}
				}
			}
			best, bestN = g.Text, g.N
		next:
		}
	}
	return fmt.Sprintf("%q x%d", best, bestN)
}
