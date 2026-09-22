package root

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
)

type normalizeCase struct {
	Input    string   `json:"input"`
	Expected string   `json:"expected"`
	Rules    []string `json:"rules"`
	Why      string   `json:"why"`
}

// normalizeContract is testdata/normalize.json: not a fixture but the specification the
// Dart normaliser on the device is written from. Its remove and fold tables are the
// contract; the tests below prove the Go code is exactly those tables, so an
// implementation that reads only this file lands on the same key for the same word.
type normalizeContract struct {
	Remove []struct {
		From string `json:"from"`
		To   string `json:"to"`
		Rule string `json:"rule"`
		What string `json:"what"`
	} `json:"remove"`
	Fold  map[string]string `json:"fold"`
	Rules []struct {
		ID   string `json:"id"`
		Text string `json:"text"`
	} `json:"rules"`
	Cases []normalizeCase `json:"cases"`
}

func loadNormalizeContract(t *testing.T) normalizeContract {
	t.Helper()
	body, err := os.ReadFile(filepath.Join(testdataDir, "normalize.json"))
	if err != nil {
		t.Fatalf("read the normalisation contract the Go and Dart normalisers share: %v", err)
	}
	var c normalizeContract
	if err := json.Unmarshal(body, &c); err != nil {
		t.Fatalf("parse the normalisation contract the Go and Dart normalisers share: %v", err)
	}
	if len(c.Cases) == 0 {
		t.Fatal("the contract the Go and Dart normalisers share holds no cases, so neither is pinned to anything")
	}
	if len(c.Remove) == 0 || len(c.Fold) == 0 || len(c.Rules) == 0 {
		t.Fatal("the contract is missing its remove, fold or rules table, so the Dart side has nothing to implement")
	}
	return c
}

func normalizeCases(t *testing.T) []normalizeCase {
	t.Helper()
	return loadNormalizeContract(t).Cases
}

// codePoint reads the "U+0627" spelling the contract writes every code point in.
func codePoint(t *testing.T, s string) rune {
	t.Helper()
	if !strings.HasPrefix(s, "U+") {
		t.Fatalf("the contract spells code points U+XXXX; %q is not readable without guessing", s)
	}
	v, err := strconv.ParseInt(s[2:], 16, 32)
	if err != nil {
		t.Fatalf("the contract spells code points U+XXXX; %q is not readable without guessing", s)
	}
	return rune(v)
}

// removeRanges reads the contract's remove table once, the way a reader of the file
// alone would read it, into the pairs the checks below scan.
func removeRanges(t *testing.T, c normalizeContract) [][2]rune {
	t.Helper()
	out := make([][2]rune, 0, len(c.Remove))
	for _, e := range c.Remove {
		out = append(out, [2]rune{codePoint(t, e.From), codePoint(t, e.To)})
	}
	return out
}

func removedByContract(ranges [][2]rune, r rune) bool {
	for _, p := range ranges {
		if r >= p[0] && r <= p[1] {
			return true
		}
	}
	return false
}

func TestEveryRuleTheContractStatesIsPinnedByACaseSoNoneCanDriftUnnoticed(t *testing.T) {
	c := loadNormalizeContract(t)
	stated := make(map[string]bool, len(c.Rules))
	for _, r := range c.Rules {
		if stated[r.ID] {
			t.Errorf("rule %q is stated twice, so a reader cannot tell which text binds", r.ID)
		}
		stated[r.ID] = true
	}
	pinned := make(map[string]bool, len(stated))
	for _, tc := range c.Cases {
		if len(tc.Rules) == 0 {
			t.Errorf("the case %q names no rule, so nothing says why it must hold", tc.Why)
		}
		for _, id := range tc.Rules {
			if !stated[id] {
				t.Errorf("the case %q names rule %q, which the contract does not state", tc.Why, id)
			}
			pinned[id] = true
		}
	}
	for _, r := range c.Rules {
		if !pinned[r.ID] {
			t.Errorf("rule %q is stated but no case exercises it, so the Dart normaliser can implement it wrongly and still read green", r.ID)
		}
	}
	for _, e := range c.Remove {
		if !stated[e.Rule] {
			t.Errorf("the remove range %s..%s cites rule %q, which the contract does not state", e.From, e.To, e.Rule)
		}
	}
}

