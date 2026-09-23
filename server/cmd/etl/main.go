package main

import (
	"flag"
	"fmt"
	"log"
	"os"
	"time"
)

func main() {
	in := flag.String("in", "./data/raw/", "ingest directory")
	out := flag.String("out", "./app/assets/corpus.db", "corpus.db to write")
	slug := flag.String("recitation", "husary-muallim", "recitation slug")
	timingsFile := flag.String("timings", "Husary_Muallim_128kbps",
		"which of quran-align's recitations data/raw/timings/ holds")
	reciter := flag.String("reciter", "Mahmoud Khalil Al-Husary", "reciter name")
	style := flag.String("style", "Muallim", "recitation style")
	version := flag.Int("corpus-version", 1, "corpus_version the API negotiates")
	full := flag.Bool("full", true, "require the whole Qur'an: 114 suras, 6236 ayas")
	senses := flag.String("senses", "./data/root_senses.json", "the checked root senses to bundle")
	flag.Parse()

	c, err := Load(*in, *slug, *timingsFile)
	if err != nil {
		log.Fatalf("read %s: %v", *in, err)
	}
	if c.Senses, err = LoadSenses(*senses); err != nil {
		log.Fatalf("read %s: %v", *senses, err)
	}
	if err := c.Check(*full); err != nil {
		log.Fatalf("corpus rejected: %v", err)
	}
	if err := Write(*out, c, Recitation{Slug: *slug, ReciterName: *reciter, Style: *style}, *version, time.Now()); err != nil {
		log.Fatalf("write %s: %v", *out, err)
	}

	timed := make(map[int64]bool, len(c.Segments))
	for _, s := range c.Segments {
		timed[s.WordID] = true
	}
	silent := 0
	for _, w := range c.Words {
		if !timed[w.ID] {
			silent++
		}
	}

	fi, err := os.Stat(*out)
	if err != nil {
		log.Fatal(err)
	}
	fmt.Printf("%s\n  suras %d  ayas %d  words %d  roots %d  senses %d\n  audio %d  segments %d (clamped %d)\n  words with no timing %d\n  %.2f MB\n",
		*out, len(c.Surahs), len(c.Ayahs), len(c.Words), len(c.Roots), len(c.Senses.Senses),
		len(c.Audio), len(c.Segments), c.Clamped, silent, float64(fi.Size())/(1<<20))
}
