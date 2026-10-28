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

func newFS() *flag.FlagSet { return flag.NewFlagSet("jidhrcorpus", flag.ContinueOnError) }

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
	if fs.Lookup("pg") != nil {
		t.Error("-pg is a flag again; a DSN on the command line is in the shell history")
	}
	for _, want := range []string{"-db", "-out", "\n  DATABASE_URL ", "\n  WIRD_DEV "} {
		if !strings.Contains(out, want) {
			t.Errorf("-h does not mention %s:\n%s", want, out)
		}
	}
}

// The failure: an unset DATABASE_URL exports whatever the local database
// holds, as if it were the one GET /v1/senses serves.
func TestAnUnsetDatabaseURLExportsTheLocalDatabase(t *testing.T) {
	const url = "postgres://u:p@db.example/wird"
	for _, tc := range []struct {
		name string
		env  map[string]string
		dsn  string
		errs []string
	}{
		{"set", map[string]string{"DATABASE_URL": url}, url, nil},
		{"set wins over dev", map[string]string{"DATABASE_URL": url, "WIRD_DEV": "1"}, url, nil},
		{"dev", map[string]string{"WIRD_DEV": "1"}, localDSN, nil},
		{"unset", nil, "", []string{"DATABASE_URL is unset (WIRD_DEV=1 uses the local default)"}},
		{"dev not 1", map[string]string{"WIRD_DEV": "true"}, "", []string{
			"WIRD_DEV must be 1 or unset", "DATABASE_URL is unset (WIRD_DEV=1 uses the local default)"}},
	} {
		c, err := loadConfig(newFS(), nil, envMap(tc.env))
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
	c, err := loadConfig(newFS(), []string{"-db", "in.db", "-out", "out.json"}, envMap(map[string]string{"DATABASE_URL": "dsn-value"}))
	if want := (Config{In: "in.db", DSN: "dsn-value", Out: "out.json"}); err != nil || c != want {
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
	configdoc.Check(t, "../../../docs/architecture/pipelines.md", "### `jidhrcorpus`", fs, read)
}