func TestTheGoNormaliserRemovesExactlyTheCodePointsTheContractListsSoTheDeviceReachesTheSameKey(t *testing.T) {
	c := loadNormalizeContract(t)
	ranges := removeRanges(t, c)
	for r := rune(0); r <= 0x10FFFF; r++ {
		want := removedByContract(ranges, r)
		if got := dropped(r); got != want {
			if want {
				t.Fatalf("the contract removes U+%04X and the Go normaliser keeps it, so the same word reaches two different keys on the device and on the server", r)
			}
			t.Fatalf("the Go normaliser removes U+%04X and the contract does not list it, so the device keeps a character the server threw away", r)
		}
	}
}

func TestTheGoNormaliserFoldsExactlyTheCodePointsTheContractListsSoTheDeviceReachesTheSameKey(t *testing.T) {
	c := loadNormalizeContract(t)
	ranges := removeRanges(t, c)
	fold := make(map[rune]rune, len(c.Fold))
	for from, to := range c.Fold {
		fold[codePoint(t, from)] = codePoint(t, to)
	}
	for r := rune(0); r <= 0x10FFFF; r++ {
		if removedByContract(ranges, r) {
			continue
		}
		want := r
		if to, ok := fold[r]; ok {
			want = to
		}
		if got := folded(r); got != want {
			t.Fatalf("the contract folds U+%04X to U+%04X and the Go normaliser gives U+%04X, so the two implementations spell the same word differently", r, want, got)
		}
	}
}

func TestTheContractTablesCanOnlyBeReadOneWay(t *testing.T) {
	c := loadNormalizeContract(t)
	ranges := removeRanges(t, c)
	var prev rune = -1
	for _, e := range c.Remove {
		from, to := codePoint(t, e.From), codePoint(t, e.To)
		if from > to {
			t.Errorf("the remove range %s..%s runs backwards, and a reader who walks it forwards removes nothing", e.From, e.To)
		}
		if from <= prev {
			t.Errorf("the remove range starting %s overlaps or repeats the one before it, so two readers can count the ranges differently", e.From)
		}
		prev = to
	}
	for from, to := range c.Fold {
		f, tgt := codePoint(t, from), codePoint(t, to)
		if removedByContract(ranges, f) {
			t.Errorf("U+%04X is both removed and folded, so the answer depends on which table a reader consults first", f)
		}
		if removedByContract(ranges, tgt) {
			t.Errorf("U+%04X folds to U+%04X, which the contract then removes, so the fold produces a character that cannot survive", f, tgt)
		}
		if _, chained := c.Fold[to]; chained {
			t.Errorf("U+%04X folds to U+%04X, which folds again, so a reader who applies the table twice gets a different word than one who applies it once", f, tgt)
		}
	}
}

func TestOrthographicVariantsReduceToTheOneSpellingTheCorpusIsKeyedBy(t *testing.T) {
	for _, c := range normalizeCases(t) {
		t.Run(c.Why, func(t *testing.T) {
			got, err := normalize(c.Input)
			if err != nil {
				t.Fatalf("normalize(%q): %v", c.Input, err)
			}
			if got != c.Expected {
				t.Errorf("normalize(%q) = %q, want %q", c.Input, got, c.Expected)
			}
		})
	}
}

