package root

import (
	"context"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"slices"
	"testing"
	"unicode"
)

// storeWith seeds a corpus that holds these roots and nothing else, so a test can
// say exactly what the store knows when the pattern rung asks it. The rung answers
// from the corpus now, so "what does the corpus hold" is half of every case here.
func storeWith(letters ...string) *MemoryStore {
	var c Corpus
	for _, l := range letters {
		c.Roots = append(c.Roots, RootRecord{Root: Root{Letters: l, Display: spaced(l)}})
	}
	return NewMemoryStore(c)
}

// knownRoots is a corpus of ordinary Arabic roots, the shape phase 3 will have when
// all 1,651 land. It is what proves this rung still answers: with no roots at all
// every word below would be a miss, and an engine that can only ever 404 is as
// broken as one that invents roots.
var knownRoots = []string{
	"كتب", "صلو", "حيي", "دعو", "زكو", "امن", "قبل", "نصر", "سجد", "ملك",
}

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

func TestTheSameShapeAnswersWhenTheCorpusKnowsTheRootAndMissesWhenItDoesNotButNamesIt(t *testing.T) {
	// This pair is the rung. مكتوب fits maf3uul either way and the letters ك ت ب
	// come out either way; what changes is whether any corpus has ever attested
	// them as a root. The template proposes, and only the store can dispose.
	got, err := New(storeWith(knownRoots...)).Resolve(context.Background(), "مكتوب", nil)
	if err != nil {
		t.Fatalf("a corpus holding ك ت ب still refused مكتوب, so the rung answers nothing at all: %v", err)
	}
	if got.Root.Letters != "كتب" || got.Method != MethodPattern {
		t.Errorf("root = %q by %q, want %q by %q", got.Root.Letters, got.Method, "كتب", MethodPattern)
	}

	_, err = New(storeWith()).Resolve(context.Background(), "مكتوب", nil)
	var miss *NoRootError
	if !errors.As(err, &miss) {
		t.Fatalf("a corpus that has never heard of ك ت ب served مكتوب anyway, so the template asserted a root on no evidence: %v", err)
	}
	if !slices.Contains(miss.Candidates, "كتب") {
		t.Errorf("the miss reports %q and never names كتب, so the caller cannot see the reading that was on the table", miss.Candidates)
	}
}

// tamarbuta is every word the gate's battery answered with the feminine ending
// promoted to a third radical. root is the real root where a reading of the shape
// can reach it, and empty where none can — صلاة is ص ل و and no template reads
// ع و د out of عادة, so the second is a miss with nothing more to say.
var tamarbuta = []struct{ word, root string }{
	{"صلاة", "صلو"},
	{"حياة", "حيي"},
	{"دعاة", "دعو"},
	{"زكاة", "زكو"},
	{"عادة", ""}, // ع و د
	{"حالة", ""}, // ح و ل
	{"طاقة", ""}, // ط و ق
	{"غابة", ""}, // غ ي ب
	{"قامة", ""}, // ق و م
}

func TestAFeminineEndingIsNeverServedAsTheThirdRadicalOfARootNoCorpusHolds(t *testing.T) {
	r := testResolver(t)
	for _, c := range tamarbuta {
		got, err := r.Resolve(context.Background(), c.word, nil)
		if err == nil {
			t.Errorf("%s was served as the root %q, which is its ة normalised to ه and read as a radical", c.word, got.Root.Letters)
			continue
		}
		var miss *NoRootError
		if !errors.As(err, &miss) {
			t.Errorf("%s: want a miss a caller can read, got %v", c.word, err)
			continue
		}
		if c.root != "" && !slices.Contains(miss.Candidates, c.root) {
			t.Errorf("%s: the miss reports %q and never names %q, so the fold threw away the reading that is right", c.word, miss.Candidates, c.root)
		}
	}
}

func TestAFeminineNounReachesItsRealRootOnceTheCorpusHoldsIt(t *testing.T) {
	// The ة fold is the reason صلاة cannot be read off its letters. Widening the
	// candidate set to the readings the fold could have destroyed is what lets the
	// corpus recognise the right one.
	r := New(storeWith(knownRoots...))
	for _, c := range tamarbuta {
		if c.root == "" {
			continue
		}
		got, err := r.Resolve(context.Background(), c.word, nil)
		if err != nil {
			t.Errorf("%s: a corpus holding %s still refused it, so the reading the fold hid was never considered: %v", c.word, c.root, err)
			continue
		}
		if got.Root.Letters != c.root {
			t.Errorf("%s: root = %q, want %q", c.word, got.Root.Letters, c.root)
		}
		if got.Method != MethodPattern {
			t.Errorf("%s: method = %q, want %q", c.word, got.Method, MethodPattern)
		}
	}
}

