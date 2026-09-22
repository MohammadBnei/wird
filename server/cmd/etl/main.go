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
	reciter := flag.String("reciter", "Mahmoud Khalil Al-Husary", "reciter name")
	style := flag.String("style", "Muallim", "recitation style")
	version := flag.Int("corpus-version", 1, "corpus_version the API negotiates")
	full := flag.Bool("full", true, "require the whole Qur'an: 114 suras, 6236 ayas")
	flag.Parse()

	c, err := Load(*in, *slug)
	if err != nil {
		log.Fatalf("read %s: %v", *in, err)
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
	fmt.Printf("%s\n  suras %d  ayas %d  words %d  roots %d\n  audio %d  segments %d (clamped %d, merged into the last word %d)\n  words with no timing %d\n  %.2f MB\n",
		*out, len(c.Surahs), len(c.Ayahs), len(c.Words), len(c.Roots),
		len(c.Audio), len(c.Segments), c.Clamped, c.Merged, silent, float64(fi.Size())/(1<<20))
}
