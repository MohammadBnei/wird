package main

import (
	"fmt"
	"github.com/MohammadBnei/wird/server/internal/rootsense"
	"io"
	"sort"
	"strings"
	"text/tabwriter"
)

// Survey reports how much evidence exists to check against, before any sense
// is proposed. A root with one slot has nothing to predict across and is
// unverifiable whatever sense is offered for it.
func Survey(w io.Writer, roots map[string]*rootsense.Root) {
	bySlots := map[int]int{}
	byWords := map[string]int{}
	checkable, oneWord, oneSlotManyGlosses := 0, 0, 0
	for _, r := range roots {
		n := len(r.Slots)
		bySlots[n]++
		switch {
		case n >= 2:
			checkable++
		case r.Words == 1:
			oneWord++
		default:
			if len(r.Slots[0].Glosses) > 1 {
				oneSlotManyGlosses++
			}
		}
		byWords[bucket(r.Words)]++
	}

	fmt.Fprintf(w, "roots %d   checkable (>=2 slots) %d   unverifiable (1 slot) %d\n",
		len(roots), checkable, len(roots)-checkable)
	fmt.Fprintf(w, "of the unverifiable: %d attest a single word, %d attest several words in one slot\n\n",
		oneWord, oneSlotManyGlosses)

	fmt.Fprintln(w, "distinct morphological slots per root")
	keys := make([]int, 0, len(bySlots))
	for k := range bySlots {
		keys = append(keys, k)
	}
	sort.Ints(keys)
	for _, k := range keys {
		fmt.Fprintf(w, "%3d slots  %5d  %s\n", k, bySlots[k], bar(bySlots[k], len(roots)))
	}

	fmt.Fprintln(w, "\nglossed words per root")
	for _, b := range []string{"1", "2", "3-4", "5-9", "10-19", "20-49", "50-99", "100-499", "500+"} {
		fmt.Fprintf(w, "%8s  %5d  %s\n", b, byWords[b], bar(byWords[b], len(roots)))
	}
}

func bucket(n int) string {
	switch {
	case n <= 2:
		return fmt.Sprint(n)
	case n < 5:
		return "3-4"
	case n < 10:
		return "5-9"
	case n < 20:
		return "10-19"
	case n < 50:
		return "20-49"
	case n < 100:
		return "50-99"
	case n < 500:
		return "100-499"
	}
	return "500+"
}

func bar(n, total int) string {
	return strings.Repeat("#", n*50/total)
}

// candidateRules are the wazn-to-English rules worth measuring. Which of them
// the check actually relies on is decided by this measurement, not by grammar
// books: a rule earns its place only if its English marker really does show up
// in that slot's glosses far above its rate elsewhere, often enough to matter.
var candidateRules = map[string][]string{
	"form-II":     {"make", "made", "cause"},
	"form-III":    {"with", "against"},
	"form-IV":     {"make", "made", "cause"},
	"form-V":      {"himself", "themselves", "yourself"},
	"form-VI":     {"each", "other", "another"},
	"form-VII":    {"become", "becomes"},
	"form-VIII":   {"himself", "themselves"},
	"form-X":      {"seek", "ask"},
	"pass-verb":   {"been", "was", "were"},
	"act-pcpl":    {"who", "those", "ones"},
	"pass-pcpl":   {"who", "those", "ones"},
	"verbal-noun": {"ing"},
}

// Reliability measures each candidate rule's English marker against the corpus
// and prints how often it fires and how enriched it is.
func Reliability(w io.Writer, roots map[string]*rootsense.Root) {
	inSlot := map[string]map[string]int{}
	slotTotal := map[string]int{}
	overall := map[string]int{}
	total := 0
	for _, r := range roots {
		for _, s := range r.Slots {
			if inSlot[s.Name] == nil {
				inSlot[s.Name] = map[string]int{}
			}
			for _, g := range s.Glosses {
				slotTotal[s.Name]++
				total++
				seen := map[string]bool{}
				for _, t := range rootsense.WordRe.FindAllString(g.Text, -1) {
					if seen[t] {
						continue
					}
					seen[t] = true
					inSlot[s.Name][t]++
					overall[t]++
				}
			}
		}
	}

	tw := tabwriter.NewWriter(w, 0, 0, 2, ' ', 0)
	fmt.Fprintln(tw, "slot\tglosses\tmarker\thits\tcoverage\tenrichment\tused")
	names := make([]string, 0, len(candidateRules))
	for k := range candidateRules {
		names = append(names, k)
	}
	sort.Strings(names)
	for _, slot := range names {
		n := slotTotal[slot]
		if n == 0 {
			continue
		}
		for _, m := range candidateRules[slot] {
			hits := inSlot[slot][m]
			cov := float64(hits) / float64(n)
			var enr float64
			if overall[m] > 0 {
				enr = cov / (float64(overall[m]) / float64(total))
			}
			fmt.Fprintf(tw, "%s\t%d\t%s\t%d\t%.1f%%\t%.1fx\t%v\n",
				slot, n, m, hits, cov*100, enr, usedMarker(slot, m))
		}
	}
	tw.Flush()
}

func usedMarker(slot, marker string) bool {
	for _, m := range rootsense.Markers[slot] {
		if m == marker {
			return true
		}
	}
	return false
}
