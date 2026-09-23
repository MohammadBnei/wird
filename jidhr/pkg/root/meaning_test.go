package root

import (
	"context"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"testing"
)

// quranCorpus is the corpus rootd serves: server/cmd/jidhrcorpus writes it out of
// app/assets/corpus.db, so these tests measure the data a caller outside Wird
// actually receives rather than a fixture written to agree with them.
func quranCorpus(t *testing.T) *MemoryStore {
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
	return s
}

const (
	sensedWord = "صَبَرُوا۟" // attested, and somebody wrote its root's sense
	silentRoot = "وصي"       // attested, and the sense check refused to write one
)

func TestTheCorpusOffersOnlyTheLanguagesItsMeaningsAreWrittenIn(t *testing.T) {
	s := quranCorpus(t)

	got := s.Languages()
	if len(got) != 2 || got[0] != "en" || got[1] != "fr" {
		t.Fatalf("languages = %v, want [en fr]: rootd answers in these when a caller names none, so a language listed here that nobody wrote is a caller asking for silence", got)
	}

	// Arabic is the language the documentation used to promise. Asking for it is
	// answered with nothing, never with an error, and never with English wearing an
	// ar label.
	unasked, err := s.Meanings(context.Background(), "صبر", []string{"ar"})
	if err != nil {
		t.Fatalf("asking for an unauthored language is an error rather than an empty answer: %v", err)
	}
	if len(unasked) != 0 {
		t.Errorf("Arabic came back as %v, so a language nobody authored is served under its name", unasked)
	}
}

func TestNoMeaningInTheCorpusCarriesAPoeticRegisterNobodyWrote(t *testing.T) {
	for letters, by := range quranCorpus(t).meanings {
		for lang, m := range by {
			body, err := json.Marshal(m)
			if err != nil {
				t.Fatalf("marshal %s %s: %v", letters, lang, err)
			}
			var fields map[string]any
			if err := json.Unmarshal(body, &fields); err != nil {
				t.Fatalf("unmarshal %s %s: %v", letters, lang, err)
			}
			if _, present := fields["poetic"]; present {
				t.Fatalf("%s %s serialises a poetic register: %s — the poetic voice is unwritten, and a blank one renders as a section with nothing in it", letters, lang, body)
			}
		}
	}
}

func TestARootWithNothingWrittenAnswersTheRootWhereAWordWithNoRootIsAMiss(t *testing.T) {
	r := New(quranCorpus(t))
	langs := []string{"en", "fr"}

	sensed, err := r.Resolve(context.Background(), sensedWord, langs)
	if err != nil {
		t.Fatalf("%s: %v", sensedWord, err)
	}
	if sensed.Meanings["en"].Plain == "" || sensed.Meanings["fr"].Plain == "" {
		t.Errorf("%s resolved to %s with meanings %v, and the sense written for that root never reached the caller", sensedWord, sensed.Root.Letters, sensed.Meanings)
	}

	// 1,119 of the 1,642 roots ship no sense on purpose. The word still resolves:
	// the root is a corpus fact, the meaning is prose nobody has written, and a
	// caller must be able to tell that from a word that has no root at all.
	silent, err := r.Resolve(context.Background(), "وَتَوَاصَوْا۟", langs)
	if err != nil {
		t.Fatalf("a root with no sense written answered an error rather than the root: %v", err)
	}
	if silent.Root.Letters != silentRoot {
		t.Fatalf("root = %q, want %q", silent.Root.Letters, silentRoot)
	}
	if len(silent.Meanings) != 0 {
		t.Errorf("meanings = %v, want none: nothing was written for %s and an invented one is the worst thing this could serve", silent.Meanings, silentRoot)
	}

	if _, err := r.Resolve(context.Background(), "إسطنبول", langs); !errors.Is(err, ErrNoRoot) {
		t.Errorf("a word with no root answered %v, so a caller cannot tell it apart from a root with nothing written", err)
	}
}
