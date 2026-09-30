package main

import "github.com/MohammadBnei/wird/server/internal/rootsense"

// These types describe the sense file the ETL used to read, and nothing reads
// one any more: corpus.db carries no senses table, a reader gets every sense
// from /v1/senses over HTTP, and the seeder in server/cmd/senseseed is what
// writes them. Nothing outside the tests assigns Corpus.Senses, so checkSenses
// in check.go returns on its first line for every real run — the build-time
// gate over authored prose is inert, and its tests prove only that the gate
// would work if something fed it. The shapes stay because the day a sense file
// is loaded again is the day that gate has to come back.

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
