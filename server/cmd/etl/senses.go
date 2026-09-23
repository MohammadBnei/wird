package main

import (
	"encoding/json"
	"fmt"
	"os"

	"github.com/MohammadBnei/wird/server/internal/rootsense"
)

// A root sense is the only prose in corpus.db that Wird wrote itself, so it
// carries the hardest conditions in this ETL: it ships only if the corpus's own
// glosses still bear it out at build time, and it is never allowed to read as
// though it came from a lexicon or as though it were about a verse.

type Sense struct {
	Root     string              `json:"root"`
	SenseEn  string              `json:"sense_en"`
	SenseFr  string              `json:"sense_fr"`
	Score    float64             `json:"score"`
	SlotsHit int                 `json:"slots_hit"`
	Slots    int                 `json:"slots"`
	Others   int                 `json:"also_verifies"`
	Support  []rootsense.Support `json:"support"`
}

type Senses struct {
	Attribution string  `json:"attribution"`
	Method      string  `json:"method"`
	Threshold   float64 `json:"threshold"`
	SpecificBar int     `json:"specificity_bar"`
	Senses      []Sense `json:"senses"`
}

// LoadSenses reads the certified sense file. A missing file is not an error:
// the senses are a separate body of work from the corpus and an ingest run
// without them is a corpus without a Core sense section, not a broken build.
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
