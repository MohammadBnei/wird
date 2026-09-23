package rootsense

import "fmt"

// biggestMiss names the gloss carrying the most occurrences that the sense does
// not explain: the branch of the root a reader would meet and the sense would
// not cover.
func BiggestMiss(root *Root, sense string) string {
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
