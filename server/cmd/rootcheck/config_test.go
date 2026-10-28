package main

import (
	"bytes"
	"flag"
	"reflect"
	"strings"
	"testing"

	"github.com/MohammadBnei/wird/server/internal/configdoc"
)

func newFS() *flag.FlagSet { return flag.NewFlagSet("rootcheck", flag.ContinueOnError) }

// The failure: a flag lands in the wrong field, or the command loses its
// arguments.
func TestAFlagLandsInTheWrongField(t *testing.T) {
	got, err := loadConfig(newFS(), []string{"-db", "c.db", "-lane", "lanedir", "-threshold", "0.5", "check", "رحم", "to show mercy"})
	want := Config{DB: "c.db", LaneDir: "lanedir", Threshold: 0.5, Args: []string{"check", "رحم", "to show mercy"}}
	if err != nil || !reflect.DeepEqual(got, want) {
		t.Errorf("got %+v, %v; want %+v", got, err, want)
	}
}

// The failure: -h on the FlagSet loadConfig was given prints some other set's
// flags, or prints them somewhere other than that set's output.
func TestHelpListsTheCommandsAndThisSetsFlags(t *testing.T) {
	fs := newFS()
	var buf bytes.Buffer
	fs.SetOutput(&buf)
	if _, err := loadConfig(fs, []string{"-h"}); err != flag.ErrHelp {
		t.Fatalf("-h: got %v, want flag.ErrHelp", err)
	}
	for _, want := range []string{"rootcheck <command> [flags]", "lane <root>", "-threshold", "-lane"} {
		if !strings.Contains(buf.String(), want) {
			t.Errorf("-h does not mention %s:\n%s", want, buf.String())
		}
	}
}

// TestConfigDocumented: the flags with their defaults and the table in
// docs/architecture/pipelines.md are one set. rootcheck reads no environment.
func TestConfigDocumented(t *testing.T) {
	fs := newFS()
	if _, err := loadConfig(fs, nil); err != nil {
		t.Fatal(err)
	}
	configdoc.Check(t, "../../../docs/architecture/pipelines.md", "### `rootcheck`", fs, nil)
}
