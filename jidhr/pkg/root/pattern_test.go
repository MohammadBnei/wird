package root

import (
	"context"
	"errors"
	"slices"
	"testing"
)

func TestAWordOutsideTheQuranicCorpusStillYieldsItsRootFromItsShape(t *testing.T) {
	r := testResolver(t)
	got, err := r.Resolve(context.Background(), "مكتوب", []string{"en"})
	if err != nil {
		t.Fatalf("a word no corpus table holds resolved to nothing, so jidhr only works on the Qur'an: %v", err)
	}
	if got.Root.Letters != "كتب" {
		t.Errorf("root letters = %q, want %q", got.Root.Letters, "كتب")
	}
	if got.Method != MethodPattern {
		t.Errorf("method = %q, want %q: a template match is a derivation and must say so", got.Method, MethodPattern)
	}
}

func TestATemplateThatDoesNotFitYieldsNothingRatherThanThreeArbitraryLetters(t *testing.T) {
	_, err := matchPattern("اسطنبول")
	if !errors.Is(err, ErrNotFound) {
		t.Fatalf("a borrowed name was fitted to a template, so the reader is taught a root that does not exist: err = %v", err)
	}
}

func TestEachStandardTemplateIsReadAsItsOwnRootAndNotAsAnotherTemplatesLetters(t *testing.T) {
	cases := []struct {
		stem     string
		want     string
		template string
	}{
		{"كاتب", "كتب", "faa3il, and form III"},
		{"مالك", "ملك", "faa3il where the other reading would make the م a radical"},
		{"اكرم", "كرم", "form IV"},
		{"تعلم", "علم", "form V"},
		{"تكاتب", "كتب", "form VI"},
		{"انكسر", "كسر", "form VII"},
		{"اجتمع", "جمع", "form VIII"},
		{"استخرج", "خرج", "form X"},
		{"مفهوم", "فهم", "maf3uul"},
		{"كتاب", "كتب", "fa33aal"},
		{"مكتب", "كتب", "maf3al"},
		{"استخراج", "خرج", "istif3aal"},
		{"مقابله", "قبل", "mufaa3ala, its ta marbuta already normalised to ha"},
		{"استرداد", "ردد", "istif3aal of a doubled root, whose third radical is written out"},
	}
	for _, c := range cases {
		got, err := matchPattern(c.stem)
		if err != nil {
			t.Errorf("%s (%s): resolved to nothing, so an ordinary Arabic word opens an empty root screen: %v", c.stem, c.template, err)
			continue
		}
		if got != c.want {
			t.Errorf("%s (%s): root = %q, want %q — the reader is taught the wrong three letters", c.stem, c.template, got, c.want)
		}
	}
}

func TestAWordWithNoTemplateLettersIsAMissAndNotItsOwnThreeLettersHandedBack(t *testing.T) {
	// تصر, مرد and افق each fit a doubled-root spelling of some template with one
	// letter of the word left over as evidence, which is no evidence at all.
	for _, word := range []string{"هذا", "لكن", "بلي", "تصر", "مرد", "افق"} {
		got, err := matchPattern(word)
		if !errors.Is(err, ErrNotFound) {
			t.Errorf("%q was reported as the root %q, but nothing in its spelling is a template — every three-letter particle would get an invented root", word, got)
		}
	}
}

func TestAHollowRootIsAMissBecauseTheSpellingCannotSayWhetherTheMiddleLetterIsWawOrYa(t *testing.T) {
	for _, word := range []string{"مقام", "اقام", "مقاس"} {
		got, err := matchPattern(word)
		if !errors.Is(err, ErrNotFound) {
			t.Errorf("%q was read as the root %q: the alef replaced a و or a ي and the spelling does not say which, so half of these answers would be wrong", word, got)
		}
	}
}

func TestADoubledRootSpelledWithOneLetterIsReportedRatherThanReadAsThePatternsOwnLetter(t *testing.T) {
	// استرد is form X of ر-د-د with the two dals written once. It is spelled exactly
	// like form VIII of س-ر-د, and nothing but the vowels tells the two apart.
	_, err := matchPattern("استرد")
	var uncertain *uncertainPatternError
	if !errors.As(err, &uncertain) {
		t.Fatalf("a doubled root was resolved to one reading: err = %v", err)
	}
	for _, want := range []string{"ردد", "سرد"} {
		if !slices.Contains(uncertain.Candidates, want) {
			t.Errorf("the miss does not name %q among its candidates, so a 404 cannot report the reading it declined to pick: %v", want, uncertain.Candidates)
		}
	}

	if got, err := matchPattern("ارتد"); !errors.Is(err, ErrNotFound) {
		t.Errorf("ارتد was read as %q: its ت is the pattern's, not a radical, and ر-ت-د is not a root", got)
	}
}

func TestAFormEightVerbWhoseFirstRadicalMergedIntoThePatternIsAMissAndNotThePatternsTaAsARadical(t *testing.T) {
	// اتصل is و-ص-ل: the waw merged into the ت of افتعل and left no trace of itself.
	for _, word := range []string{"اتصل", "اتفق"} {
		got, err := matchPattern(word)
		if !errors.Is(err, ErrNotFound) {
			t.Errorf("%q was read as the root %q, which is the pattern's own ت promoted to a radical", word, got)
		}
		if got != "" {
			t.Errorf("%q came back with the root %q alongside its miss, so a careless caller uses it anyway", word, got)
		}
	}
}

