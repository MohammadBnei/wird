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
// say exactly what the store knows when the pattern rung asks it. The seed corpus
// testResolver loads is the other half of that: it holds the real roots of the
// battery below and the traps beside them, which is the shape phase 3 ships.
func storeWith(letters ...string) *MemoryStore {
	var c Corpus
	for _, l := range letters {
		c.Roots = append(c.Roots, RootRecord{Root: Root{Letters: l, Display: spaced(l)}})
	}
	return NewMemoryStore(c)
}

// missFor resolves a word the pattern rung must never answer for and returns what
// it offered instead. A template can say that a word fits a shape and a corpus can
// say that three letters are a root somebody uses; neither can say that those
// letters are the root of this word, so every word here comes back as a miss
// carrying its readings.
func missFor(t *testing.T, r *Resolver, word string) (*NoRootError, bool) {
	t.Helper()
	got, err := r.Resolve(context.Background(), word, nil)
	if err == nil {
		t.Errorf("%s was served as the root %q by %q, on no evidence but the shape of the word", word, got.Root.Letters, got.Method)
		return nil, false
	}
	var miss *NoRootError
	if !errors.As(err, &miss) {
		t.Errorf("%s: want a miss a caller can read, got %v", word, err)
		return nil, false
	}
	return miss, true
}

// offered says what the miss reported about these letters: whether they reached the
// caller at all, and whether they were marked as a root the corpus knows.
func offered(miss *NoRootError, letters string) (Candidate, bool) {
	i := slices.IndexFunc(miss.Candidates, func(c Candidate) bool { return c.Letters == letters })
	if i < 0 {
		return Candidate{}, false
	}
	return miss.Candidates[i], true
}

// battery is the word list the gate measured the old assert path against, beside
// the root each word really has. want is empty where no reading of any template can
// reach that root, and the word is here anyway because it must not be answered with
// the reading that does fit.
var battery = []struct{ word, want, why string }{
	{"ملوك", "ملك", "the م is the first radical and is spelled like maf3al's prefix"},
	{"مريض", "مرض", "the م is the first radical and the ي is a long vowel"},
	{"مكتوب", "كتب", "maf3uul, where the م really is the template's"},
	{"مسجد", "سجد", "maf3al, where the م really is the template's"},
	{"صلاة", "صلو", "the ة the normaliser wrote as ه is no radical at all"},
	{"دعاء", "دعو", "a mamduud hamza standing where the weak radical was"},
	{"مدير", "", "د و ر: the hollow's و is not in the spelling"},
	{"منير", "", "ن و ر: the hollow's و is not in the spelling"},
	{"قرآن", "", "ق ر ء: the hamza is not in the spelling that reaches this rung"},
	{"مصري", "", "a nisba built on a place name, which has no root"},
	{"مريم", "", "a name"},
	{"تونس", "", "a name"},
	{"موسى", "", "a name"},
}

func TestNoWordIsServedARootItsShapeMerelyFitsEvenWhenTheCorpusKnowsThoseLetters(t *testing.T) {
	// This is the whole rung in one test. Seven of these words were answered by the
	// old assert path, and every wrong answer it gave — ل و ك for ملوك, ا ن س for
	// تونس, و س ي for موسى — is a real classical root that the corpus below holds.
	// The store was being asked whether لوك is a root when the question was whether
	// لوك is the root of ملوك, and it cannot tell the two apart.
	r := testResolver(t)
	for _, c := range battery {
		miss, ok := missFor(t, r, c.word)
		if !ok || c.want == "" {
			continue
		}
		got, on := offered(miss, c.want)
		if !on {
			t.Errorf("%s (%s): the miss reports %v and never names %s, so the reader is offered every reading but the right one", c.word, c.why, miss.Candidates, c.want)
			continue
		}
		if !got.Known {
			t.Errorf("%s: %s reached the caller unmarked although the corpus holds it, so it sits among the shapes that merely fit", c.word, c.want)
		}
	}
}

func TestAMissPutsTheReadingsTheCorpusKnowsAboveTheOnesThatMerelyFitTheShape(t *testing.T) {
	// The caller is handed a list instead of an answer, so the list carries the
	// difference between a reading some corpus has attested and three letters that
	// only fit a shape. Unranked and unmarked, the first line reads as the verdict.
	miss, ok := missFor(t, testResolver(t), "ملوك")
	if !ok {
		return
	}

	var known, shaped int
	for i, c := range miss.Candidates {
		if c.Known {
			known++
			if shaped > 0 {
				t.Errorf("%s is a reading the corpus knows and sits at %d, below %d readings that only fit the shape: %v", c.Letters, i, shaped, miss.Candidates)
			}
			continue
		}
		shaped++
	}
	if known == 0 || shaped == 0 {
		t.Fatalf("the miss reports %d attested and %d unattested readings, so the ranking it is meant to show cannot be read from it: %v", known, shaped, miss.Candidates)
	}
}

