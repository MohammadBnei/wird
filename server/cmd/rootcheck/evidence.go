package main

import (
	"fmt"
	"io"
	"sort"
	"strings"

	"github.com/MohammadBnei/wird/server/internal/rootsense"
)

// Evidence prints, for every root the check can judge, the glosses the corpus
// carries and the morphological shape each came from. It is the input a sense
// is written from, and printing it is the only way to write one root by root
// rather than from memory.
//
// Glosses are capped per slot: a root with three hundred glosses for one shape
// says the same thing three hundred times, and the cap keeps the wide roots
// from burying the narrow ones.
func Evidence(w io.Writer, roots map[string]*rootsense.Root, perSlot int) {
	letters := make([]string, 0, len(roots))
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

	for _, l := range letters {
		r := roots[l]
		var parts []string
		for _, s := range r.Slots {
			gs := s.Glosses
			if len(gs) > perSlot {
				// Shortest first: a short gloss is the translator's bare
				// rendering, a long one carries the sentence around it.
				gs = append([]string(nil), gs...)
				sort.Slice(gs, func(i, j int) bool { return len(gs[i]) < len(gs[j]) })
				gs = gs[:perSlot]
			}
			parts = append(parts, fmt.Sprintf("%s[%d]: %s", s.Name, len(s.Glosses), strings.Join(gs, " / ")))
		}
		fmt.Fprintf(w, "%s\t%dw\t%s\n", r.Letters, r.Words, strings.Join(parts, "\t"))
	}
}
