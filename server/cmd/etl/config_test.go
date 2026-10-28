package main

import (
	"flag"
	"testing"

	"github.com/MohammadBnei/wird/server/internal/configdoc"
)

func newFS() *flag.FlagSet { return flag.NewFlagSet("etl", flag.ContinueOnError) }

// The failure: a flag lands in the wrong field; In and Out are both strings.
func TestAFlagLandsInTheWrongField(t *testing.T) {
	got, err := loadConfig(newFS(), []string{"-in", "raw/", "-out", "c.db", "-corpus-version", "42", "-full=false"})
	if want := (Config{In: "raw/", Out: "c.db", CorpusVersion: 42, Full: false}); err != nil || got != want {
		t.Errorf("got %+v, %v; want %+v", got, err, want)
	}
}

// TestConfigDocumented: the flags with their defaults and the table in
// docs/architecture/pipelines.md are one set. etl reads no environment.
func TestConfigDocumented(t *testing.T) {
	fs := newFS()
	if _, err := loadConfig(fs, nil); err != nil {
		t.Fatal(err)
	}
	configdoc.Check(t, "../../../docs/architecture/pipelines.md", "### `etl`", fs, nil)
}
