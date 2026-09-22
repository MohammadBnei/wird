package root

import (
	"context"
	"encoding/json"
	"errors"
	"io"
)

// ErrNotFound is what a Store returns when a lookup matched nothing. It is a miss,
// not a failure: the resolver steps down to the next rung. Any other error stops
// resolution outright, because a broken corpus must never read to the caller as an
// Arabic word with no root.
var ErrNotFound = errors.New("jidhr: not found")

// Entry is one written form as a corpus records it. An entry with an empty Surface
// states a lemma fact on its own, which is how a corpus that knows a dictionary
// form without having attested a spelling for it is expressed.
type Entry struct {
	Surface string `json:"surface,omitempty"`
	Lemma   string `json:"lemma,omitempty"`
	Form    string `json:"form,omitempty"`
	Root    string `json:"root"`
}

// RootRecord is a root plus whatever Qur'anic statistics the store holds for it.
type RootRecord struct {
	Root
	Quran *QuranStats `json:"quran,omitempty"`
}

// Store is everything the resolver needs from a corpus. Implement it over Postgres
// for a deployment, or seed a MemoryStore for a caller that wants no database at all.
type Store interface {
	// EntryBySurface matches a written form exactly as the corpus spells it,
	// diacritics included. This is rung one and must not fall back to a looser
	// match, or every result would claim to be an attested lexicon hit.
	EntryBySurface(ctx context.Context, surface string) (Entry, error)

	// EntryByNormalized matches a form by its normalised spelling. This is rung
	// two, so an implementation keeps the normalised spelling of every surface
	// form alongside the original.
	EntryByNormalized(ctx context.Context, normalized string) (Entry, error)

	// EntryByLemma matches a dictionary form by its normalised spelling.
	EntryByLemma(ctx context.Context, normalized string) (Entry, error)

	// Root returns the root with these joined letters.
	Root(ctx context.Context, letters string) (RootRecord, error)

	// Meanings returns the authored meanings for a root, keyed by language, for
	// the languages asked for. A root with nothing authored yet is not an error
	// and not a miss: it returns no meanings and a nil error.
	Meanings(ctx context.Context, letters string, langs []string) (map[string]Meaning, error)
}

// Corpus is the seed for a MemoryStore and the on-disk shape of jidhr's fixtures.
type Corpus struct {
	Roots    []RootRecord                  `json:"roots"`
	Entries  []Entry                       `json:"entries"`
	Meanings map[string]map[string]Meaning `json:"meanings"`
}

// MemoryStore is a Store held entirely in memory, seeded from a Corpus. It is how
// the resolver is tested before any corpus is ingested, and how a caller outside
// Wird uses jidhr with no database at all.
type MemoryStore struct {
	bySurface    map[string]Entry
	byNormalized map[string]Entry
	byLemma      map[string]Entry
	roots        map[string]RootRecord
	meanings     map[string]map[string]Meaning
}

// NewMemoryStore indexes a corpus. The normalised indexes are built by running the
// same normaliser the resolver runs, so the fake cannot answer a question the real
// store would answer differently.
func NewMemoryStore(c Corpus) *MemoryStore {
	m := &MemoryStore{
		bySurface:    map[string]Entry{},
		byNormalized: map[string]Entry{},
		byLemma:      map[string]Entry{},
		roots:        map[string]RootRecord{},
		meanings:     c.Meanings,
	}
	for _, r := range c.Roots {
		m.roots[r.Letters] = r
	}
	for _, e := range c.Entries {
		index(m.bySurface, e.Surface, e)
	}
	// ponytail: the first entry to claim a key wins. Ambiguous forms need a list
	// and a ranking, which is the real store's problem once a corpus exists.
	for _, e := range c.Entries {
		index(m.byNormalized, normalized(e.Surface), e)
		index(m.byLemma, normalized(e.Lemma), e)
	}
	return m
}

// LoadMemoryStore reads a corpus in the fixture JSON shape.
func LoadMemoryStore(r io.Reader) (*MemoryStore, error) {
	var c Corpus
	if err := json.NewDecoder(r).Decode(&c); err != nil {
		return nil, err
	}
	return NewMemoryStore(c), nil
}

func index(into map[string]Entry, key string, e Entry) {
	if key == "" {
		return
	}
	if _, taken := into[key]; taken {
		return
	}
	into[key] = e
}

// normalized is normalize without its error, for index building: a word the
// normaliser cannot reduce simply gets no normalised index entry.
func normalized(word string) string {
	n, err := normalize(word)
	if err != nil {
		return ""
	}
	return n
}

func (m *MemoryStore) EntryBySurface(_ context.Context, surface string) (Entry, error) {
	e, ok := m.bySurface[surface]
	if !ok {
		return Entry{}, ErrNotFound
	}
	return e, nil
}

func (m *MemoryStore) EntryByNormalized(_ context.Context, n string) (Entry, error) {
	e, ok := m.byNormalized[n]
	if !ok {
		return Entry{}, ErrNotFound
	}
	return e, nil
}

func (m *MemoryStore) EntryByLemma(_ context.Context, n string) (Entry, error) {
	e, ok := m.byLemma[n]
	if !ok {
		return Entry{}, ErrNotFound
	}
	return e, nil
}

func (m *MemoryStore) Root(_ context.Context, letters string) (RootRecord, error) {
	r, ok := m.roots[letters]
	if !ok {
		return RootRecord{}, ErrNotFound
	}
	return r, nil
}

func (m *MemoryStore) Meanings(_ context.Context, letters string, langs []string) (map[string]Meaning, error) {
	have := m.meanings[letters]
	if len(have) == 0 {
		return nil, nil
	}
	out := map[string]Meaning{}
	for _, l := range langs {
		if mn, ok := have[l]; ok {
			out[l] = mn
		}
	}
	if len(out) == 0 {
		return nil, nil
	}
	return out, nil
}
