package configdoc

import (
	"flag"
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
	// A heading with no table of its own does not borrow the next section's.
	if got, _ := Table(path, "# x"); got != nil {
		t.Errorf("# x has no table, read %q", got)
	}
}

func TestDiff(t *testing.T) {
	fs := flag.NewFlagSet("x", flag.ContinueOnError)
	fs.String("in", "./x/", "")
	read := map[string]bool{"DATABASE_URL": true}
	clean := []Row{{"-in", "./x/"}, {"DATABASE_URL", "none (WIRD_DEV=1: local)"}}
	for _, tc := range []struct {
		name string
		rows []Row
		want []string
	}{
		// Positive control: in sync, and a variable's prose default is not compared.
		{"clean", clean, nil},
		{"flag missing", clean[1:], []string{"does not document -in"}},
		{"variable missing", clean[:1], []string{"does not document DATABASE_URL"}},
		{"default differs", []Row{{"-in", "./y/"}, clean[1]},
			[]string{`gives -in the default "./y/"; the code has "./x/"`}},
		{"row not read", append(slices.Clone(clean), Row{"-gone", "1"}),
			[]string{"documents -gone, which the code does not read"}},
	} {
		if got := Diff(tc.rows, fs, read); !slices.Equal(got, tc.want) {
			t.Errorf("%s: got %q, want %q", tc.name, got, tc.want)
		}
	}
}
