package root

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"slices"
	"strings"
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

	// Root returns the root with these joined letters. It answers membership —
	// whether anything in the language is built on these letters — and never
	// identity, so a yes from it is not a statement about any particular word.
	Root(ctx context.Context, letters string) (RootRecord, error)

	// AttestsSurface returns the roots the corpus records this exact spelling
	// under, diacritics and all. It is what settles a normalised key two roots
	// share: قل is قول and قلل, but قُلْ as the corpus writes it is only قول, so a
	// caller who supplies the diacritics gets the one root the authority records
	// and never a list. A spelling the corpus does not write returns no roots and
	// a nil error.
	AttestsSurface(ctx context.Context, surface string) ([]string, error)

	// Attests returns the roots the corpus records this written form under, spelled
	// as the corpus spells them. This is the identity question Root cannot answer:
	// Root says لوك is a root, Attests says whether ملوك is one of its forms, and
	// reading the first as the second is what once served ملوك as ل و ك.
	//
	// A form the corpus never attests returns no roots and a nil error, because an
	// unattested word is a miss and not a failure. Two roots back means this
	// spelling is shared, and they come back most-used root first.
	//
	// One indexed lookup on the normalised form answers this — a form-to-root table
	// keyed by that spelling. It deliberately takes no candidate roots to filter by:
	// the resolver can arrive here holding two dozen readings of one word, and a
	// lookup per reading is that many round trips for one question.
	Attests(ctx context.Context, form string) ([]string, error)

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

	// Attested maps a written form to the roots the corpus attests it to. Both
	// sides go in spelled as the corpus spells them and are normalised on the way
	// into the index, so a fixture carries the corpus's own orthography and makes
	// no spelling decisions of its own.
	Attested map[string][]string `json:"attested,omitempty"`
}

// MemoryStore is a Store held entirely in memory, seeded from a Corpus. It is how
// the resolver is tested before any corpus is ingested, and how a caller outside
// Wird uses jidhr with no database at all.
type MemoryStore struct {
	bySurface    map[string]Entry
	byNormalized map[string]Entry
	byLemma      map[string]Entry
	roots        map[string]RootRecord
	attested     map[string][]string
	bySpelling   map[string][]string
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
		attested:     map[string][]string{},
		bySpelling:   map[string][]string{},
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
		for _, k := range indexKeys(e.Surface) {
			index(m.byNormalized, k, e)
		}
		for _, k := range indexKeys(e.Lemma) {
			index(m.byLemma, k, e)
		}
	}
	for form, roots := range c.Attested {
		spelling := TrimMarks(form)
		for _, r := range roots {
			if spelling != "" && !slices.Contains(m.bySpelling[spelling], r) {
				m.bySpelling[spelling] = append(m.bySpelling[spelling], r)
			}
			for _, k := range indexKeys(form) {
				if k != "" && !slices.Contains(m.attested[k], r) {
					m.attested[k] = append(m.attested[k], r)
				}
			}
		}
	}
	// Two spellings of one form reach the same key in whatever order the map hands
	// them over, and a resolver that answers a different root on a different run is
	// worse than one that answers none. The most-used root leads, because a key
	// several roots share is answered with the list in this order.
	//
	// ponytail: most-used is counted over the whole Qur'an, not over this spelling,
	// so كفوا leads with كفف where the one verse that writes it means كفأ. Both
	// roots are on the answer either way. Order by attestations of this spelling
	// once the corpus file carries a count per form and root.
	for _, roots := range m.attested {
		m.sortByUse(roots)
	}
	for _, roots := range m.bySpelling {
		m.sortByUse(roots)
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

// sortByUse orders roots by how much of the Qur'an is built on them, most first,
// and settles a tie on the letters so two runs answer alike.
func (m *MemoryStore) sortByUse(roots []string) {
	slices.SortFunc(roots, func(a, b string) int {
		if d := m.uses(b) - m.uses(a); d != 0 {
			return d
		}
		return strings.Compare(a, b)
	})
}

func (m *MemoryStore) uses(letters string) int {
	r, ok := m.roots[letters]
	if !ok || r.Quran == nil {
		return 0
	}
	return r.Quran.Occurrences
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

func (m *MemoryStore) Attests(_ context.Context, form string) ([]string, error) {
	return m.attested[form], nil
}

func (m *MemoryStore) AttestsSurface(_ context.Context, surface string) ([]string, error) {
	return m.bySpelling[TrimMarks(surface)], nil
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

// Languages are the languages this corpus holds meanings in, sorted. A caller that
// names none is answered in these, so the languages offered are the ones the data
// actually carries rather than a list written down beside it that drifts from it.
func (m *MemoryStore) Languages() []string {
	var langs []string
	for _, by := range m.meanings {
		for lang := range by {
			if !slices.Contains(langs, lang) {
				langs = append(langs, lang)
			}
		}
	}
	slices.Sort(langs)
	return langs
}
