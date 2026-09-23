package root

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"slices"
	"testing"
)

// quranResolver resolves against the morphology phase 3 ingested: every root the
// Qur'anic corpus records and every written form it records under one. The seed
// corpus in corpus.json is the worked example a caller outside Wird copies; this
// one is what the app answers from, and the tests that matter run against it.
func quranResolver(t *testing.T) *Resolver {
	t.Helper()
	f, err := os.Open(filepath.Join(testdataDir, "quran.json"))
	if err != nil {
		t.Fatalf("open the Qur'anic corpus: %v", err)
	}
	defer f.Close()
	s, err := LoadMemoryStore(f)
	if err != nil {
		t.Fatalf("load the Qur'anic corpus: %v", err)
	}
	return New(s)
}

// gateBattery is the word list four QA rounds built out of what the pattern rung got
// wrong. An empty root means the corpus does not settle the word and the reader
// must be shown a miss rather than the likeliest-looking reading.
var gateBattery = []struct {
	word string
	root string
}{
	{"ملوك", ""},
	{"مدير", ""},
	{"مريض", ""},
	{"منير", "نور"},
	{"مصري", ""},
	{"مريم", ""},
	{"تونس", ""},
	{"موسى", ""},
	{"قرآن", ""},
	{"صلاة", ""},
	{"حياة", ""},
	{"دعاة", "دعو"},
	{"زكاة", ""},
	{"عادة", ""},
	{"حالة", ""},
	{"طاقة", "طوق"},
	{"غابة", ""},
	{"قامة", ""},
	{"دعاء", "دعو"},
	{"بنات", "بني"},
	{"تلفزيون", ""},
	{"تليفون", ""},
	{"انترنت", ""},
	{"باريس", ""},
	{"امريكا", ""},
	{"تركيا", ""},
	{"بطاطا", ""},
	{"ياباني", ""},
	{"مكتوب", ""},
	{"مسجد", "سجد"},
	{"منصور", ""},
	{"استغفر", "غفر"},
	{"مقهى", ""},
	{"قراء", ""},
	{"وتواصوا", "وصي"},
}

func TestNoWordOfTheBatteryIsServedARootTheCorpusNeverRecordedForIt(t *testing.T) {
	r := quranResolver(t)
	for _, c := range gateBattery {
		got, err := r.Resolve(context.Background(), c.word, nil)
		switch {
		case c.root == "" && err == nil:
			t.Errorf("%s was served the root %q, and a reader learns a root the corpus never recorded for that word", c.word, got.Root.Letters)
		case c.root == "":
			if !errors.Is(err, ErrNoRoot) {
				t.Errorf("%s: want a miss, got %v", c.word, err)
			}
		case err != nil:
			t.Errorf("%s: the corpus records the root %s for this very form and the reader was shown nothing: %v", c.word, c.root, err)
		case got.Root.Letters != c.root:
			t.Errorf("%s was served %q where the corpus records %q", c.word, got.Root.Letters, c.root)
		case got.Method != MethodPattern:
			t.Errorf("%s resolved by %q, so the reader is told an attested corpus fact arrived by some other route", c.word, got.Method)
		}
	}
}

func TestGrowingTheCorpusDoesNotMakeAKnownRootTheAnswerForAWordItNeverAttests(t *testing.T) {
	// Each of these once resolved: a template read three letters out of the word,
	// the store confirmed those letters are a root, and the confirmation was read
	// as an answer. مرض really is a root and مريض really is from it; مصر really is
	// a root and مصري really is from it. The corpus attests neither form, so
	// neither may be asserted, and the rung must miss even with the right-looking
	// letters already on its table.
	r := quranResolver(t)
	for _, word := range []string{"ملوك", "مدير", "مريض", "مصري", "صلاة", "قرآن", "حياة"} {
		miss, ok := missFor(t, r, word)
		if !ok {
			continue
		}
		var offered []string
		for _, c := range miss.Candidates {
			if c.Known {
				offered = append(offered, c.Letters)
			}
		}
		if len(offered) == 0 {
			t.Errorf("%s: the miss offers no reading the corpus knows, so this case proves nothing about asserting one", word)
		}
	}
}

