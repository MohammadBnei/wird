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
	"github.com/MohammadBnei/wird/server/internal/rootsense"
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
  cost <tsv>            how many senses in a root\tsense TSV each part of the bar keeps
  evidence [root...]    the glosses a sense must be written from, heaviest first
  build <tsv> <json>    check every proposed sense and write out the ones that hold
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
		bar, err := barFor(roots, *threshold)
		if err != nil {
			fmt.Fprintln(os.Stderr, "rootcheck:", err)
			os.Exit(1)
		}
		root, ok := roots[args[1]]
		if !ok {
			fmt.Fprintf(os.Stderr, "rootcheck: root %q has no glossed words in the corpus\n", args[1])
			os.Exit(1)
		}
		reportCheck(os.Stdout, rootsense.Check(root, args[2]), bar)

	case "calibrate":
		sep, err := rootsense.Calibrate(roots)
		if err != nil {
			fmt.Fprintln(os.Stderr, "rootcheck:", err)
			os.Exit(1)
		}
		sep.Report(os.Stdout, roots)

	case "scan":
		bar, err := barFor(roots, *threshold)
		if err != nil {
			fmt.Fprintln(os.Stderr, "rootcheck:", err)
			os.Exit(1)
		}
		Scan(os.Stdout, roots, bar)

	case "cost":
		if len(args) < 2 {
			flag.Usage()
			os.Exit(2)
		}
		bar, err := barFor(roots, *threshold)
		if err != nil {
			fmt.Fprintln(os.Stderr, "rootcheck:", err)
			os.Exit(1)
		}
		if err := Cost(os.Stdout, roots, args[1], bar); err != nil {
			fmt.Fprintln(os.Stderr, "rootcheck:", err)
			os.Exit(1)
		}

	case "evidence":
		Evidence(os.Stdout, roots, args[1:], 12)

	case "build":
		if len(args) < 3 {
			flag.Usage()
			os.Exit(2)
		}
		bar, err := barFor(roots, *threshold)
		if err != nil {
			fmt.Fprintln(os.Stderr, "rootcheck:", err)
			os.Exit(1)
		}
		if err := Build(os.Stdout, roots, args[1], args[2], bar); err != nil {
			fmt.Fprintln(os.Stderr, "rootcheck:", err)
			os.Exit(1)
		}

	case "survey":
		Survey(os.Stdout, roots)

	case "reliability":
		Reliability(os.Stdout, roots)

	default:
		flag.Usage()
		os.Exit(2)
	}
}

// barFor returns the calibrated bar, or a score-only bar when the operator
// overrides the threshold by hand.
func barFor(roots map[string]*rootsense.Root, override float64) (rootsense.Bar, error) {
	if override != 0 {
		return rootsense.Bar{Score: override}, nil
	}
	sep, err := rootsense.Calibrate(roots)
	return sep.Bar, err
}

func reportCheck(w *os.File, r rootsense.Result, bar rootsense.Bar) {
	fmt.Fprintf(w, "%s  %q\n", r.Root, r.Sense)
	fmt.Fprintf(w, "%s  score %.3f/%.3f  coverage %.3f/%.3f of %d occurrences  dispersion %s/%d  slots %d/%d\n\n",
		r.Verdict(bar), r.Score, bar.Score, r.Coverage, bar.Coverage, r.Tested,
		rootsense.Disp(r.Dispersion), bar.Dispersion, r.SlotsHit, len(r.Slots))

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
	for _, c := range r.Clauses {
		if len(c.Ungrounded) == 0 {
			continue
		}
		fmt.Fprintf(w, "\nclause %q rests on words this root never shows:\n", c.Text)
		for _, u := range c.Ungrounded {
			kind := "instead of the attested words"
			if u.Rider {
				kind = "riding on an attested word"
			}
			fmt.Fprintf(w, "  %-14s glossed under %3d roots  (%s)\n", u.Stem, u.Roots, kind)
		}
	}
}
