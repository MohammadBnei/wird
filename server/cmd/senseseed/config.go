package main

import (
	"errors"
	"flag"
	"fmt"
	"os"
)

// Config is the whole of senseseed's configuration: its flags, then the DSN
// from the environment. The DSN is never a flag nor a flag's default: a
// default is printed by -h and by every flag error, and a DSN carries the
// database password.
//
// The table under "### `senseseed`" in docs/architecture/pipelines.md lists
// every flag and variable, and TestConfigDocumented holds the two to the same
// set.
type Config struct {
	TSV, Roots, DSN string
	Dry             bool
}

// loadConfig defines the flags on fs, parses args, then reads getenv, with
// every problem in one error. A refusal names variables, never their values.
func loadConfig(fs *flag.FlagSet, args []string, getenv func(string) string) (Config, error) {
	var c Config
	fs.StringVar(&c.TSV, "tsv", "./data/root_senses_draft.tsv", "the drafting log to seed from")
	fs.StringVar(&c.Roots, "roots", "./app/assets/corpus.db", "the corpus.db whose roots table every root is checked against")
	fs.BoolVar(&c.Dry, "dry", false, "read and check the file, write nothing, and touch no database")
	fs.Usage = func() {
		fmt.Fprintf(fs.Output(), "Usage of %s:\n", fs.Name())
		fs.PrintDefaults()
		fmt.Fprintln(fs.Output(), "\nEnvironment (read, never printed):\n"+
			"  DATABASE_URL  the database to seed; required unless WIRD_DEV=1 or -dry\n"+
			"  WIRD_DEV      1 seeds the local compose database when DATABASE_URL is unset")
	}
	if err := fs.Parse(args); err != nil {
		return c, err
	}
	var err error
	c.DSN, err = databaseURL(getenv, c.Dry)
	return c, err
}

// databaseURL is DATABASE_URL, else the local compose database under
// WIRD_DEV=1, else a refusal (docs/adr/0037): the silent localhost fallback
// this replaced let a seed meant for production replace whatever a local
// database held, and report a version as if it had landed. optional is a run
// that touches no database (-dry), which needs neither.
//
// ponytail: the same function as jidhrcorpus's config.go. Both are package
// main, and sharing twenty lines would take a package of its own.
func databaseURL(getenv func(string) string, optional bool) (string, error) {
	var errs []error
	dev := false
	switch getenv("WIRD_DEV") {
	case "":
	case "1":
		dev = true
	default:
		errs = append(errs, errors.New("WIRD_DEV must be 1 or unset"))
	}
	dsn := getenv("DATABASE_URL")
	switch {
	case dsn != "", optional:
	case dev:
		dsn = localDSN
	default:
		errs = append(errs, errors.New("DATABASE_URL is unset (WIRD_DEV=1 uses the local default)"))
	}
	return dsn, errors.Join(errs...)
}

// localDSN is the compose database's, with nothing secret in it.
const localDSN = "postgres://wird:wird@localhost:5432/wird"

// fromProcess is the one place senseseed reads its real command line and
// environment.
func fromProcess() (Config, error) {
	return loadConfig(flag.CommandLine, os.Args[1:], os.Getenv)
}