func TestAWordWhoseFirstLetterIsARadicalMimIsNotServedAsTheTemplatesOwnMim(t *testing.T) {
	// Every one of these was answered with its first letter thrown away: ملوك came
	// back as ل و ك when it is م ل ك, مدير as د ي ر when it is د و ر. maf3al fits
	// all of them and so does the reading where the م is a radical, and no template
	// can tell the two apart — only a corpus can, and none of these readings is in
	// one.
	r := testResolver(t)
	for _, word := range []string{"ملوك", "مدير", "مريض", "مصري", "منير", "مرور"} {
		got, err := r.Resolve(context.Background(), word, nil)
		if err == nil {
			t.Errorf("%s was served as the root %q, which is the word with its own first radical peeled off as if it were the template's م", word, got.Root.Letters)
			continue
		}
		if !errors.Is(err, ErrNoRoot) {
			t.Errorf("%s: want ErrNoRoot, got %v", word, err)
		}
	}
}

func TestAHamzaSeatIsNotServedAsARadicalWawAndReachesTheRealRootWhenTheCorpusHasIt(t *testing.T) {
	// مؤمن normalises to مومن, and the و the rung would call a radical is a seat the
	// normaliser wrote away. The root is ا م ن.
	_, err := testResolver(t).Resolve(context.Background(), "مؤمن", nil)
	var miss *NoRootError
	if !errors.As(err, &miss) {
		t.Fatalf("مؤمن was served a root, and the only evidence for it was a hamza seat the normaliser folded: %v", err)
	}
	if !slices.Contains(miss.Candidates, "امن") {
		t.Errorf("the miss reports %q and never names امن, so the seat's own reading was lost with the fold", miss.Candidates)
	}

	got, err := New(storeWith(knownRoots...)).Resolve(context.Background(), "مؤمن", nil)
	if err != nil {
		t.Fatalf("a corpus holding ا م ن still refused مؤمن: %v", err)
	}
	if got.Root.Letters != "امن" {
		t.Errorf("root = %q, want %q", got.Root.Letters, "امن")
	}
}

func TestAProperNounThatHappensToFitAWaznIsAMissRatherThanARoot(t *testing.T) {
	// A name fits a template as well as a verb does. Nothing in the letters says
	// otherwise, so the only thing that can refuse مريم is a corpus that has never
	// recorded ر ي م as the root of anything.
	r := testResolver(t)
	for _, word := range []string{"مريم", "موسى", "تونس", "سارة", "باريس", "امريكا"} {
		got, err := r.Resolve(context.Background(), word, nil)
		if err == nil {
			t.Errorf("%s was served as the root %q, so the app teaches a root for a name that has none", word, got.Root.Letters)
			continue
		}
		if !errors.Is(err, ErrNoRoot) {
			t.Errorf("%s: want ErrNoRoot, got %v", word, err)
		}
	}
}

func TestTwoReadingsTheCorpusBothKnowsAreReportedRatherThanOneOfThemPicked(t *testing.T) {
	// د ع و and د ع ي are both real roots and دعاء is spelled the same under either.
	// Evidence for two readings is evidence for neither.
	_, err := New(storeWith("دعو", "دعي")).Resolve(context.Background(), "دعاء", nil)
	var miss *NoRootError
	if !errors.As(err, &miss) {
		t.Fatalf("one of two attested readings was served as the answer: %v", err)
	}
	for _, want := range []string{"دعو", "دعي"} {
		if !slices.Contains(miss.Candidates, want) {
			t.Errorf("the miss reports %q and drops %q, so the caller cannot see what it was choosing between", miss.Candidates, want)
		}
	}
}

func TestATemplateThatDoesNotFitProposesNothingRatherThanThreeArbitraryLetters(t *testing.T) {
	if got := matchPattern("اسطنبول"); len(got) != 0 {
		t.Fatalf("a borrowed name was fitted to a template and proposed %q, so the reader is offered a root that does not exist", got)
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
		got := matchPattern(c.stem)
		if !slices.Contains(got, c.want) {
			t.Errorf("%s (%s): the readings are %q and %q is not among them, so a corpus holding that root could never confirm it", c.stem, c.template, got, c.want)
		}
	}
}

func TestAWordWithNoTemplateLettersProposesNothingRatherThanItsOwnThreeLetters(t *testing.T) {
	// تصر, مرد and افق each fit a doubled-root spelling of some template with one
	// letter of the word left over as evidence, which is no evidence at all.
	for _, word := range []string{"هذا", "لكن", "بلي", "تصر", "مرد", "افق"} {
		if got := matchPattern(word); len(got) != 0 {
			t.Errorf("%q proposed %q, but nothing in its spelling is a template — every three-letter particle would get an invented root", word, got)
		}
	}
}

func TestAHollowRootIsAMissBecauseTheSpellingCannotSayWhetherTheMiddleLetterIsWawOrYa(t *testing.T) {
	r := testResolver(t)
	for _, word := range []string{"مقام", "اقام", "مقاس"} {
		got, err := r.Resolve(context.Background(), word, nil)
		if err == nil {
			t.Errorf("%q was read as the root %q: the alef replaced a و or a ي and the spelling does not say which, so half of these answers would be wrong", word, got.Root.Letters)
		}
	}
}

