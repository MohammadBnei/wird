package main

import (
	"fmt"
	"io"
	"sort"

	"github.com/MohammadBnei/wird/server/internal/rootsense"
)

// Specificity is the control the calibration set cannot give. Every authored
// sense was written after reading its own root's glosses, so of course it
// matches them; the question that is still open is whether it matches ANY
// root's glosses, which would mean the check is passing English shaped like a
// gloss rather than a sense that belongs to this root.
//
// With no file it runs the senses known to be right instead, which is where the
// bar the authored senses are held to comes from.
//
// So each sense is scored against all 1,642 roots. A sense that verifies its
// own root and almost none of the others carries root-specific information. A
// sense that verifies dozens is a phrase general enough to fit anything, and it
// is listed here by name so it can be withdrawn.
func Specificity(w io.Writer, roots map[string]*rootsense.Root, cands []Candidate, threshold float64) {
	letters := make([]string, 0, len(roots))
	for k := range roots {
		letters = append(letters, k)
	}
	sort.Strings(letters)

	if len(cands) == 0 {
		for _, c := range rootsense.Calibration {
			if c.Right {
				cands = append(cands, Candidate{Root: c.Root, En: c.Sense})
			}
		}
	}

	type row struct {
		cand   Candidate
		others int
	}
	var rows []row
	ownVerified, pairs, hits := 0, 0, 0
	for _, c := range cands {
		root, ok := roots[c.Root]
		if !ok {
			continue
		}
		if !rootsense.Check(root, c.En).Verified(threshold) {
			continue // not shipped, so its specificity does not matter
		}
		ownVerified++
		others := 0
		for _, l := range letters {
			if l == c.Root {
				continue
			}
			pairs++
			if rootsense.Check(roots[l], c.En).Verified(threshold) {
				others++
				hits++
			}
		}
		rows = append(rows, row{c, others})
	}

	sort.Slice(rows, func(i, j int) bool { return rows[i].others > rows[j].others })
	fmt.Fprintf(w, "shipped senses %d\n", ownVerified)
	fmt.Fprintf(w, "own root verified %d/%d\n", ownVerified, ownVerified)
	fmt.Fprintf(w, "other roots verified %d of %d sense-root pairs (%.2f%%)\n\n", hits, pairs,
		100*float64(hits)/float64(pairs))

	buckets := map[int]int{}
	for _, r := range rows {
		switch {
		case r.others == 0:
			buckets[0]++
		case r.others <= 2:
			buckets[2]++
		case r.others <= 5:
			buckets[5]++
		case r.others <= 10:
			buckets[10]++
		case r.others <= 25:
			buckets[25]++
		default:
			buckets[99]++
		}
	}
	fmt.Fprintln(w, "other roots each shipped sense also verifies")
	for _, b := range []struct {
		k     int
		label string
	}{{0, "0"}, {2, "1-2"}, {5, "3-5"}, {10, "6-10"}, {25, "11-25"}, {99, "26+"}} {
		fmt.Fprintf(w, "%8s  %4d\n", b.label, buckets[b.k])
	}

	fmt.Fprintln(w, "\nthe least specific senses shipped")
	for i, r := range rows {
		if i >= 25 || r.others <= 10 {
			break
		}
		fmt.Fprintf(w, "%5d  %s  %q\n", r.others, r.cand.Root, r.cand.En)
	}
}
