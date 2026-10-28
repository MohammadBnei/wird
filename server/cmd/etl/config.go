package main

import (
	"flag"
	"os"
)

// Config is the whole of etl's configuration: its flags. It reads no
// environment. The table under "### `etl`" in docs/architecture/pipelines.md
// lists every flag with its default, and TestConfigDocumented holds the two
// to the same set.
type Config struct {
	In, Out       string
	CorpusVersion int
	Full          bool
}

// loadConfig defines etl's flags on fs and parses args into a Config.
func loadConfig(fs *flag.FlagSet, args []string) (Config, error) {
	var c Config
	fs.StringVar(&c.In, "in", "./data/raw/", "ingest directory")
	fs.StringVar(&c.Out, "out", "./app/assets/corpus.db", "corpus.db to write")
	// The asset in app/assets/ carries 8 (bundledCorpusVersion in the app), the API
	// groups reports by this number, and the rebuild SOURCES.md documents passes
	// no flag — so a stale default would silently regress every report's build.
	// app/test/features/report/report_screen_test.dart asserts the asset agrees
	// with this, which is what caught the last bump.
	fs.IntVar(&c.CorpusVersion, "corpus-version", 8, "corpus_version the API negotiates")
	fs.BoolVar(&c.Full, "full", true, "require the whole Qur'an: 114 suras, 6236 ayas")
	err := fs.Parse(args)
	return c, err
}

// fromProcess is etl's real command line.
func fromProcess() (Config, error) {
	return loadConfig(flag.CommandLine, os.Args[1:])
}
