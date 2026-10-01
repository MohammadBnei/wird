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
	// 5 since the French word glosses arrived: the asset in app/assets/ carries 5, the API
	// groups reports by this number, and the rebuild SOURCES.md documents passes
	// no flag — so a stale default would silently regress every report's build.
	// app/test/features/report/report_screen_test.dart asserts the asset agrees
	// with this, which is what caught the last bump.
	version := flag.Int("corpus-version", 5, "corpus_version the API negotiates")
	full := flag.Bool("full", true, "require the whole Qur'an: 114 suras, 6236 ayas")
	flag.Parse()

	c, err := Load(*in, *slug, *timingsFile)
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
	fmt.Printf("%s\n  suras %d  ayas %d  words %d  roots %d\n  audio %d  segments %d (clamped %d)\n  parsed segments %d  roles %d\n  words with no timing %d\n  words with no French gloss %d\n  %.2f MB\n",
		*out, len(c.Surahs), len(c.Ayahs), len(c.Words), len(c.Roots),
		len(c.Audio), len(c.Segments), c.Clamped, len(c.Irab), len(IrabRoles()),
		silent, c.FrenchGlossesMissed, float64(fi.Size())/(1<<20))
}
