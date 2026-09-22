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

// NoRootError carries the forms the ladder actually tried, so a 404 can report
// what was considered rather than only that nothing worked.
type NoRootError struct {
	Word       string
	Normalized string
	Candidates []string
}

func (e *NoRootError) Error() string {
	return fmt.Sprintf("jidhr: no root found for %q (considered %s)", e.Word, strings.Join(e.Candidates, ", "))
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

	// Rung five: the templates propose, the store disposes. A template can only say
	// that a word fits a shape — it has no way to know whether the three letters it
	// reads out are a root anyone has ever used, and left to assert on its own it
	// answered صلاة with ص ل ه and ملوك with ل و ك. So the shapes hand over every
	// reading and the corpus is the evidence: exactly one reading it knows is an
	// answer, and none or several is a miss naming all of them. With a corpus of
	// four roots almost everything here is a miss, which is the honest answer for an
	// engine whose corpus has not been ingested yet, and the rung sharpens by itself
	// as roots land rather than by growing another guard.
	//
	// It runs on the normalised word and on nothing else. Running it down the
	// stripped stems as well walks ever more mutilated stems until one happens to
	// fit a wazn, and one always does — تلفزيون peels to تلفز and reads as form V
	// of ل ف ز — so a reading that appears only after peeling is a guess about a
	// guess.
	candidates := matchPattern(res.Normalized)
	var known []string
	for _, c := range candidates {
		_, err := r.store.Root(ctx, c)
		switch {
		case err == nil:
			known = append(known, c)
		case !errors.Is(err, ErrNotFound):
			return Result{}, err
		}
	}
	if len(known) == 1 {
		return r.fromLetters(ctx, res, known[0], MethodPattern, langs)
	}

	// The readings the store could not confirm are the most useful thing a 404 can
	// carry, so they go in the body rather than into the log. A reading that is
	// already there as a stripped stem is not news twice.
	for _, c := range candidates {
		if !slices.Contains(considered, c) {
			considered = append(considered, c)
		}
	}

	return Result{}, &NoRootError{Word: word, Normalized: res.Normalized, Candidates: considered}
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
