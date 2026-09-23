package root

import (
	"context"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"testing"
)

// The fixtures live at jidhr/testdata rather than beside this package, because the
// Dart normaliser on the device reads normalize.json from there too.
const testdataDir = "../../testdata"

func testResolver(t *testing.T) *Resolver {
	t.Helper()
	f, err := os.Open(filepath.Join(testdataDir, "corpus.json"))
	if err != nil {
		t.Fatalf("open the seed corpus: %v", err)
	}
	defer f.Close()
	s, err := LoadMemoryStore(f)
	if err != nil {
		t.Fatalf("load the seed corpus: %v", err)
	}
	return New(s)
}

func TestANonArabicStringIsBadInputRatherThanAWordWeDoNotKnow(t *testing.T) {
	r := testResolver(t)
	for _, word := range []string{"hello", "", "   ", "١٢٣"} {
		_, err := r.Resolve(context.Background(), word, nil)
		if !errors.Is(err, ErrNotArabic) {
			t.Errorf("%q: want ErrNotArabic, got %v", word, err)
		}
		if errors.Is(err, ErrNoRoot) {
			t.Errorf("%q: reported as an unresolvable Arabic word, so the caller is told 404 and never learns to fix its input", word)
		}
	}
}

func TestABorrowedNameWithNoRootIsAMissAndNotAnInventedRoot(t *testing.T) {
	r := testResolver(t)
	_, err := r.Resolve(context.Background(), "إسطنبول", nil)
	if !errors.Is(err, ErrNoRoot) {
		t.Fatalf("want ErrNoRoot, got %v", err)
	}
	if errors.Is(err, ErrNotArabic) {
		t.Fatal("reported as bad input, so the caller is told to fix a word that is perfectly good Arabic")
	}
	var miss *NoRootError
	if !errors.As(err, &miss) {
		t.Fatalf("want a *NoRootError carrying what was considered, got %T", err)
	}
	if len(miss.Candidates) == 0 {
		t.Error("the miss names nothing it considered, so a 404 cannot report what was tried")
	}
}

func TestAnExactQuranicSpellingResolvesFromTheLexicon(t *testing.T) {
	r := testResolver(t)
	got, err := r.Resolve(context.Background(), "وَتَوَاصَوْا", []string{"en", "ar"})
	if err != nil {
		t.Fatalf("resolve: %v", err)
	}
	if got.Method != MethodLexicon {
		t.Errorf("method = %q, want %q: an attested form must not be reported as a derivation", got.Method, MethodLexicon)
	}
	if got.Root.Letters != "وصي" {
		t.Errorf("root letters = %q, want %q", got.Root.Letters, "وصي")
	}
	if got.Root.Display != "و ص ي" {
		t.Errorf("root display = %q, want %q", got.Root.Display, "و ص ي")
	}
	if got.Lemma != "تَوَاصَى" {
		t.Errorf("lemma = %q, want %q", got.Lemma, "تَوَاصَى")
	}
	if got.Quran == nil || got.Quran.Occurrences != 32 {
		t.Errorf("quran = %+v, want 32 occurrences", got.Quran)
	}
	if _, ok := got.Meanings["en"]; !ok {
		t.Error("no English meaning, so the reader opens a root with nothing to read")
	}
	if _, ok := got.Meanings["ar"]; !ok {
		t.Error("no Arabic meaning, so the reader opens a root with nothing to read")
	}
}

func TestAStoreFailureIsReportedAsAFailureAndNotAsAWordWithNoRoot(t *testing.T) {
	boom := errors.New("the corpus is unreachable")
	r := New(failingStore{err: boom})

	_, err := r.Resolve(context.Background(), "وَتَوَاصَوْا", nil)
	if !errors.Is(err, boom) {
		t.Fatalf("want the store failure, got %v", err)
	}
	if errors.Is(err, ErrNoRoot) || errors.Is(err, ErrNotArabic) {
		t.Fatal("a broken corpus was dressed up as a statement about the word, so an outage reads to every caller as a missing root")
	}
}

func TestARootOutsideTheQuranCarriesNoQuranStatistic(t *testing.T) {
	r := testResolver(t)
	got, err := r.Resolve(context.Background(), "بَرمَجَة", []string{"en"})
	if err != nil {
		t.Fatalf("resolve: %v", err)
	}
	if got.Quran != nil {
		t.Errorf("quran = %+v, want absent: a caller asking about an ordinary Arabic word is handed a Qur'an count it never asked for", got.Quran)
	}
	if _, present := marshalFields(t, got)["quran"]; present {
		t.Error("the response still carries a quran object, so a client cannot tell absent from zero")
	}
}

func TestAnUnwrittenPoeticMeaningIsAbsentRatherThanEmpty(t *testing.T) {
	r := testResolver(t)
	got, err := r.Resolve(context.Background(), "صَبَرُوا", []string{"ar"})
	if err != nil {
		t.Fatalf("resolve: %v", err)
	}
	if _, present := marshalFields(t, got.Meanings["ar"])["poetic"]; present {
		t.Error("an unauthored poetic register serialises as an empty string, so the screen renders a blank section instead of no section")
	}
}

