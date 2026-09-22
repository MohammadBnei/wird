// Package root resolves an Arabic word to its root and the meanings authored for
// that root. It is a library first: nothing here reads configuration, opens a
// connection, or keeps global state, so a project that is not Wird can use it by
// handing New a Store of its own.
package root

import (
	"context"
	"errors"
	"fmt"
	"slices"
	"strings"
	"unicode"
)

// ErrNotArabic marks input that is not an Arabic word at all. The HTTP layer maps
// it to 400.
var ErrNotArabic = errors.New("jidhr: input is not Arabic")

// ErrNoRoot marks a valid Arabic word whose root no rung could derive. The HTTP
// layer maps it to 404. It is deliberately a different error from ErrNotArabic:
// one answer tells the caller to fix its input, the other tells it the input was
// fine and we simply do not know the word, and a caller cannot act on both with
// the same status code.
var ErrNoRoot = errors.New("jidhr: no root found")

// Candidate is one thing the ladder put on the table: a form it walked, or a
// reading the templates proposed. Known says the corpus holds a root with these
// letters — which is evidence that the reading is a real Arabic root, and never
// evidence that it is the root of the word asked about.
type Candidate struct {
	Letters string `json:"letters"`
	Known   bool   `json:"known"`
}

// NoRootError carries everything the ladder considered, so a 404 reports what was
// on the table rather than only that nothing worked. The candidates the corpus
// knows come first: they are the likelier guesses, and a caller that cannot tell
// them apart from a shape that merely fits reads the first line as the answer.
type NoRootError struct {
	Word       string
	Normalized string
	Candidates []Candidate
}

func (e *NoRootError) Error() string {
	letters := make([]string, 0, len(e.Candidates))
	for _, c := range e.Candidates {
		letters = append(letters, c.Letters)
	}
	return fmt.Sprintf("jidhr: no root found for %q (considered %s)", e.Word, strings.Join(letters, ", "))
}

func (e *NoRootError) Unwrap() error { return ErrNoRoot }

// Resolver answers word-to-root questions against one corpus.
type Resolver struct {
	store Store
}

// New builds a resolver over a store. The store is the only thing a resolver
// knows, which is what lets one process serve several corpora at once.
func New(s Store) *Resolver {
	return &Resolver{store: s}
}

// Resolve walks the ladder — exact form, normalised form, lemma, stripped stem,
// then pattern — and stops at the first rung that hits, naming that rung in
// Result.Method. langs selects which authored meanings come back; an empty langs
// asks for none.
//
// It returns ErrNotArabic for input that is not Arabic and a *NoRootError
// wrapping ErrNoRoot for Arabic the ladder could not resolve. Every other error
// is a failure of the store, never a statement about the word.
func (r *Resolver) Resolve(ctx context.Context, word string, langs []string) (Result, error) {
	word = strings.TrimSpace(word)
	if !containsArabicLetter(word) {
		return Result{}, ErrNotArabic
	}

	res := Result{Input: word, Normalized: word}
	n, err := normalize(word)
	if err != nil && !errors.Is(err, ErrNotFound) {
		return Result{}, err
	}
	if n != "" {
		res.Normalized = n
	}

	considered := []string{word}
	if res.Normalized != word {
		considered = append(considered, res.Normalized)
	}

	entry, method, err := r.lookup(ctx, word, res.Normalized)
	if err == nil {
		return r.fromEntry(ctx, res, entry, method, langs)
	}
	if !errors.Is(err, ErrNotFound) {
		return Result{}, err
	}

	// Rung four. Peeling affixes is what lets a word the Qur'anic corpus never
	// attested resolve at all, so every stem goes back through rungs one to three.
	stems, err := stripAffixes(res.Normalized)
	if err != nil && !errors.Is(err, ErrNotFound) {
		return Result{}, err
	}
	for _, stem := range stems {
		considered = append(considered, stem)
		entry, _, err := r.lookup(ctx, "", stem)
		if err == nil {
			return r.fromEntry(ctx, res, entry, MethodStripped, langs)
		}
		if !errors.Is(err, ErrNotFound) {
			return Result{}, err
		}
	}

	// Rung five proposes and never disposes. A template can say that a word fits a
	// shape, and the store can say that three letters are a root somebody uses.
	// Neither says that this root is the root of THIS word, and reading the second as
	// an answer to the third is what served ملوك as ل و ك and تونس as ا ن س: real
	// classical roots, neither of them the root of the word asked about. So the rung
	// ranks and the caller chooses — a miss carrying every reading, the ones the
	// corpus attests first.
	//
	// ponytail: the ceiling is that the store answers membership while the question is
	// identity, and no guard over the letters closes that gap. Phase 3 ingests the
	// morphology that attests a word form to a root: a Store that can answer
	// Attests(ctx, form, root) turns this ranking back into an answer, reported as
	// MethodPattern, for the one reading it confirms. Until that data lands there is
	// nothing here to assert from.
	//
	// It runs on the normalised word and on nothing else. Running it down the
	// stripped stems as well walks ever more mutilated stems until one happens to
	// fit a wazn, and one always does — تلفزيون peels to تلفز and reads as form V
	// of ل ف ز — so a reading that appears only after peeling is a guess about a
	// guess.
	for _, c := range matchPattern(res.Normalized) {
		if !slices.Contains(considered, c) {
			considered = append(considered, c)
		}
	}

	// ponytail: the corpus sorts the readings it knows from the ones it does not, and
	// nothing here orders the known ones among themselves — ملوك offers لوك and ملك
	// and the letters prefer neither. Attestation is that ordering too.
	var known, shaped []Candidate
	for _, c := range considered {
		_, err := r.store.Root(ctx, c)
		switch {
		case err == nil:
			known = append(known, Candidate{Letters: c, Known: true})
		case errors.Is(err, ErrNotFound):
			shaped = append(shaped, Candidate{Letters: c})
		default:
			return Result{}, err
		}
	}

	return Result{}, &NoRootError{Word: word, Normalized: res.Normalized, Candidates: append(known, shaped...)}
}