func TestNormalisingAnAlreadyNormalWordChangesNothing(t *testing.T) {
	for _, c := range normalizeCases(t) {
		t.Run(c.Why, func(t *testing.T) {
			once, err := normalize(c.Input)
			if err != nil {
				t.Fatalf("normalize(%q): %v", c.Input, err)
			}
			twice, err := normalize(once)
			if err != nil {
				t.Fatalf("normalize(%q): %v", once, err)
			}
			if twice != once {
				t.Errorf("normalising twice gave %q where once gave %q, so the device and the server disagree the moment either normalises a value the other already normalised", twice, once)
			}
		})
	}
}

func TestUnvowelledInputStillResolvesToTheRightRoot(t *testing.T) {
	r := testResolver(t)
	got, err := r.Resolve(context.Background(), "وتواصوا", nil)
	if err != nil {
		t.Fatalf("a word typed without diacritics resolved to nothing: %v", err)
	}
	if got.Root.Letters != "وصي" {
		t.Errorf("root letters = %q, want %q", got.Root.Letters, "وصي")
	}
	if got.Method != MethodNormalized {
		t.Errorf("method = %q, want %q: the corpus spells this form with diacritics, so calling it a lexicon hit overstates what we know", got.Method, MethodNormalized)
	}
	if got.Normalized != "وتواصوا" {
		t.Errorf("normalized = %q, want %q", got.Normalized, "وتواصوا")
	}
}

func TestAWordOnlyItsDictionaryFormKnowsStillReachesItsRoot(t *testing.T) {
	r := testResolver(t)
	got, err := r.Resolve(context.Background(), "صبر", []string{"en"})
	if err != nil {
		t.Fatalf("a form the corpus never attested but whose lemma it holds resolved to nothing: %v", err)
	}
	if got.Root.Letters != "صبر" {
		t.Errorf("root letters = %q, want %q", got.Root.Letters, "صبر")
	}
	if got.Method != MethodLemma {
		t.Errorf("method = %q, want %q", got.Method, MethodLemma)
	}
}

func TestTheSameWordRecognisedFromSpeechAndReadFromTheMushafReachOneKey(t *testing.T) {
	pairs := []struct {
		uthmani, modern string
	}{
		{"ٱلرَّحْمَٰنِ", "الرحمن"},
		{"هَٰذَا", "هذا"},
		{"بِهِۦ", "به"},
		{"ٱلصَّلَوٰةِ", "الصلوه"},
		{"هُدًى", "هدي"},
	}
	for _, p := range pairs {
		t.Run(p.modern, func(t *testing.T) {
			u, err := normalize(p.uthmani)
			if err != nil {
				t.Fatalf("normalize(%q): %v", p.uthmani, err)
			}
			m, err := normalize(p.modern)
			if err != nil {
				t.Fatalf("normalize(%q): %v", p.modern, err)
			}
			if u != m {
				t.Errorf("the mushaf spelling reduces to %q and the spoken one to %q, so the cursor would never advance past this word", u, m)
			}
		})
	}
}

func TestNormalisingNeverMergesTwoWordsThatAreNotTheSameWord(t *testing.T) {
	pairs := []struct {
		a, b, why string
	}{
		{"الفتح", "فتح", "the definite article is a prefix for the stripping rung, not orthography"},
		{"جاء", "جا", "a standalone hamza is a letter and distinguishes two words"},
		{"وتواصوا", "تواصوا", "an attached waw is a prefix to peel, never a mark to delete"},
		{"قلب", "كلب", "qaf and kaf are different letters"},
		{"ذهب", "دهب", "dhal and dal are different letters"},
		{"حمد", "همد", "ha and the letter ta marbuta folds onto are different letters"},
	}
	for _, p := range pairs {
		t.Run(p.why, func(t *testing.T) {
			a, err := normalize(p.a)
			if err != nil {
				t.Fatalf("normalize(%q): %v", p.a, err)
			}
			b, err := normalize(p.b)
			if err != nil {
				t.Fatalf("normalize(%q): %v", p.b, err)
			}
			if a == b {
				t.Errorf("%q and %q both reduce to %q, so one of them would be taught the other's root", p.a, p.b, a)
			}
		})
	}
}
