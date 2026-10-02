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
	// 7 since the reciters arrived: the asset in app/assets/ carries 7, the API
	// groups reports by this number, and the rebuild SOURCES.md documents passes
	// no flag — so a stale default would silently regress every report's build.
	// app/test/features/report/report_screen_test.dart asserts the asset agrees
	// with this, which is what caught the last bump.
	version := flag.Int("corpus-version", 7, "corpus_version the API negotiates")
	full := flag.Bool("full", true, "require the whole Qur'an: 114 suras, 6236 ayas")
	flag.Parse()

	c, err := Load(*in, Recitations)
	if err != nil {
		log.Fatalf("read %s: %v", *in, err)
	}
	if err := c.Check(*full); err != nil {
		log.Fatalf("corpus rejected: %v", err)
	}
	if err := Write(*out, c, *version, time.Now()); err != nil {
		log.Fatalf("write %s: %v", *out, err)
	}

	fi, err := os.Stat(*out)
	if err != nil {
		log.Fatal(err)
	}
	fmt.Printf("%s\n  suras %d  ayas %d  words %d  roots %d  audio %d\n  parsed segments %d  roles %d\n  words with no French gloss %d\n  %.2f MB\n",
		*out, len(c.Surahs), len(c.Ayahs), len(c.Words), len(c.Roots), len(c.Audio),
		len(c.Irab), len(IrabRoles()), c.FrenchGlossesMissed, float64(fi.Size())/(1<<20))
	for _, r := range c.Recited {
		fmt.Printf("  %s: segments %d (clamped %d)  words with no timing %d\n",
			r.Slug, len(r.Segments), r.Clamped, r.Untimed)
	}
	for _, r := range c.Refused {
		fmt.Printf("  REFUSED %s\n", r)
	}
}
