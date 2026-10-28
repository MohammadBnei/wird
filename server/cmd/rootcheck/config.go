package main

import (
	"flag"
	"fmt"
	"os"
)

// Config is the whole of rootcheck's configuration: its flags and the command
// after them. It reads no environment. The table under "### `rootcheck`" in
// docs/architecture/pipelines.md lists every flag with its default, and
// TestConfigDocumented holds the two to the same set.
type Config struct {
	DB, LaneDir string
	Threshold   float64
	// Args is the command and its arguments; main dispatches on them.
	Args []string
}

// loadConfig defines rootcheck's flags and usage on fs and parses args.
func loadConfig(fs *flag.FlagSet, args []string) (Config, error) {
	var c Config
	fs.StringVar(&c.DB, "db", "./app/assets/corpus.db", "corpus.db to read")
	fs.StringVar(&c.LaneDir, "lane", "./data/raw/lane", "the  clone of Lane's TEI; gitignored, consulted, never shipped")
	fs.Float64Var(&c.Threshold, "threshold", 0, "score pass mark; 0 means the calibrated bar. Overriding it drops every term but the score and the clause order")
	fs.Usage = func() {
		fmt.Fprint(fs.Output(), `rootcheck <command> [flags]

  check <root> <sense>  score one candidate sense against one root
  calibrate             score the built-in right/wrong senses, report the separation
  scan                  score every known-right sense against every root
  survey                how much evidence each root offers, before any sense exists
  cost <tsv>            how many senses in a root\tsense TSV each part of the bar keeps
  order <tsv>           rewrite the TSV so every sense leads with its heaviest clause
  evidence [root...]    the glosses a sense must be written from, heaviest first
  build <tsv> <json>    check every proposed sense and write out the ones that hold
  reliability           which wazn-to-English rules the corpus supports
  lane <root>           Lane's article for a root, to write its sense from

`)
		fs.PrintDefaults()
	}
	err := fs.Parse(args)
	c.Args = fs.Args()
	return c, err
}

// fromProcess is rootcheck's real command line.
func fromProcess() (Config, error) {
	return loadConfig(flag.CommandLine, os.Args[1:])
}