func TestADoubledRootSpelledWithOneLetterIsProposedBesideTheOtherReadingAndNotInsteadOfIt(t *testing.T) {
	// استرد is form X of ر-د-د with the two dals written once. It is spelled exactly
	// like form VIII of س-ر-د, and nothing but the vowels tells the two apart, so
	// both go to the store and the store answers.
	got := matchPattern("استرد")
	for _, want := range []string{"ردد", "سرد"} {
		if !slices.Contains(got, want) {
			t.Errorf("the readings are %q and %q is not among them, so a corpus holding that root could never confirm it", got, want)
		}
	}
	if _, err := testResolver(t).Resolve(context.Background(), "استرد", nil); !errors.Is(err, ErrNoRoot) {
		t.Errorf("استرد resolved although the corpus holds neither reading: %v", err)
	}
}

func TestAFormEightVerbWhoseFirstRadicalMergedIntoThePatternIsAMissAndNotThePatternsTaAsARadical(t *testing.T) {
	// اتصل is و-ص-ل: the waw merged into the ت of افتعل and left no trace of itself.
	// The shape also reads as form I of ت-ص-ل, which is not a root, and a corpus is
	// the only thing that knows that.
	r := testResolver(t)
	for _, word := range []string{"اتصل", "اتفق"} {
		got, err := r.Resolve(context.Background(), word, nil)
		if err == nil {
			t.Errorf("%q was served as the root %q, which is the pattern's own ت promoted to a radical", word, got.Root.Letters)
		}
	}
}

func TestAnAmbiguousShapeReachesTheReaderOnlyAsTheReadingTheCorpusAttests(t *testing.T) {
	// انتصر is form VIII of ن-ص-ر, but it is spelled exactly like form VII of an
	// imaginary ت-ص-ر. The letters choose neither; a corpus that holds ن ص ر and
	// has never heard of ت ص ر chooses for them.
	if _, err := testResolver(t).Resolve(context.Background(), "انتصر", []string{"en"}); !errors.Is(err, ErrNoRoot) {
		t.Fatalf("a word with two possible roots resolved against a corpus holding neither, so the app teaches one of them as a fact: %v", err)
	}

	got, err := New(storeWith(knownRoots...)).Resolve(context.Background(), "انتصر", nil)
	if err != nil {
		t.Fatalf("a corpus holding ن ص ر still refused انتصر, so evidence never breaks a tie: %v", err)
	}
	if got.Root.Letters != "نصر" {
		t.Errorf("root = %q, want %q", got.Root.Letters, "نصر")
	}
}

func TestDiacriticsThatSurvivedTheNormaliserAreAMissRatherThanARootWithAMarkInIt(t *testing.T) {
	if got := matchPattern("مَكْتُوب"); len(got) != 0 {
		t.Fatalf("a vowelled stem was matched anyway and proposed %q, so a short vowel can end up inside a root's letters", got)
	}
}

func TestEveryLetterTheNormaliserFoldsOntoAnotherIsAFoldThisRungCanReadBackwards(t *testing.T) {
	// normalize.json is the contract, and it is the reason this rung is wrong about
	// spelling: a slot can hold a letter the normaliser put there. Any fold added to
	// that file without a reading here silently becomes a new class of invented
	// root, which is how ة→ه produced ص ل ه for صلاة.
	f, err := os.Open(filepath.Join(testdataDir, "normalize.json"))
	if err != nil {
		t.Fatalf("open the normaliser contract: %v", err)
	}
	defer f.Close()
	var contract struct {
		Fold map[string]string `json:"fold"`
	}
	if err := json.NewDecoder(f).Decode(&contract); err != nil {
		t.Fatalf("read the normaliser contract: %v", err)
	}

	for from, to := range contract.Fold {
		src, dst := codePoint(t, from), codePoint(t, to)
		if !unicode.Is(unicode.Arabic, src) || !unicode.Is(unicode.Arabic, dst) {
			continue // the digit folds put nothing in a radical slot
		}
		if dst == 'ا' {
			continue // an alef is never read as a radical at all, in any slot
		}
		if len(radicalReadings(dst, true)) < 2 {
			t.Errorf("the normaliser folds %s onto %s, and a %s standing in a radical slot is read only as itself — the word's real root is then unreachable", from, to, string(dst))
		}
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

func TestARealHamzaRootStaysAmongTheReadingsAndDoesNotBecomeASilentMiss(t *testing.T) {
	// قراء is the plural of قارئ and its root really is ق ر ء, so a rule that simply
	// banned hamza from the last slot would throw away the correct reading of this
	// word to fix دعاء. The rung owes the store both readings, not neither.
	got := matchPattern("قراء")
	for _, want := range []string{"قرء", "قرو"} {
		if !slices.Contains(got, want) {
			t.Errorf("the readings are %q and %q is not among them, so a corpus holding that root could never confirm it", got, want)
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
