package main

import (
	"bytes"
	"flag"
	"slices"
	"strings"
	"testing"

	"github.com/MohammadBnei/wird/server/internal/configdoc"
)

func envMap(m map[string]string) func(string) string { return func(k string) string { return m[k] } }

func newFS() *flag.FlagSet { return flag.NewFlagSet("senseseed", flag.ContinueOnError) }

// The failure: -h, and every flag error, prints the database password.
func TestHelpNeverPrintsTheDatabasePassword(t *testing.T) {
	fs := newFS()
	var buf bytes.Buffer
	fs.SetOutput(&buf)
	getenv := func(string) string { return "postgres://u:PWSENTINEL@h/db" }
	if _, err := loadConfig(fs, []string{"-h"}, getenv); err != flag.ErrHelp {
		t.Fatalf("-h: got %v, want flag.ErrHelp", err)
	}
	out := buf.String()
	if strings.Contains(out, "PWSENTINEL") {
		t.Fatalf("-h printed DATABASE_URL:\n%s", out)
	}
	if fs.Lookup("db") != nil {
		t.Error("-db is a flag again; a DSN on the command line is in the shell history")
	}
	for _, want := range []string{"-tsv", "-roots", "-dry", "\n  DATABASE_URL ", "\n  WIRD_DEV "} {
		if !strings.Contains(out, want) {
			t.Errorf("-h does not mention %s:\n%s", want, out)
		}
	}
}

// The failure: a seed meant for production, run with DATABASE_URL unset,
// replaces the local database's senses and reports a version as if it landed.
func TestAnUnsetDatabaseURLSeedsTheLocalDatabase(t *testing.T) {
	const url = "postgres://u:p@db.example/wird"
	for _, tc := range []struct {
		name string
		args []string
		env  map[string]string
		dsn  string
		errs []string
	}{
		{"set", nil, map[string]string{"DATABASE_URL": url}, url, nil},
		{"set wins over dev", nil, map[string]string{"DATABASE_URL": url, "WIRD_DEV": "1"}, url, nil},
		{"dev", nil, map[string]string{"WIRD_DEV": "1"}, localDSN, nil},
		{"unset", nil, nil, "", []string{"DATABASE_URL is unset (WIRD_DEV=1 uses the local default)"}},
		{"dev not 1", nil, map[string]string{"WIRD_DEV": "true"}, "", []string{
			"WIRD_DEV must be 1 or unset", "DATABASE_URL is unset (WIRD_DEV=1 uses the local default)"}},
		// -dry touches no database, so it needs none; a bad WIRD_DEV is still refused.
		{"dry", []string{"-dry"}, nil, "", nil},
		{"dry, dev not 1", []string{"-dry"}, map[string]string{"WIRD_DEV": "yes"}, "", []string{"WIRD_DEV must be 1 or unset"}},
	} {
		c, err := loadConfig(newFS(), tc.args, envMap(tc.env))
		var got []string
		if err != nil {
			got = strings.Split(err.Error(), "\n")
		}
		if !slices.Equal(got, tc.errs) {
			t.Errorf("%s: refused with %q, want %q", tc.name, got, tc.errs)
		}
		if err == nil && c.DSN != tc.dsn {
			t.Errorf("%s: DSN %q, want %q", tc.name, c.DSN, tc.dsn)
		}
	}
}

// The failure: a flag lands in the wrong field.
func TestAFlagLandsInTheWrongField(t *testing.T) {
	c, err := loadConfig(newFS(), []string{"-tsv", "in.tsv", "-roots", "roots.db"}, envMap(map[string]string{"DATABASE_URL": "dsn-value"}))
	if want := (Config{TSV: "in.tsv", Roots: "roots.db", DSN: "dsn-value"}); err != nil || c != want {
		t.Errorf("got %+v, %v; want %+v", c, err, want)
	}
	c, err = loadConfig(newFS(), []string{"-dry"}, envMap(nil))
	if want := (Config{TSV: "./data/root_senses_draft.tsv", Roots: "./app/assets/corpus.db", Dry: true}); err != nil || c != want {
		t.Errorf("got %+v, %v; want %+v", c, err, want)
	}
}

// TestConfigDocumented: the flags with their defaults, the variables
// loadConfig reads, and the table in docs/architecture/pipelines.md are one
// set.
func TestConfigDocumented(t *testing.T) {
	fs, read := newFS(), map[string]bool{}
	if _, err := loadConfig(fs, nil, func(k string) string { read[k] = true; return map[string]string{"DATABASE_URL": "x"}[k] }); err != nil {
		t.Fatal(err)
	}
	configdoc.Check(t, "../../../docs/architecture/pipelines.md", "### `senseseed`", fs, read)
}
