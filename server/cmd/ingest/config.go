package main

import (
	"errors"
	"flag"
	"fmt"
	"os"
	"slices"
	"strconv"
	"strings"
	"time"
)

// Config is the whole of ingest's configuration: its flags. It reads no
// environment. The table under "### `ingest`" in
// docs/architecture/pipelines.md lists every flag with its default, and
// TestConfigDocumented holds the two to the same set.
type Config struct {
	Out, Manifest string
	// Suras is nil for every chapter chapters.json lists.
	Suras       []int
	Recitations []string
	Delay       time.Duration
	Retries     int
	Force       bool
}

// loadConfig defines ingest's flags on fs, parses args, and checks them before
// anything is read or fetched, with every problem in one error.
func loadConfig(fs *flag.FlagSet, args []string) (Config, error) {
	var c Config
	var only, recitations string
	fs.StringVar(&c.Out, "out", "./data/raw/", "directory the downloads land in; gitignored")
	fs.StringVar(&c.Manifest, "manifest", "./data/manifest.json", "manifest to write; this is what git holds")
	fs.StringVar(&only, "suras", "", "suras to fetch, e.g. 1,2,103,112 or 1-5 (default: all 114)")
	fs.StringVar(&recitations, "recitations", strings.Join(slices.Clone(defaultRecitations), ","),
		"which of quran-align's 12 recitations to take word timings from, comma-separated")
	fs.DurationVar(&c.Delay, "delay", 200*time.Millisecond, "pause between requests")
	fs.IntVar(&c.Retries, "retries", 5, "retries per request before giving up")
	fs.BoolVar(&c.Force, "force", false, "re-download files that are already on disk")
	if err := fs.Parse(args); err != nil {
		return c, err
	}

	var errs []error
	var err error
	if c.Suras, err = parseSuras(only); err != nil {
		errs = append(errs, err)
	}
	c.Recitations = strings.Split(recitations, ",")
	// A negative count makes no attempt at all, and a run that has to fetch
	// anything gives up on its first file "after 0 attempts".
	if c.Retries < 0 {
		errs = append(errs, errors.New("-retries must be 0 or more"))
	}
	return c, errors.Join(errs...)
}

// parseSuras reads -suras. Empty is nil: every chapter. The refusal quotes
// what was given, which is a sura list and never a secret.
func parseSuras(spec string) ([]int, error) {
	if strings.TrimSpace(spec) == "" {
		return nil, nil
	}
	var out []int
	for _, part := range strings.Split(spec, ",") {
		part = strings.TrimSpace(part)
		lo, hi, isRange := strings.Cut(part, "-")
		if !isRange {
			hi = lo
		}
		a, err1 := strconv.Atoi(strings.TrimSpace(lo))
		b, err2 := strconv.Atoi(strings.TrimSpace(hi))
		if err1 != nil || err2 != nil || a < 1 || b > 114 || a > b {
			return nil, fmt.Errorf("-suras %q: %q is not a sura or a range within 1-114", spec, part)
		}
		for n := a; n <= b; n++ {
			out = append(out, n)
		}
	}
	return out, nil
}

// fromProcess is ingest's real command line.
func fromProcess() (Config, error) {
	return loadConfig(flag.CommandLine, os.Args[1:])
}