func TestAShapeThatFitsTwoTemplatesIsAMissCarryingBothReadingsAndNotOneOfThemPicked(t *testing.T) {
	// انتصر is form VIII of ن-ص-ر, but it is spelled exactly like form VII of an
	// imaginary ت-ص-ر, and this rung has nothing that can choose between them.
	_, err := matchPattern("انتصر")
	var uncertain *uncertainPatternError
	if !errors.As(err, &uncertain) {
		t.Fatalf("one of two equally good readings was returned as the answer: err = %v", err)
	}
	for _, want := range []string{"نصر", "تصر"} {
		if !slices.Contains(uncertain.Candidates, want) {
			t.Errorf("the miss does not name %q among its candidates: %v", want, uncertain.Candidates)
		}
	}
}

func TestAnAmbiguousShapeNeverReachesTheReaderAsAResolvedRoot(t *testing.T) {
	r := testResolver(t)
	_, err := r.Resolve(context.Background(), "انتصر", []string{"en"})
	if !errors.Is(err, ErrNoRoot) {
		t.Fatalf("a word with two possible roots resolved anyway, so the app teaches one of them as a fact: %v", err)
	}
}

func TestDiacriticsThatSurvivedTheNormaliserAreAMissRatherThanARootWithAMarkInIt(t *testing.T) {
	got, err := matchPattern("مَكْتُوب")
	if !errors.Is(err, ErrNotFound) {
		t.Fatalf("a vowelled stem was matched anyway and produced %q, so a short vowel can end up inside a root's letters", got)
	}
}

// mamdud lists the words whose فعال shape ends in a hamza that is not a radical,
// beside the root each one really has. Every one of them was once served with a
// fabricated root ending in hamza and method=pattern.
var mamdud = []struct{ word, root string }{
	{"دعاء", "دعو"},
	{"سماء", "سمو"},
	{"نساء", "نسو"},
	{"لقاء", "لقي"},
	{"قضاء", "قضي"},
	{"عطاء", "عطو"},
	{"رجاء", "رجو"},
	{"وفاء", "وفي"},
	{"بناء", "بني"},
	{"شتاء", "شتو"},
	{"غذاء", "غذو"},
}

func TestAMamdudNounIsAMissNamingTheRealRootRatherThanAConfidentRootEndingInHamza(t *testing.T) {
	r := testResolver(t)
	for _, c := range mamdud {
		got, err := r.Resolve(context.Background(), c.word, nil)
		if err == nil {
			t.Errorf("%s was served as the root %q, but its hamza is a weak radical hardened by the alef in front of it, not a letter of the root", c.word, got.Root.Letters)
			continue
		}
		var miss *NoRootError
		if !errors.As(err, &miss) {
			t.Errorf("%s: want a miss a caller can read, got %v", c.word, err)
			continue
		}
		if !slices.Contains(miss.Candidates, c.root) {
			t.Errorf("%s: the miss reports %q and never names %q, so the reader is told nothing was found when the real root was one of two readings on the table", c.word, miss.Candidates, c.root)
		}
	}
}

func TestARealHamzaRootStaysAnAmbiguityAndDoesNotBecomeASilentMiss(t *testing.T) {
	// قراء is the plural of قارئ and its root really is ق ر ء, so a rule that simply
	// banned hamza from the last slot would throw away the correct reading of this
	// word to fix دعاء. The rung owes the caller both readings, not neither.
	_, err := matchPattern("قراء")
	var uncertain *uncertainPatternError
	if !errors.As(err, &uncertain) {
		t.Fatalf("want the two readings of قراء, got %v", err)
	}
	for _, want := range []string{"قرء", "قرو"} {
		if !slices.Contains(uncertain.Candidates, want) {
			t.Errorf("the miss does not name %q among its candidates, so a 404 cannot report the reading it declined to pick: %v", want, uncertain.Candidates)
		}
	}
}

func TestAFemininePluralIsAMissRatherThanARootEndingInTheSuffixesOwnTa(t *testing.T) {
	// The stripper will not peel ات off four letters, because two letters are not a
	// root. The pattern rung then fitted فعال straight over the suffix and read the
	// ت as the third radical. نبات really is ن ب ت, so the shape has two readings
	// and this rung may not pick one of them.
	r := testResolver(t)
	for _, c := range []struct{ word, root string }{
		{"بنات", "بني"},
		{"لغات", "لغو"},
		{"فتات", "فتي"},
		{"جهات", ""}, // و ج ه: no reading of this shape reaches it, so a miss is all we owe
	} {
		got, err := r.Resolve(context.Background(), c.word, nil)
		if err == nil {
			t.Errorf("%s was served as the root %q, which is its feminine plural ending promoted to a radical", c.word, got.Root.Letters)
			continue
		}
		var miss *NoRootError
		if !errors.As(err, &miss) {
			t.Errorf("%s: want a miss a caller can read, got %v", c.word, err)
			continue
		}
		if c.root != "" && !slices.Contains(miss.Candidates, c.root) {
			t.Errorf("%s: the miss reports %q and never names %q", c.word, miss.Candidates, c.root)
		}
	}
}

func TestAWordWithNoAffixesToPeelKeepsItsPatternReading(t *testing.T) {
	// The rule that stops the ladder walking down the stems until a wazn fits must
	// not also silence the rung on the word it was handed.
	r := testResolver(t)
	got, err := r.Resolve(context.Background(), "مكتوب", nil)
	if err != nil {
		t.Fatalf("an ordinary maf3uul stopped resolving, so the pattern rung now refuses everything: %v", err)
	}
	if got.Root.Letters != "كتب" || got.Method != MethodPattern {
		t.Errorf("root = %q by %q, want %q by %q", got.Root.Letters, got.Method, "كتب", MethodPattern)
	}
}
