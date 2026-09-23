// rootcheck tests a proposed English sense for an Arabic root against the
// glosses the bundled corpus already carries for that root's own words.
//
// It answers one question and refuses to answer any other: does this sense
// predict what the corpus says, across the morphological shapes the root
// appears in? A sense the corpus does not bear out is reported as unverified,
// and an unverified root ships nothing.
package main

import (
	"flag"
	"fmt"
	"os"
	"sort"
	"text/tabwriter"

	"github.com/MohammadBnei/wird/server/internal/rootsense"
)

func main() {
	db := flag.String("db", "./app/assets/corpus.db", "corpus.db to read")
	threshold := flag.Float64("threshold", 0, "pass mark; 0 means use the calibrated one")
	out := flag.String("o", "", "build: JSON file to write the verified senses to")
	perSlot := flag.Int("per-slot", 4, "evidence: glosses to print per morphological slot")
	flag.Usage = func() {
		fmt.Fprint(os.Stderr, `rootcheck <command> [flags]

  check <root> <sense>  score one candidate sense against one root
  calibrate             score the built-in right/wrong senses, report the separation
  build <file>          score every authored sense, keep only what the corpus bears out
  specificity [file]    score each sense against every root, not just its own;
                        with no file, the senses known to be right
  evidence              print every checkable root's glosses, for writing senses from
  survey                how much evidence each root offers, before any sense exists
  reliability           which wazn-to-English rules the corpus supports

`)
		flag.PrintDefaults()
	}
	flag.Parse()

	args := flag.Args()
	if len(args) == 0 {
		flag.Usage()
		os.Exit(2)
	}

	roots, err := rootsense.LoadRoots(*db)
	if err != nil {
		fmt.Fprintln(os.Stderr, "rootcheck:", err)
		os.Exit(1)
	}

	switch args[0] {
	case "check":
		if len(args) < 3 {
			flag.Usage()
			os.Exit(2)
		}
		t := *threshold
		if t == 0 {
			sep, err := rootsense.Calibrate(roots)
			if err != nil {
				fmt.Fprintln(os.Stderr, "rootcheck:", err)
				os.Exit(1)
			}
			t = sep.Threshold
		}
		root, ok := roots[args[1]]
		if !ok {
			fmt.Fprintf(os.Stderr, "rootcheck: root %q has no glossed words in the corpus\n", args[1])
			os.Exit(1)
		}
		reportCheck(os.Stdout, rootsense.Check(root, args[2]), t)

	case "calibrate":
		sep, err := rootsense.Calibrate(roots)
		if err != nil {
			fmt.Fprintln(os.Stderr, "rootcheck:", err)
			os.Exit(1)
		}
		sep.Report(os.Stdout, roots)

	case "build":
		if len(args) < 2 {
			flag.Usage()
			os.Exit(2)
		}
		cands, err := ReadCandidates(args[1])
		if err != nil {
			fmt.Fprintln(os.Stderr, "rootcheck:", err)
			os.Exit(1)
		}
		t := *threshold
		if t == 0 {
			sep, err := rootsense.Calibrate(roots)
			if err != nil {
				fmt.Fprintln(os.Stderr, "rootcheck:", err)
				os.Exit(1)
			}
			t = sep.Threshold
		}
		if err := Build(os.Stdout, roots, cands, t, *out); err != nil {
			fmt.Fprintln(os.Stderr, "rootcheck:", err)
			os.Exit(1)
		}

	case "specificity":
		var cands []Candidate
		if len(args) > 1 {
			var err error
			if cands, err = ReadCandidates(args[1]); err != nil {
				fmt.Fprintln(os.Stderr, "rootcheck:", err)
				os.Exit(1)
			}
		}
		t := *threshold
		if t == 0 {
			sep, err := rootsense.Calibrate(roots)
			if err != nil {
				fmt.Fprintln(os.Stderr, "rootcheck:", err)
				os.Exit(1)
			}
			t = sep.Threshold
		}
		Specificity(os.Stdout, roots, cands, t)

	case "evidence":
		Evidence(os.Stdout, roots, *perSlot)

	case "survey":
		Survey(os.Stdout, roots)

	case "reliability":
		Reliability(os.Stdout, roots)

	default:
		flag.Usage()
		os.Exit(2)
	}
}

func reportCheck(w *os.File, r rootsense.Result, threshold float64) {
	fmt.Fprintf(w, "%s  %q\n", r.Root, r.Sense)
	fmt.Fprintf(w, "%s  score %.3f (threshold %.3f)  recall %.3f  precision %.3f  slots %d/%d\n\n",
		r.Verdict(threshold), r.Score, threshold, r.Recall, r.Precision, r.SlotsHit, len(r.Slots))

	tw := tabwriter.NewWriter(w, 0, 0, 2, ' ', 0)
	fmt.Fprintln(tw, "slot\tagreed\tglosses that did not agree")
	slots := append([]rootsense.SlotResult(nil), r.Slots...)
	sort.Slice(slots, func(i, j int) bool { return slots[i].Recall() > slots[j].Recall() })
	for _, s := range slots {
		miss := ""
		for i, m := range s.Examples {
			if i > 0 {
				miss += "; "
			}
			miss += m
		}
		fmt.Fprintf(tw, "%s\t%d/%d\t%s\n", s.Name, s.Agreed, s.Total, miss)
	}
	tw.Flush()
	if len(r.Unmatched) > 0 {
		fmt.Fprintf(w, "\nsense words the root does not attest: %v\n", r.Unmatched)
	}
}
