package main

import (
	"flag"
	"slices"
	"strings"
	"testing"

	"github.com/MohammadBnei/wird/server/internal/configdoc"
)

func newFS() *flag.FlagSet { return flag.NewFlagSet("rootdraft", flag.ContinueOnError) }

// The failure: a flag or a variable lands in the wrong field. Every value is
// one no other field holds.
func TestAFlagLandsInTheWrongField(t *testing.T) {
	args := []string{"-db", "c.db", "-lane", "lanedir", "-prompt", "p.md", "-out", "o.tsv", "-roots", "a,b",
		"-limit", "3", "-workers", "7", "-model", "m1", "-base-url", "http://flag/v1", "-json-mode=false", "-force"}
	got, err := loadConfig(newFS(), args, envMap(map[string]string{"OPENAI_API_KEY": "oa_K2"}), noHF)
	want := Config{DB: "c.db", LaneDir: "lanedir", Prompt: "p.md", Out: "o.tsv", Roots: "a,b", Limit: 3, Workers: 7,
		Model: "m1", BaseURL: "http://flag/v1", APIKey: "oa_K2", JSONMode: false, Force: true}
	if err != nil || got != want {
		t.Errorf("got %+v, %v\nwant %+v", got, err, want)
	}
}

// The failure: a run with no token, or with no worker to draft on, reads the
// prompt, the corpus and the log before it says so, or deadlocks.
func TestARunThatCannotDraftStarts(t *testing.T) {
	asked := 0
	hf := func(tok string) func() string { return func() string { asked++; return tok } }
	for _, tc := range []struct {
		name  string
		args  []string
		env   map[string]string
		hf    string
		key   string
		errs  []string
		asked int
	}{
		{"hf auth token", nil, nil, "hf_CLI", "hf_CLI", nil, 1},
		{"env wins, hf not asked", nil, map[string]string{"HF_TOKEN": "hf_K1"}, "hf_CLI", "hf_K1", nil, 0},
		{"no token anywhere", nil, nil, "", "", []string{
			"no API key: set HF_TOKEN or OPENAI_API_KEY, or run `hf auth login` so `hf auth token` can print one"}, 1},
		{"no workers", []string{"-workers", "0"}, map[string]string{"HF_TOKEN": "hf_K1"}, "", "hf_K1",
			[]string{"-workers must be 1 or more"}, 0},
		{"both at once", []string{"-workers", "-1"}, nil, "", "", []string{
			"no API key: set HF_TOKEN or OPENAI_API_KEY, or run `hf auth login` so `hf auth token` can print one",
			"-workers must be 1 or more"}, 1},
		// -dry calls nothing: no token is looked for, and no worker runs.
		{"dry", []string{"-dry", "-workers", "0"}, nil, "hf_CLI", "", nil, 0},
	} {
		asked = 0
		c, err := loadConfig(newFS(), tc.args, envMap(tc.env), hf(tc.hf))
		var got []string
		if err != nil {
			got = strings.Split(err.Error(), "\n")
		}
		if !slices.Equal(got, tc.errs) {
			t.Errorf("%s: refused with %q, want %q", tc.name, got, tc.errs)
		}
		if err == nil && c.APIKey != tc.key {
			t.Errorf("%s: key %q, want %q", tc.name, c.APIKey, tc.key)
		}
		if asked != tc.asked {
			t.Errorf("%s: `hf auth token` asked %d times, want %d", tc.name, asked, tc.asked)
		}
	}
}

// TestConfigDocumented: the flags with their effective defaults, the
// variables loadConfig reads, and the table in
// docs/architecture/pipelines.md are one set.
func TestConfigDocumented(t *testing.T) {
	fs, read := newFS(), map[string]bool{}
	if _, err := loadConfig(fs, nil, func(k string) string { read[k] = true; return "" }, func() string { return "hf_CLI" }); err != nil {
		t.Fatal(err)
	}
	configdoc.Check(t, "../../../docs/architecture/pipelines.md", "### `rootdraft`", fs, read)
}
