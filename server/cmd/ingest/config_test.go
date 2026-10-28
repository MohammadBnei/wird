package main

import (
	"flag"
	"reflect"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/MohammadBnei/wird/server/internal/configdoc"
)

func newFS() *flag.FlagSet { return flag.NewFlagSet("ingest", flag.ContinueOnError) }

// The failure: a flag lands in the wrong field; Out and Manifest are both
// strings, Delay and Retries both numbers.
func TestAFlagLandsInTheWrongField(t *testing.T) {
	got, err := loadConfig(newFS(), []string{"-out", "raw/", "-manifest", "m.json", "-suras", "1,2,103-105",
		"-recitations", "A,B", "-delay", "3s", "-retries", "9", "-force"})
	want := Config{Out: "raw/", Manifest: "m.json", Suras: []int{1, 2, 103, 104, 105}, Recitations: []string{"A", "B"},
		Delay: 3 * time.Second, Retries: 9, Force: true}
	if err != nil || !reflect.DeepEqual(got, want) {
		t.Errorf("got %+v, %v\nwant %+v", got, err, want)
	}
	// No -suras is every chapter, which run reads from chapters.json.
	got, err = loadConfig(newFS(), nil)
	if err != nil || got.Suras != nil || !slices.Equal(got.Recitations, defaultRecitations) {
		t.Errorf("defaults: %+v, %v", got, err)
	}
}

// The failure: a bad -suras or a negative -retries is found only after the
// morphology check and two downloads, or not at all.
func TestABadFlagIsFoundAfterTheDownloads(t *testing.T) {
	for _, tc := range []struct {
		args []string
		errs []string
	}{
		{[]string{"-suras", "1,abc"}, []string{`-suras "1,abc": "abc" is not a sura or a range within 1-114`}},
		{[]string{"-suras", "0"}, []string{`-suras "0": "0" is not a sura or a range within 1-114`}},
		{[]string{"-suras", "5-3"}, []string{`-suras "5-3": "5-3" is not a sura or a range within 1-114`}},
		{[]string{"-suras", "114-115"}, []string{`-suras "114-115": "114-115" is not a sura or a range within 1-114`}},
		{[]string{"-retries", "-1"}, []string{"-retries must be 0 or more"}},
		{[]string{"-suras", ",", "-retries", "-2"}, []string{`-suras ",": "" is not a sura or a range within 1-114`, "-retries must be 0 or more"}},
		{[]string{"-suras", " ", "-retries", "0"}, nil},
	} {
		_, err := loadConfig(newFS(), tc.args)
		var got []string
		if err != nil {
			got = strings.Split(err.Error(), "\n")
		}
		if !slices.Equal(got, tc.errs) {
			t.Errorf("%v: refused with %q, want %q", tc.args, got, tc.errs)
		}
	}
}

// TestConfigDocumented: the flags with their defaults and the table in
// docs/architecture/pipelines.md are one set. ingest reads no environment.
func TestConfigDocumented(t *testing.T) {
	fs := newFS()
	if _, err := loadConfig(fs, nil); err != nil {
		t.Fatal(err)
	}
	configdoc.Check(t, "../../../docs/architecture/pipelines.md", "### `ingest`", fs, nil)
}