// lookup runs rungs one to three against one form and reports which rung hit. An
// empty surface skips rung one, which is right for a stripped stem: a stem is
// something we derived, not something the corpus wrote down.
func (r *Resolver) lookup(ctx context.Context, surface, normalized string) (Entry, Method, error) {
	if surface != "" {
		e, err := r.store.EntryBySurface(ctx, surface)
		if err == nil {
			return e, MethodLexicon, nil
		}
		if !errors.Is(err, ErrNotFound) {
			return Entry{}, "", err
		}
	}

	e, err := r.store.EntryByNormalized(ctx, normalized)
	if err == nil {
		return e, MethodNormalized, nil
	}
	if !errors.Is(err, ErrNotFound) {
		return Entry{}, "", err
	}

	e, err = r.store.EntryByLemma(ctx, normalized)
	if err == nil {
		return e, MethodLemma, nil
	}
	return Entry{}, "", err
}

func (r *Resolver) fromEntry(ctx context.Context, res Result, e Entry, m Method, langs []string) (Result, error) {
	res.Lemma = e.Lemma
	res.Form = e.Form
	return r.fromLetters(ctx, res, e.Root, m, langs)
}

func (r *Resolver) fromLetters(ctx context.Context, res Result, letters string, m Method, langs []string) (Result, error) {
	res.Method = m
	res.Root = Root{Letters: letters, Display: spaced(letters)}

	rec, err := r.store.Root(ctx, letters)
	switch {
	case err == nil:
		res.Root = rec.Root
		res.Quran = rec.Quran
	case !errors.Is(err, ErrNotFound):
		return Result{}, err
	}
	// A root the store has never heard of still has its letters. Dropping it would
	// throw away exactly what the pattern rung exists to produce: the root of a
	// word that is not in our corpus.

	if len(langs) == 0 {
		return res, nil
	}
	meanings, err := r.store.Meanings(ctx, res.Root.Letters, langs)
	if err != nil {
		return Result{}, err
	}
	res.Meanings = meanings
	return res, nil
}

// containsArabicLetter is the boundary between 400 and 404. Diacritics are marks
// and Arabic-Indic digits are digits, so a string holding only those is not a word
// we can be asked about.
func containsArabicLetter(s string) bool {
	for _, r := range s {
		if unicode.IsLetter(r) && unicode.Is(unicode.Arabic, r) {
			return true
		}
	}
	return false
}

// ponytail: display is the letters spaced out and transliteration comes from the
// store. A root the store does not hold gets no transliteration until someone
// authors the letter table it would need.
func spaced(letters string) string {
	return strings.Join(strings.Split(letters, ""), " ")
}
