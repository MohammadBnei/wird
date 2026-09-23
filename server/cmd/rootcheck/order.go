package main

import (
	"bufio"
	"fmt"
	"io"
	"os"
	"sort"
	"strings"

	"github.com/MohammadBnei/wird/server/internal/rootsense"
)

// Order rewrites a candidate file so that every sense leads with the branch a
// reader is likeliest to meet.
//
// It changes no claim. The clauses are the same clauses, saying the same
// things about the same root; they are sorted by how many of the root's own
// occurrences each one explains, heaviest first, and the French is permuted to
// match so the two languages keep saying the same thing in the same order.
// That is the whole of it, and it is worth a command rather than a hand pass
// because a hand pass over several hundred rows is where a French clause gets
// left behind its English.
//
// Sorting by what a clause explains on its own is enough to satisfy the check,
// which asks that no later clause explain more than the first: a later clause
// is credited only with what no earlier clause said, which is never more than
// it explains alone.
func Order(w io.Writer, roots map[string]*rootsense.Root, tsv string) error {
	f, err := os.Open(tsv)
	if err != nil {
		return err
	}
	defer f.Close()

	moved := 0
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		line := sc.Text()
		col := strings.Split(line, "\t")
		root := roots[col[0]]
		if strings.HasPrefix(line, "#") || strings.TrimSpace(line) == "" || len(col) < 2 || root == nil {
			fmt.Fprintln(w, line)
			continue
		}
		en := strings.Split(col[1], ";")
		if len(en) < 2 {
			fmt.Fprintln(w, line)
			continue
		}
		var fr []string
		if len(col) > 2 && strings.TrimSpace(col[2]) != "" {
			fr = strings.Split(col[2], ";")
			if len(fr) != len(en) {
				// One language making more claims than the other is a fault in
				// the row, not something to permute quietly around.
				fmt.Fprintf(os.Stderr, "%s: %d English clauses, %d French; left as written\n",
					col[0], len(en), len(fr))
				fmt.Fprintln(w, line)
				continue
			}
		}

		order := make([]int, len(en))
		covered := make([]int, len(en))
		for i, c := range en {
			order[i] = i
			if res := rootsense.Check(root, c); len(res.Clauses) > 0 {
				covered[i] = res.Clauses[0].Covered
			}
		}
		sort.SliceStable(order, func(a, b int) bool { return covered[order[a]] > covered[order[b]] })
		if order[0] != 0 {
			moved++
		}

		outEn := make([]string, len(en))
		outFr := make([]string, len(fr))
		for i, j := range order {
			outEn[i] = strings.TrimSpace(en[j])
			if fr != nil {
				outFr[i] = strings.TrimSpace(fr[j])
			}
		}
		row := []string{col[0], strings.Join(outEn, "; ")}
		if fr != nil {
			row = append(row, strings.Join(outFr, " ; "))
		} else if len(col) > 2 {
			row = append(row, col[2])
		}
		fmt.Fprintln(w, strings.Join(row, "\t"))
	}
	fmt.Fprintf(os.Stderr, "%d senses now lead with a different clause\n", moved)
	return sc.Err()
}
