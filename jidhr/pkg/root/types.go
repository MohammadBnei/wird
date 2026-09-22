package root

// Method names the rung of the resolution ladder that produced a result. The rung
// is the confidence: a lexicon hit is an attested corpus fact, a pattern match is a
// derivation from the shape of the word. There is no separate confidence score,
// because a caller branching on an undefined float branches on nothing.
type Method string

const (
	MethodLexicon    Method = "lexicon"
	MethodNormalized Method = "normalized"
	MethodLemma      Method = "lemma"
	MethodStripped   Method = "stripped"
	// MethodPattern names rung five, the last. It is the weakest of the five only
	// in that the form reached no lexicon entry of its own: the root still comes
	// from the corpus attesting this very spelling, never from the letters merely
	// allowing it. The templates rank what a miss reports and decide nothing.
	MethodPattern Method = "pattern"
)

// Root identifies an Arabic root. Letters is the joined form and is the key
// everywhere: in URL paths, in the store, and in the meanings table. Display
// carries the spaced presentation and is never a key, because two callers
// percent-encode a spaced string two different ways. Translit is absent rather
// than empty for a root nobody has transliterated yet, because a blank
// transliteration is read as a transliteration.
type Root struct {
	Letters  string `json:"letters"`
	Display  string `json:"display"`
	Translit string `json:"translit,omitempty"`
}

// QuranStats is absent for a root that does not occur in the Qur'an, so a caller
// asking about an arbitrary Arabic word is never handed a Qur'an statistic it did
// not ask for.
type QuranStats struct {
	Occurrences int `json:"occurrences"`
}

// Meaning is one language's authored meaning of a root, in both registers.
// Meanings are written by a person, never generated, so an unwritten poetic
// register is absent rather than an empty string.
type Meaning struct {
	Plain  string `json:"plain"`
	Poetic string `json:"poetic,omitempty"`
}

// Result is the published response shape of GET /v1/root. The field order here is
// the documented order, and outside callers parse these names.
type Result struct {
	Input      string             `json:"input"`
	Normalized string             `json:"normalized"`
	Root       Root               `json:"root"`
	Lemma      string             `json:"lemma,omitempty"`
	Form       string             `json:"form,omitempty"`
	Method     Method             `json:"method"`
	Quran      *QuranStats        `json:"quran,omitempty"`
	Meanings   map[string]Meaning `json:"meanings,omitempty"`
}
