// Package configdoc holds each CLI's flags and environment variables to the
// table docs/architecture/pipelines.md keeps for it. It is a test helper
// outside a _test.go file, imported only by the CLIs' config tests, like
// internal/testenv.
package configdoc

import (
	"bufio"
	"flag"
	"fmt"
	"maps"
	"os"
	"slices"
	"strings"
	"testing"
)

// Row is one line of a configuration table: a flag ("-name") or a variable,
// and its default as written in the doc, backticks dropped. "none" is empty.
type Row struct{ Name, Default string }

// Table reads the first table after the line heading in the markdown file at
// path. The first two cells of each row are the name and the default.
func Table(path, heading string) ([]Row, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	var rows []Row
	under, in := false, false
	for sc := bufio.NewScanner(f); sc.Scan(); {
		line := strings.TrimSpace(sc.Text())
		switch {
		case !under:
			under = line == heading
		case !strings.HasPrefix(line, "|"):
			if in {
				return rows, nil
			}
		case !in:
			in = true // the header row
		case strings.HasPrefix(line, "|-"), strings.HasPrefix(line, "| -"):
		default:
			cells := strings.Split(line, "|")
			if len(cells) < 3 {
				continue
			}
			def := cell(cells[2])
			if def == "none" {
				def = ""
			}
			rows = append(rows, Row{Name: cell(cells[1]), Default: def})
		}
	}
	return rows, nil
}

func cell(s string) string { return strings.Trim(strings.TrimSpace(s), "`") }

// Check holds fs and the variables a loader read to the table under heading
// in doc: the same flags with the same defaults, and the same variables. fs
// must have been through the CLI's loadConfig with no arguments, so each
// flag's value is its effective default, including one filled in after
// parsing (rootdraft's -prompt, -out and -base-url).
func Check(t testing.TB, doc, heading string, fs *flag.FlagSet, read map[string]bool) {
	t.Helper()
	rows, err := Table(doc, heading)
	if err != nil {
		t.Fatal(err)
	}
	if len(rows) == 0 {
		t.Fatalf("%s has no table under %q", doc, heading)
	}
	for _, p := range Diff(rows, fs, read) {
		t.Errorf("%s under %q %s", doc, heading, p)
	}
}

// Diff is what Check reports: each flag or variable the rows leave out, each
// flag whose documented default differs, and each row the code does not read.
func Diff(rows []Row, fs *flag.FlagSet, read map[string]bool) []string {
	want := map[string]string{} // what the code has
	fs.VisitAll(func(f *flag.Flag) { want["-"+f.Name] = f.Value.String() })
	for v := range read {
		want[v] = ""
	}
	got := map[string]string{} // what the doc says
	for _, r := range rows {
		if !strings.HasPrefix(r.Name, "-") {
			r.Default = "" // a variable's default is prose; its name is what is held
		}
		got[r.Name] = r.Default
	}
	var problems []string
	for _, name := range slices.Sorted(maps.Keys(want)) {
		d, ok := got[name]
		switch {
		case !ok:
			problems = append(problems, "does not document "+name)
		case d != want[name]:
			problems = append(problems, fmt.Sprintf("gives %s the default %q; the code has %q", name, d, want[name]))
		}
	}
	for _, name := range slices.Sorted(maps.Keys(got)) {
		if _, ok := want[name]; !ok {
			problems = append(problems, "documents "+name+", which the code does not read")
		}
	}
	return problems
}