func TestTheReadingThatKeepsAWordsOwnFirstLetterIsProposedBesideTheOneThatPeelsIt(t *testing.T) {
	// ملوك is م ل ك and مريض is م ر ض: the م is the first radical, not the
	// prefix it is spelled like. The rung read every fixed template letter as
	// necessarily the template's, so the right reading was never even on the table —
	// and a corpus that holds ل و ك, a real root meaning to chew, cannot catch that.
	r := testResolver(t)
	for _, c := range []struct{ word, radical, affixal string }{
		{"ملوك", "ملك", "لوك"},
		{"مريض", "مرض", "ريض"},
	} {
		miss, ok := missFor(t, r, c.word)
		if !ok {
			continue
		}
		if _, on := offered(miss, c.radical); !on {
			t.Errorf("%s: the miss reports %v and never names %s, so the reading where the first letter is a radical is missing from the word's own candidate set", c.word, miss.Candidates, c.radical)
		}
		if _, on := offered(miss, c.affixal); !on {
			t.Errorf("%s: the miss reports %v and never names %s, so completing the rule cost it the reading it already had", c.word, miss.Candidates, c.affixal)
		}
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

func TestAFeminineEndingIsNeverServedAsTheThirdRadicalAndTheRootItHidesIsOffered(t *testing.T) {
	// The ة fold is the reason صلاة cannot be read off its letters: ص ل ه is what
	// the spelling says and ص ل و is what the word is. Widening the readings to what
	// the fold could have destroyed is what puts the right one in front of the caller,
	// and the corpus holding ع و د is what proves the empty rows are unreachable
	// rather than merely absent.
	r := testResolver(t)
	for _, c := range tamarbuta {
		miss, ok := missFor(t, r, c.word)
		if !ok {
			continue
		}
		if c.root == "" {
			if got, on := offered(miss, c.root); on && got.Known {
				t.Errorf("%s: %v names a root the shape cannot reach", c.word, miss.Candidates)
			}
			continue
		}
		got, on := offered(miss, c.root)
		if !on {
			t.Errorf("%s: the miss reports %v and never names %s, so the fold threw away the reading that is right", c.word, miss.Candidates, c.root)
			continue
		}
		if !got.Known {
			t.Errorf("%s: %s reached the caller unmarked although the corpus holds it", c.word, c.root)
		}
	}
}

func TestAHamzaSeatIsNotServedAsARadicalWawAndTheSeatsOwnReadingIsMarkedAttested(t *testing.T) {
	// مؤمن normalises to مومن, and the و a template would call a radical is a seat
	// the normaliser wrote away. The root is ا م ن, and the corpus holds it.
	miss, ok := missFor(t, testResolver(t), "مؤمن")
	if !ok {
		return
	}
	got, on := offered(miss, "امن")
	if !on {
		t.Fatalf("the miss reports %v and never names امن, so the seat's own reading was lost with the fold", miss.Candidates)
	}
	if !got.Known {
		t.Error("امن reached the caller unmarked although the corpus holds it, so the reading that is right is indistinguishable from the two that are not")
	}
}

func TestTwoReadingsTheCorpusBothKnowsAreBothReportedRatherThanOneOfThemPicked(t *testing.T) {
	// د ع و and د ع ي are both real roots and دعاء is spelled the same under
	// either. Evidence for two readings is evidence for neither.
	miss, ok := missFor(t, testResolver(t), "دعاء")
	if !ok {
		return
	}
	for _, want := range []string{"دعو", "دعي"} {
		got, on := offered(miss, want)
		if !on {
			t.Errorf("the miss reports %v and drops %s, so the caller cannot see what it was choosing between", miss.Candidates, want)
			continue
		}
		if !got.Known {
			t.Errorf("%s reached the caller unmarked although the corpus holds it", want)
		}
	}
}

func TestACorpusChangesWhereAReadingSitsAndNeverWhetherItIsTheAnswer(t *testing.T) {
	// مكتوب fits maf3uul either way and ك ت ب comes out either way. What a corpus
	// holding that root changes is that the reading is marked attested and ranked
	// first; what it must never change is the verdict, because no corpus of roots can
	// say that ك ت ب is the root of this word rather than a root that exists.
	rich, ok := missFor(t, testResolver(t), "مكتوب")
	if !ok {
		return
	}
	got, on := offered(rich, "كتب")
	if !on || !got.Known {
		t.Fatalf("a corpus holding ك ت ب reported %v: the reading is missing or unmarked, so the caller cannot tell it from a shape that fits", rich.Candidates)
	}
	if rich.Candidates[0].Letters != "كتب" {
		t.Errorf("the attested reading sits behind %s, so the best guess is not the first one a caller reads", rich.Candidates[0].Letters)
	}

	bare, ok := missFor(t, New(storeWith()), "مكتوب")
	if !ok {
		return
	}
	got, on = offered(bare, "كتب")
	if !on {
		t.Fatalf("a corpus that has never heard of ك ت ب reported %v, so an empty corpus loses the reading instead of ranking it last", bare.Candidates)
	}
	if got.Known {
		t.Error("ك ت ب came back marked attested against a corpus that holds no roots at all, so the mark says nothing")
	}
}

func TestAnAmbiguousShapeIsRankedByTheCorpusAndStillAnsweredByNeitherReading(t *testing.T) {
	// انتصر is form VIII of ن-ص-ر, but it is spelled exactly like form VII of an
	// imaginary ت-ص-ر. The corpus holds ن ص ر and has never heard of ت ص ر, which
	// ranks the two and does not decide between them.
	miss, ok := missFor(t, testResolver(t), "انتصر")
	if !ok {
		return
	}
	if miss.Candidates[0].Letters != "نصر" || !miss.Candidates[0].Known {
		t.Errorf("the miss opens with %v, so the reading the corpus attests is not the one the caller reads first", miss.Candidates)
	}
	if _, on := offered(miss, "تصر"); !on {
		t.Errorf("the miss reports %v and drops تصر, so the caller cannot see the other reading of the shape", miss.Candidates)
	}
}

func TestAHollowRootIsUnreachableFromTheSpellingAndIsNotDressedUpAsOneThatIsNot(t *testing.T) {
	// The alef of مقام replaced a و or a ي and the spelling does not say which, so
	// ق و م cannot be read out of it — the corpus holds that root and it still cannot
	// be reached. What the shape does yield is مقم, and offering that as the answer
	// would be wrong for half of these words.
	r := testResolver(t)
	for _, c := range []struct{ word, real string }{
		{"مقام", "قوم"},
		{"اقام", "قوم"},
		{"مقاس", "قيس"},
	} {
		miss, ok := missFor(t, r, c.word)
		if !ok {
			continue
		}
		if _, on := offered(miss, c.real); on {
			t.Errorf("%s: %v names %s, so a weak radical the spelling never carried was read out of it anyway", c.word, miss.Candidates, c.real)
		}
	}
}

func TestAProperNounThatHappensToFitAWaznIsAMissRatherThanARoot(t *testing.T) {
	// A name fits a template as well as a verb does, and the readings a name yields
	// are ordinary roots: تونس reads as ا ن س and موسى as و س ي, both of which
	// this corpus holds. Nothing in the letters and nothing in a list of roots can
	// refuse them; only a record of which words are built from which root can.
	r := testResolver(t)
	for _, word := range []string{"مريم", "موسى", "تونس", "سارة", "باريس", "امريكا"} {
		missFor(t, r, word)
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

func TestADoubledRootSpelledWithOneLetterIsProposedBesideTheOtherReadingAndNotInsteadOfIt(t *testing.T) {
	// استرد is form X of ر-د-د with the two dals written once. It is spelled exactly
	// like form VIII of س-ر-د, and nothing but the vowels tells the two apart, so
	// both go to the store and the store ranks them.
	got := matchPattern("استرد")
	for _, want := range []string{"ردد", "سرد"} {
		if !slices.Contains(got, want) {
			t.Errorf("the readings are %q and %q is not among them, so a corpus holding that root could never confirm it", got, want)
		}
	}
}

func TestAFormEightVerbWhoseFirstRadicalMergedIntoThePatternIsAMissAndNotThePatternsTaAsARadical(t *testing.T) {
	// اتصل is و-ص-ل: the waw merged into the ت of افتعل and left no trace of itself,
	// so the root is not in the letters at all. The shape also reads as form I of
	// ت-ص-ل, and the reader may be shown that reading but never told it is the root.
	r := testResolver(t)
	for _, word := range []string{"اتصل", "اتفق"} {
		missFor(t, r, word)
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
		miss, ok := missFor(t, r, c.word)
		if !ok {
			continue
		}
		if _, on := offered(miss, c.root); !on {
			t.Errorf("%s: the miss reports %v and never names %s, so the reader is told nothing was found when the real root was one of two readings on the table", c.word, miss.Candidates, c.root)
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
		miss, ok := missFor(t, r, c.word)
		if !ok || c.root == "" {
			continue
		}
		if _, on := offered(miss, c.root); !on {
			t.Errorf("%s: the miss reports %v and never names %s", c.word, miss.Candidates, c.root)
		}
	}
}
