package main

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/MohammadBnei/wird/server/internal/rootsense"
)

// corpusOf builds a small corpus out of words spelled here, so a test can say
// exactly what a root's own glosses are and how many occurrences carry each.
func corpusOf(words ...rootsense.WordRow) map[string]*rootsense.Root {
	return rootsense.Bucket(words)
}

func repeat(n int, w rootsense.WordRow) []rootsense.WordRow {
	out := make([]rootsense.WordRow, n)
	for i := range out {
		out[i] = w
	}
	return out
}

// The reordering pass has to move the French with the English. A sense whose
// clauses are sorted in one language and left as written in the other tells a
// French reader the opposite of what it tells an English one, which is worse
// than the wrong order it was run to fix.
func TestReorderingMovesTheFrenchWithTheEnglish(t *testing.T) {
	var words []rootsense.WordRow
	words = append(words, repeat(10, rootsense.WordRow{Root: "qwm", Gloss: "he stood", Form: "I"})...)
	words = append(words, repeat(90, rootsense.WordRow{Root: "qwm", Gloss: "a people"})...)
	roots := corpusOf(words...)

	dir := t.TempDir()
	tsv := filepath.Join(dir, "senses.tsv")
	if err := os.WriteFile(tsv, []byte("# a comment survives\nqwm\tto stand; a people\tse tenir debout ; un peuple\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	var out bytes.Buffer
	if err := Order(&out, roots, tsv); err != nil {
		t.Fatal(err)
	}

	lines := strings.Split(strings.TrimSpace(out.String()), "\n")
	if len(lines) != 2 || !strings.HasPrefix(lines[0], "#") {
		t.Fatalf("the comment line did not survive: %q", out.String())
	}
	col := strings.Split(lines[1], "\t")
	if col[1] != "a people; to stand" {
		t.Errorf("English reads %q; the branch carrying ninety of the hundred occurrences does not lead", col[1])
	}
	if col[2] != "un peuple ; se tenir debout" {
		t.Errorf("French reads %q; it did not move with the English", col[2])
	}
	if !rootsense.Check(roots["qwm"], col[1]).Leads {
		t.Errorf("%q still leads with its minority branch", col[1])
	}
}

// The duplicate-prose refusal takes both roots in a collision, because nothing
// in the check says which of them the prose belongs to. A proposal that ships
// nothing is not one of them: no reader is ever shown it, so refusing a sense
// the corpus bears out on its account refuses a root over prose that does not
// exist. هلك, 68 occurrences and borne out in three shapes, was refused by وبق,
// two occurrences in one shape and rejected by the score.
func TestAProposalThatShipsNothingDoesNotRefuseARootTheCorpusBearsOut(t *testing.T) {
	var words []rootsense.WordRow
	words = append(words, repeat(10, rootsense.WordRow{Root: "hlk", Gloss: "he destroyed", Form: "I"})...)
	words = append(words, repeat(10, rootsense.WordRow{Root: "hlk", Gloss: "destruction"})...)
	words = append(words, rootsense.WordRow{Root: "wbq", Gloss: "he destroyed", Form: "I"})
	roots := corpusOf(words...)

	dir := t.TempDir()
	tsv := filepath.Join(dir, "senses.tsv")
	same := "to destroy; destruction\tdétruire ; la destruction\n"
	if err := os.WriteFile(tsv, []byte("hlk\t"+same+"wbq\t"+same), 0o600); err != nil {
		t.Fatal(err)
	}
	out := filepath.Join(dir, "senses.json")
	bar := rootsense.Bar{Score: 0.2, Coverage: 0.5, Dispersion: 1, Branch: 0.5}
	if err := Build(&bytes.Buffer{}, roots, tsv, out, bar); err != nil {
		t.Fatal(err)
	}

	var bundle Bundle
	f, err := os.Open(out)
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	if err := json.NewDecoder(f).Decode(&bundle); err != nil {
		t.Fatal(err)
	}
	if len(bundle.Senses) != 1 || bundle.Senses[0].Root != "hlk" {
		t.Errorf("shipped %v; the root the corpus bears out was refused by one it does not", bundle.Senses)
	}
}
