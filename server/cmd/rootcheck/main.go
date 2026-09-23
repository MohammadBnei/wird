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
)

func main() {
	db := flag.String("db", "./app/assets/corpus.db", "corpus.db to read")
	threshold := flag.Float64("threshold", 0, "pass mark; 0 means use the calibrated one")
	flag.Usage = func() {
		fmt.Fprint(os.Stderr, `rootcheck <command> [flags]

  check <root> <sense>  score one candidate sense against one root
  calibrate             score the built-in right/wrong senses, report the separation
  scan                  score every known-right sense against every root
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

	roots, err := LoadRoots(*db)
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
			sep, err := Calibrate(roots)
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
		reportCheck(os.Stdout, Check(root, args[2]), t)

	case "calibrate":
		sep, err := Calibrate(roots)
		if err != nil {
			fmt.Fprintln(os.Stderr, "rootcheck:", err)
			os.Exit(1)
		}
		sep.Report(os.Stdout, roots)

	case "scan":
		t := *threshold
		if t == 0 {
			sep, err := Calibrate(roots)
			if err != nil {
				fmt.Fprintln(os.Stderr, "rootcheck:", err)
				os.Exit(1)
			}
			t = sep.Threshold
		}
		Scan(os.Stdout, roots, t)

	case "survey":
		Survey(os.Stdout, roots)

	case "reliability":
		Reliability(os.Stdout, roots)

	default:
		flag.Usage()
		os.Exit(2)
	}
}

func reportCheck(w *os.File, r Result, threshold float64) {
	fmt.Fprintf(w, "%s  %q\n", r.Root, r.Sense)
	fmt.Fprintf(w, "%s  score %.3f (threshold %.3f)  recall %.3f  precision %.3f  slots %d/%d\n\n",
		r.Verdict(threshold), r.Score, threshold, r.Recall, r.Precision, r.SlotsHit, len(r.Slots))

	tw := tabwriter.NewWriter(w, 0, 0, 2, ' ', 0)
	fmt.Fprintln(tw, "slot\tagreed\tglosses that did not agree")
	slots := append([]SlotResult(nil), r.Slots...)
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