func TestAWordTheQuranNeverUsesStaysAMissHoweverMuchTheCorpusGrows(t *testing.T) {
	// The corpus went from 234 roots to 1,642 and from a handful of forms to
	// nineteen thousand. Growth adds words the corpus attests; it never turns a
	// foreign name into an Arabic word, and a reader must not be handed a root for
	// تلفزيون because the table beneath it got bigger.
	r := quranResolver(t)
	for _, word := range []string{"تلفزيون", "تليفون", "انترنت", "باريس", "امريكا", "تركيا", "بطاطا", "ياباني", "إسطنبول"} {
		got, err := r.Resolve(context.Background(), word, nil)
		if err == nil {
			t.Errorf("%s was served the root %q, so the app teaches a root for a word that has none", word, got.Root.Letters)
			continue
		}
		miss, ok := missFor(t, r, word)
		if ok && len(miss.Candidates) == 0 {
			t.Errorf("%s: the miss names nothing it considered, so the caller cannot report what was tried", word)
		}
	}
}

func TestAFormTwoRootsBothClaimIsAnsweredWithBothRatherThanRefused(t *testing.T) {
	// أسرى is two words in one spelling: the corpus records it under أسر, "to
	// travel by night", and under سري, "captives", and it writes both the same way
	// down to the last diacritic. The morphology does not settle it, so nothing
	// here may either — but refusing to answer is not the same as not deciding.
	// Both readings go on the answer, and a 404 that listed them and served
	// neither told a reader less than the corpus knows.
	got, err := quranResolver(t).Resolve(context.Background(), "أسرى", nil)
	if err != nil {
		t.Fatalf("أسرى: the corpus records two roots for this spelling and the reader was shown neither: %v", err)
	}
	if got.Method != MethodShared {
		t.Errorf("أسرى resolved by %q, so a reader is told one reading was settled when the corpus settles nothing", got.Method)
	}
	for _, want := range []string{"أسر", "سري"} {
		if !slices.ContainsFunc(got.Roots, func(r Root) bool { return r.Letters == want }) {
			t.Errorf("the answer carries %v and drops %q, so a reader is shown one of the two readings as if the other did not exist", got.Roots, want)
		}
	}
	if len(got.Roots) > 0 && got.Root.Letters != got.Roots[0].Letters {
		t.Errorf("root is %q and roots leads with %q, so a caller reading one field and a caller reading the other are told different things",
			got.Root.Letters, got.Roots[0].Letters)
	}
}

func TestADiacritizedSpellingTheAuthorityWritesUnderOneRootIsNotTurnedIntoAHomograph(t *testing.T) {
	// قل is the spelling of both قول and قلل once the diacritics are gone, and the
	// collision belongs to the normaliser rather than to the corpus: قُلْ, 209
	// occurrences and the opening word of Al-Ikhlas, is written under قول and
	// nothing else. A caller who supplies the diacritics has answered the question
	// the normaliser destroyed, and the answer is the one root the authority
	// records — not a list, and never the 404 that used to report both readings as
	// known and then serve neither.
	r := quranResolver(t)
	for _, c := range []struct{ word, root string }{
		{"قُلْ", "قول"},
		{"كُفُوًا", "كفأ"},
	} {
		got, err := r.Resolve(context.Background(), c.word, nil)
		if err != nil {
			t.Errorf("%s: the corpus writes this spelling under %s alone and the reader was shown nothing: %v", c.word, c.root, err)
			continue
		}
		if got.Root.Letters != c.root {
			t.Errorf("%s was served %q where the corpus writes %q for this spelling", c.word, got.Root.Letters, c.root)
		}
		if len(got.Roots) != 0 {
			t.Errorf("%s came back with %v beside it, so a spelling the authority does not leave open is reported as open", c.word, got.Roots)
		}
	}
}

func TestAMorphologyLookupThatFailsIsReportedAsAFailureAndNotAsAWordWithNoRoot(t *testing.T) {
	boom := errors.New("the form-to-root table is unreachable")
	r := New(brokenAttestation{MemoryStore: NewMemoryStore(Corpus{}), err: boom})

	_, err := r.Resolve(context.Background(), "منير", nil)
	if !errors.Is(err, boom) {
		t.Fatalf("want the store failure, got %v", err)
	}
	if errors.Is(err, ErrNoRoot) {
		t.Fatal("a half-read corpus was dressed up as a statement about the word, so an outage reads to every caller as a word with no root")
	}
}

// brokenAttestation answers every rung but the last, which is how an outage of one
// table looks from inside the resolver.
type brokenAttestation struct {
	*MemoryStore
	err error
}

func (s brokenAttestation) Attests(context.Context, string) ([]string, error) {
	return nil, s.err
}
