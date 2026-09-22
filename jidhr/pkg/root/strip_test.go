package root

import (
	"context"
	"errors"
	"slices"
	"testing"
)

func TestAPrefixedAndSuffixedWordStillReachesItsRoot(t *testing.T) {
	r := testResolver(t)
	got, err := r.Resolve(context.Background(), "وبالصبر", []string{"en"})
	if err != nil {
		t.Fatalf("a word carrying clitics resolved to nothing, so any Arabic outside the Qur'anic corpus is unreadable: %v", err)
	}
	if got.Root.Letters != "صبر" {
		t.Errorf("root letters = %q, want %q", got.Root.Letters, "صبر")
	}
	if got.Method != MethodStripped {
		t.Errorf("method = %q, want %q: a stem we derived must not be reported as an attested form", got.Method, MethodStripped)
	}
}

func TestAWordCarryingTheDefiniteArticleDoesNotLookLikeAnUnknownWord(t *testing.T) {
	stems, err := stripAffixes("الصبر")
	if err != nil {
		t.Fatalf("stripAffixes: %v", err)
	}
	if !slices.Contains(stems, "صبر") {
		t.Errorf("stems = %q, want one of them to be %q", stems, "صبر")
	}
}

func TestAThreeRadicalWordIsNeverPeeledDownToATwoLetterStem(t *testing.T) {
	// Each of these begins or ends with a letter that is also a clitic. Peeling it
	// leaves two letters, and two letters are not a root: the reader would be shown
	// a confident wrong answer, which is worse than being shown nothing.
	for _, word := range []string{"وعد", "وجه", "كتب", "بيت", "لبن", "سمع", "مات", "ملك", "نبي", "دعا"} {
		stems, err := stripAffixes(word)
		if err == nil {
			t.Errorf("%q: peeled into %q, so a radical was mistaken for an affix", word, stems)
		}
	}
}

func TestAWordWithNoAffixesIsAMissRatherThanAStoreFailure(t *testing.T) {
	_, err := stripAffixes("صبر")
	if !errors.Is(err, ErrNotFound) {
		t.Fatalf("want ErrNotFound so the ladder steps down a rung, got %v: any other error aborts resolution and turns an honest 404 into a 500", err)
	}
}

func TestAPronounSuffixComesOffBeforeALeadingRadicalIsReadAsAPreposition(t *testing.T) {
	// كتابه is "his book". Peeling the ك as the preposition "like" leaves تابه,
	// whose root is توب — repentance. The suffix is the affix; the ك is a radical.
	stems, err := stripAffixes("كتابه")
	if err != nil {
		t.Fatalf("stripAffixes: %v", err)
	}
	if stems[0] != "كتاب" {
		t.Errorf("first stem = %q, want %q: %q would be tried first and could resolve to the wrong root", stems[0], "كتاب", stems[0])
	}
}

func TestALeadingRadicalSurvivesWhenTheEndingIsTheRealAffix(t *testing.T) {
	stems, err := stripAffixes("ورده")
	if err != nil {
		t.Fatalf("stripAffixes: %v", err)
	}
	if stems[0] != "ورد" {
		t.Errorf("first stem = %q, want %q: the waw of ورد is a radical, not the conjunction", stems[0], "ورد")
	}
}

func TestAStackOfCliticsIsPeeledDownToTheStem(t *testing.T) {
	for _, tc := range []struct{ word, stem string }{
		{"وبالصبر", "صبر"},
		{"فبكتابهم", "كتاب"},
		{"للكتاب", "كتاب"},
		{"كتبناها", "كتب"},
		{"سيكتب", "كتب"},
	} {
		stems, err := stripAffixes(tc.word)
		if err != nil {
			t.Errorf("%q: %v", tc.word, err)
			continue
		}
		if !slices.Contains(stems, tc.stem) {
			t.Errorf("%q: stems %q never reach %q, so a word outside the Qur'anic corpus stays unreadable", tc.word, stems, tc.stem)
		}
	}
}

func TestStemsAreOfferedLongestFirstSoTheLeastAggressiveReadingIsTriedFirst(t *testing.T) {
	stems, err := stripAffixes("وبالكتابهم")
	if err != nil {
		t.Fatalf("stripAffixes: %v", err)
	}
	for i, stem := range stems {
		if len([]rune(stem)) < minStem {
			t.Errorf("stem %q is shorter than a root's three radicals", stem)
		}
		if i > 0 && len([]rune(stems[i-1])) < len([]rune(stem)) {
			t.Errorf("stem %q is offered before the longer %q: the store would take the more aggressive reading first and answer with a root the word does not have", stems[i-1], stem)
		}
	}
}

func TestTheFutureParticleIsNotPeeledOffANounThatMerelyBeginsWithSeen(t *testing.T) {
	// سلام is peace; لام is a different word entirely. The future particle only
	// ever sits on an imperfect verb, so it may not come off a noun.
	stems, err := stripAffixes("سلام")
	if err == nil && slices.Contains(stems, "لام") {
		t.Errorf("stems %q include %q, so a noun would be resolved through the root of an unrelated verb", stems, "لام")
	}
}
