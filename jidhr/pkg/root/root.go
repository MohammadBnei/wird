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

// ErrNoRoot marks a valid Arabic word we have no root to give for — because no
// rung could derive one, or because the corpus itself records the word with no
// root. The HTTP layer maps it to 404. It is deliberately a different error from
// ErrNotArabic: one answer tells the caller to fix its input, the other tells it
// the input was fine, and a caller cannot act on both with the same status code.
// NoRootError.Rootless tells the two kinds of 404 apart.
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
	// Rootless says the corpus recorded this spelling with no root, rather than the
	// ladder having failed to find one. They are different answers: مِنْ is a
	// particle the morphology deliberately gives no root, باريس is a word we have
	// never seen, and a caller told "no root could be derived" for both cannot tell
	// them apart. Candidates is empty when it is set, because nothing was
	// considered — the authority answered.
	Rootless   bool
	Candidates []Candidate
}

func (e *NoRootError) Error() string {
	if e.Rootless {
		return fmt.Sprintf("jidhr: the corpus records %q with no root", e.Word)
	}
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
	if !IsArabicWord(word) {
		return Result{}, ErrNotArabic
	}

	res := Result{Input: word, Normalized: word}
	if n := key(word); n != "" {
		res.Normalized = n
	}

	considered := []string{word}
	if res.Normalized != word {
		considered = append(considered, res.Normalized)
	}

	// The morphology records 1,189 spellings — مِنْ, هُوَ, ٱلَّذِينَ, عَلَيْهِمْ — under no
	// root, deliberately: a particle comes from no triliteral root. That is the
	// authority answering about the very word the caller handed us, and it is
	// settled here, above every rung, because every rung below overrules it. Once
	// the diacritics are gone مِنْ is مَنَّ and عَلَيْهِمْ is عَـٰلِيَهُمْ, so the attestation
	// rung served منن and علو — roots the authority denies these words — as facts,
	// with nothing in the answer to say so.
	//
	// A spelling the corpus also writes under a root is not settled by this and
	// falls through: يَحْيَىٰ is the name, which has no root, and also "he lives",
	// which is حيي, and the corpus writes the two identically, diacritics and all.
	surfaceRootless, err := r.store.RootlessSurface(ctx, word)
	if err != nil {
		return Result{}, err
	}
	if surfaceRootless {
		exact, err := r.store.AttestsSurface(ctx, word)
		if err != nil {
			return Result{}, err
		}
		if len(exact) == 0 {
			return Result{}, &NoRootError{Word: word, Normalized: res.Normalized, Rootless: true}
		}
	}

	// Whether the normalised key is one a rootless word shares. The collision lives
	// in the key and not in the corpus, so this rides on every answer the key
	// produced and on no answer the caller's own diacritics settled.
	keyRootless, err := r.store.Rootless(ctx, res.Normalized)
	if err != nil {
		return Result{}, err
	}

	entry, method, err := r.lookup(ctx, word, res.Normalized)
	if err == nil {
		res.Rootless = keyRootless && method != MethodLexicon
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
			res.Rootless = keyRootless
			return r.fromEntry(ctx, res, entry, MethodStripped, langs)
		}
		if !errors.Is(err, ErrNotFound) {
			return Result{}, err
		}
	}

	// Rung five, and the only thing it asserts from is attestation: the corpus
	// having recorded this very form under a root. A template can say that a word
	// fits a shape and the store can say that لوك is a root; neither says that لوك
	// is the root of ملوك, and reading the second out of the first is what once
	// served ملوك as ل و ك and تونس as ا ن س — real classical roots, neither of them
	// the root of the word asked about. A form the corpus never wrote down stays a
	// miss however neatly it fits a wazn, which is why growing the corpus does not
	// make باريس answerable.
	//
	// Where attestation and the templates disagree, attestation wins: طاقة is
	// ط و ق and no shape reaches that, so a rung answering only readings a template
	// proposed would throw away a corpus fact to keep a tidier story. Two roots
	// means the corpus itself does not settle the form, and a coin toss between two
	// attested readings is still a guess, so both go on the table instead.
	attested, err := r.store.Attests(ctx, res.Normalized)
	if err != nil {
		return Result{}, err
	}
	if len(attested) == 0 && keyRootless {
		// The corpus knows this spelling and gives it no root. That is an answer and
		// not the miss that says we have never met the word.
		return Result{}, &NoRootError{Word: word, Normalized: res.Normalized, Rootless: true}
	}
	if len(attested) == 1 && !keyRootless {
		return r.fromLetters(ctx, res, attested[0], MethodPattern, langs)
	}
	if len(attested) > 0 {
		// The caller's own diacritics settle it when they wrote any: قل is the
		// spelling of both قول and قلل, but قُلْ is one word and the corpus records
		// one root for it. The collision belongs to the normalised key, not to the
		// authority, and refusing a word the authority spells unambiguously would
		// turn a fact into a miss. A spelling the corpus also writes rootless is
		// never settled this way, however fully the caller wrote it out: يَحْيَىٰ is
		// both readings in the authority itself.
		exact, err := r.store.AttestsSurface(ctx, word)
		if err != nil {
			return Result{}, err
		}
		if !surfaceRootless && len(exact) == 1 && slices.Contains(attested, exact[0]) {
			return r.fromLetters(ctx, res, exact[0], MethodLexicon, langs)
		}
		res.Rootless = keyRootless
		return r.fromShared(ctx, res, attested, langs)
	}

	// The templates run on the normalised word and on nothing else. Running them
	// down the stripped stems as well walks ever more mutilated stems until one
	// happens to fit a wazn, and one always does — تلفزيون peels to تلفز and reads
	// as form V of ل ف ز — so a reading that appears only after peeling is a guess
	// about a guess.
	for _, c := range matchPattern(res.Normalized) {
		if !slices.Contains(considered, c) {
			considered = append(considered, c)
		}
	}

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

