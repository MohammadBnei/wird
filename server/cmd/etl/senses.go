package main

import (
	"encoding/json"
	"fmt"
	"os"

	"github.com/MohammadBnei/wird/server/internal/rootsense"
)

// A root sense is the only prose in corpus.db that Wird wrote itself, so it
// carries the hardest conditions in this ETL: it ships only if the corpus's own
// glosses still bear it out at build time, and it reaches the database with the
// words it was checked against and a line saying whose reading it is, because a
// reader who cannot tell authored prose from a quoted lexicon has been told
// something false about where the words came from.

type Sense struct {
	Root       string              `json:"root"`
	SenseEn    string              `json:"sense_en"`
	SenseFr    string              `json:"sense_fr"`
	Score      float64             `json:"score"`
	Coverage   float64             `json:"coverage"`
	Dispersion int                 `json:"dispersion"`
	SlotsHit   int                 `json:"slots_hit"`
	Slots      int                 `json:"slots"`
	Others     int                 `json:"also_verifies"`
	Support    []rootsense.Support `json:"support"`
}

type Senses struct {
	Attribution string `json:"attribution"`
	Source      string `json:"source"`
	Basis       string `json:"basis"`
	Method      string `json:"method"`
	Bar         struct {
		Score      float64 `json:"score"`
		Coverage   float64 `json:"coverage"`
		Dispersion int     `json:"dispersion"`
	} `json:"bar"`
	SpecificBar int     `json:"specificity_bar"`
	Senses      []Sense `json:"senses"`
}

// LoadSenses reads the checked sense file. A missing file is not an error: the
// senses are a separate body of work from the corpus, and an ingest run without
// them is a corpus with no Core sense section, not a broken build.
func LoadSenses(path string) (*Senses, error) {
	f, err := os.Open(path)
	if os.IsNotExist(err) {
		return &Senses{}, nil
	}
	if err != nil {
		return nil, err
	}
	defer f.Close()
	var s Senses
	if err := json.NewDecoder(f).Decode(&s); err != nil {
		return nil, fmt.Errorf("%s: %w", path, err)
	}
	return &s, nil
}
