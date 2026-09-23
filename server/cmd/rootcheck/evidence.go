package main

import (
	"fmt"
	"io"
	"sort"
	"strings"

	"github.com/MohammadBnei/wird/server/internal/rootsense"
)

// Evidence prints what a root actually says, which is what a sense has to be
// written from. Glosses come out heaviest first with their occurrence counts,
// because the branch a reader meets is the one the counts name: غير holds a
// dozen ways of saying "change" and one gloss, "other than", carrying most of
// its occurrences, and a list ordered alphabetically hides exactly that.
func Evidence(w io.Writer, roots map[string]*rootsense.Root, only []string, perSlot int) {
	letters := only
	if len(letters) == 0 {
		for k, r := range roots {
			if len(r.Slots) >= 2 {
				letters = append(letters, k)
			}
		}
		sort.Slice(letters, func(i, j int) bool {
			a, b := roots[letters[i]], roots[letters[j]]
			if a.Words != b.Words {
				return a.Words > b.Words
			}
			return a.Letters < b.Letters
		})
	}

	for _, l := range letters {
		r := roots[l]
		if r == nil {
			fmt.Fprintf(w, "%s\t(no glossed words)\n", l)
			continue
		}
		// Heaviest glosses first across every shape, because "what does this
		// root say" and "what will a reader meet" are the same question and the
		// counts answer it. The shape each gloss came from is kept beside it:
		// the sense still has to hold in more than one.
		var gs []rootsense.Gloss
		slotOf := map[string]string{}
		for _, s := range r.Slots {
			for _, g := range s.Glosses {
				gs = append(gs, g)
				slotOf[g.Text] = s.Name
			}
		}
		sort.Slice(gs, func(i, j int) bool { return gs[i].N > gs[j].N })
		if len(gs) > perSlot {
			gs = gs[:perSlot]
		}
		var parts []string
		for _, g := range gs {
			parts = append(parts, fmt.Sprintf("%s x%d [%s]", g.Text, g.N, slotOf[g.Text]))
		}
		fmt.Fprintf(w, "%s\t%dw %dslots\t%s\n", r.Letters, r.Words, len(r.Slots), strings.Join(parts, " / "))
	}
}
