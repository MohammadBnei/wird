package main

import (
	"errors"
	"flag"
	"fmt"
	"os"
)

// Config is the whole of jidhrcorpus's configuration: its flags, then the DSN
// from the environment, so a run against a deployed database is a variable
// rather than a password in a shell history. The DSN is never a flag nor a
// flag's default: a default is printed by -h and by every flag error.
//
// -db keeps its name and its meaning: the corpus.db the morphology is read out
// of. The Wird database is DATABASE_URL only.
//
// The table under "### `jidhrcorpus`" in docs/architecture/pipelines.md lists
// every flag and variable, and TestConfigDocumented holds the two to the same
// set.
type Config struct{ In, DSN, Out string }

// loadConfig defines the flags on fs, parses args, then reads getenv, with
// every problem in one error. A refusal names variables, never their values.
func loadConfig(fs *flag.FlagSet, args []string, getenv func(string) string) (Config, error) {
	var c Config
	fs.StringVar(&c.In, "db", "./app/assets/corpus.db", "the corpus.db the app bundles")
	fs.StringVar(&c.Out, "out", "./jidhr/testdata/quran.json", "the jidhr corpus to write")
	fs.Usage = func() {
		fmt.Fprintf(fs.Output(), "Usage of %s:\n", fs.Name())
		fs.PrintDefaults()
		fmt.Fprintln(fs.Output(), "\nEnvironment (read, never printed):\n"+
			"  DATABASE_URL  the Wird database the root senses are read out of; required unless WIRD_DEV=1\n"+
			"  WIRD_DEV      1 reads the local compose database when DATABASE_URL is unset")
	}
	if err := fs.Parse(args); err != nil {
		return c, err
	}
	var err error
	c.DSN, err = databaseURL(getenv, false)
	return c, err
}

// databaseURL is DATABASE_URL, else the local compose database under
// WIRD_DEV=1, else a refusal (docs/adr/0037): the silent localhost fallback
// this replaced exported whatever a local database happened to hold.
// optional is a run that touches no database, which needs neither.
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

// fromProcess is the one place jidhrcorpus reads its real command line and
// environment.
func fromProcess() (Config, error) {
	return loadConfig(flag.CommandLine, os.Args[1:], os.Getenv)
}