func TestAskingForOneLanguageDoesNotReturnTheOthers(t *testing.T) {
	r := testResolver(t)
	got, err := r.Resolve(context.Background(), "وَتَوَاصَوْا", []string{"en", "fr"})
	if err != nil {
		t.Fatalf("resolve: %v", err)
	}
	if _, ok := got.Meanings["ar"]; ok {
		t.Error("Arabic came back unasked for, so an English-only client renders text it cannot lay out")
	}
	if _, ok := got.Meanings["fr"]; ok {
		t.Error("French came back although nothing is authored in it")
	}
	if _, ok := got.Meanings["en"]; !ok {
		t.Error("the one language that was asked for is missing")
	}
}

func TestTheRootResponseKeepsItsPublishedFieldNames(t *testing.T) {
	got, err := json.Marshal(Result{
		Input:      "وَتَوَاصَوْا",
		Normalized: "وتواصوا",
		Root:       Root{Letters: "وصي", Display: "و ص ي", Translit: "w-ṣ-y"},
		Lemma:      "تَوَاصَى",
		Form:       "VI · perfect · 3rd m. pl.",
		Method:     MethodLexicon,
		Quran:      &QuranStats{Occurrences: 32},
		Meanings:   map[string]Meaning{"en": {Plain: "to enjoin", Poetic: "a rope passed on"}},
	})
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	const want = `{"input":"وَتَوَاصَوْا","normalized":"وتواصوا","root":{"letters":"وصي","display":"و ص ي","translit":"w-ṣ-y"},"lemma":"تَوَاصَى","form":"VI · perfect · 3rd m. pl.","method":"lexicon","quran":{"occurrences":32},"meanings":{"en":{"plain":"to enjoin","poetic":"a rope passed on"}}}`
	if string(got) != want {
		t.Errorf("the published response shape changed, so every caller parsing it breaks\n got: %s\nwant: %s", got, want)
	}
}

func marshalFields(t *testing.T, v any) map[string]json.RawMessage {
	t.Helper()
	body, err := json.Marshal(v)
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	var fields map[string]json.RawMessage
	if err := json.Unmarshal(body, &fields); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	return fields
}

// failingStore stands in for a corpus that is down rather than one that is empty.
type failingStore struct{ err error }

func (s failingStore) EntryBySurface(context.Context, string) (Entry, error) {
	return Entry{}, s.err
}

func (s failingStore) EntryByNormalized(context.Context, string) (Entry, error) {
	return Entry{}, s.err
}

func (s failingStore) EntryByLemma(context.Context, string) (Entry, error) {
	return Entry{}, s.err
}

func (s failingStore) Attests(context.Context, string) ([]string, error) {
	return nil, s.err
}

func (s failingStore) AttestsSurface(context.Context, string) ([]string, error) {
	return nil, s.err
}

func (s failingStore) Root(context.Context, string) (RootRecord, error) {
	return RootRecord{}, s.err
}

func (s failingStore) Meanings(context.Context, string, []string) (map[string]Meaning, error) {
	return nil, s.err
}

func TestABorrowedNameIsAMissRatherThanARootFoundByPeelingItUntilAWaznFits(t *testing.T) {
	// Each of these once resolved: the ladder ran the pattern rung over every
	// stripped stem and took the first stem that happened to fit a template, so
	// تلفزيون lost its ت and its ون and came back as form V of ل ف ز, and ياباني
	// came back as ب ن ي — "to build" — for the nisba of Japan.
	r := testResolver(t)
	for _, word := range []string{
		"تلفزيون", "تليفون", "انترنت", "باريس",
		"امريكا", "تركيا", "بطاطا", "ياباني", "إسطنبول",
	} {
		got, err := r.Resolve(context.Background(), word, nil)
		if err == nil {
			t.Errorf("%s was served as the root %q, so the app teaches a root for a word that has none", word, got.Root.Letters)
			continue
		}
		if !errors.Is(err, ErrNoRoot) {
			t.Errorf("%s: want ErrNoRoot, got %v", word, err)
		}
		if errors.Is(err, ErrNotArabic) {
			t.Errorf("%s: reported as bad input, so the caller is told to fix a word that is perfectly good Arabic", word)
		}
	}
}

func TestAMissNamesTheReadingsThePatternRungDeclinedToChooseBetween(t *testing.T) {
	miss, ok := missFor(t, testResolver(t), "دعاء")
	if !ok {
		return
	}
	for _, want := range []string{"دعو", "دعي", "دعء"} {
		if _, on := offered(miss, want); !on {
			t.Errorf("the 404 reports %v and drops %q, so the caller is told nothing was found when three readings were on the table and one of them is right", miss.Candidates, want)
		}
	}
}
