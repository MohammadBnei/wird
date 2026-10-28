package configdoc

import (
	"os"
	"path/filepath"
	"slices"
	"testing"
)

func TestTable(t *testing.T) {
	path := filepath.Join(t.TempDir(), "doc.md")
	doc := "# x\n\n### `a`\n\n| Flag or variable | Default | What |\n|---|---|---|\n| `-in` | `./x/` | in |\n" +
		"| `-n` | none | n |\n| `DATABASE_URL` | none (WIRD_DEV=1: local) | db |\n\nprose\n\n" +
		"### `b`\n\n| Flag or variable | Default | What |\n|---|---|---|\n| `-other` | `1` | o |\n"
	if err := os.WriteFile(path, []byte(doc), 0o644); err != nil {
		t.Fatal(err)
	}
	got, err := Table(path, "### `a`")
	if err != nil {
		t.Fatal(err)
	}
	want := []Row{{"-in", "./x/"}, {"-n", ""}, {"DATABASE_URL", "none (WIRD_DEV=1: local)"}}
	if !slices.Equal(got, want) {
		t.Errorf("got %q, want %q", got, want)
	}
	// Positive control: the second table is read under its own heading, and
	// not at all under the first.
	if got, _ := Table(path, "### `b`"); !slices.Equal(got, []Row{{"-other", "1"}}) {
		t.Errorf("table b: %q", got)
	}
	if got, _ := Table(path, "### `c`"); got != nil {
		t.Errorf("a missing heading read %q", got)
	}
}
