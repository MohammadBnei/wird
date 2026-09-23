package main

import (
	"fmt"
	"github.com/MohammadBnei/wird/server/internal/rootsense"
	"io"
	"sort"
	"text/tabwriter"
)

// Scan is the corpus-scale control. Thirty-three hand-written cases can be
// fitted by accident; this cannot. Every sense known to be right is scored
// against all 1,642 roots, and the check is only worth having if each one
// verifies its own root and almost none of the others.
//
// A sense that verifies many roots is not a sense, it is a phrase general
// enough to fit anything, and the count here is what exposes that.
func Scan(w io.Writer, roots map[string]*rootsense.Root, bar rootsense.Bar) {
	letters := make([]string, 0, len(roots))
	for k := range roots {
		letters = append(letters, k)
	}
	sort.Strings(letters)

	tw := tabwriter.NewWriter(w, 0, 0, 2, ' ', 0)
	fmt.Fprintln(tw, "sense\town root\tscore\tother roots verified\tof")
	totalOther, totalOwn, cases := 0, 0, 0
	for _, c := range rootsense.Calibration {
		if !c.Right {
			continue
		}
		cases++
		var own float64
		others, eligible := 0, 0
		var worst []string
		for _, l := range letters {
			res := rootsense.Check(roots[l], c.Sense)
			if len(res.Slots) >= 2 {
				eligible++
			}
			if l == c.Root {
				own = res.Score
				continue
			}
			if res.Verified(bar) {
				others++
				if len(worst) < 3 {
					worst = append(worst, l)
				}
			}
		}
		if rootsense.Check(roots[c.Root], c.Sense).Verified(bar) {
			totalOwn++
		}
		totalOther += others
		fmt.Fprintf(tw, "%s\t%s\t%.3f\t%d %v\t%d\n", c.Sense, c.Root, own, others, worst, eligible)
	}
	tw.Flush()
	fmt.Fprintf(w, "\nown root verified %d/%d\n", totalOwn, cases)
	fmt.Fprintf(w, "other roots verified %d in %d sense-root pairs (%.2f%%)\n",
		totalOther, cases*(len(roots)-1), 100*float64(totalOther)/float64(cases*(len(roots)-1)))
}