// fromShared answers a spelling the corpus attests under several roots with all of
// them rather than with a 404 that lists them. Which root this word came from is
// the sentence's to say and nothing here reads a sentence, so the answer carries
// every reading the corpus has and names the rung that produced it.
func (r *Resolver) fromShared(ctx context.Context, res Result, letters []string, langs []string) (Result, error) {
	for _, l := range letters {
		rec, err := r.store.Root(ctx, l)
		switch {
		case err == nil:
			res.Roots = append(res.Roots, rec.Root)
		case errors.Is(err, ErrNotFound):
			res.Roots = append(res.Roots, Root{Letters: l, Display: spaced(l)})
		default:
			return Result{}, err
		}
	}
	return r.fromLetters(ctx, res, letters[0], MethodShared, langs)
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

// IsArabicWord is the boundary between 400 and 404: at least one Arabic letter,
// and no letter of another script. Diacritics are marks and Arabic-Indic digits
// are digits, so a string holding only those is not a word we can be asked about,
// and صبرabc is not an Arabic word we happen not to know — it is a word with Latin
// letters in it, and 404 would tell its caller the corpus was asked and came back
// empty. It is exported because rootd has to ask the resolver's question rather
// than a second copy of it that drifts.
func IsArabicWord(s string) bool {
	arabic := false
	for _, r := range s {
		// The runes the normaliser drops are decided first: tatweel is a letter to
		// Unicode and belongs to no script, so a word stretched typographically —
		// which is most of the Uthmani text — would otherwise read as a word with a
		// foreign letter in it.
		if dropped(r) || !unicode.IsLetter(r) {
			continue
		}
		if !unicode.Is(unicode.Arabic, r) {
			return false
		}
		arabic = true
	}
	return arabic
}

// ponytail: display is the letters spaced out and transliteration comes from the
// store. A root the store does not hold gets no transliteration until someone
// authors the letter table it would need.
func spaced(letters string) string {
	return strings.Join(strings.Split(letters, ""), " ")
}
