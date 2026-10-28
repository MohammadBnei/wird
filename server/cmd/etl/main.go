package main

import (
	"fmt"
	"log"
	"os"
	"time"
)

func main() {
	cfg, err := fromProcess() // ExitOnError: a bad flag exits 2
	if err != nil {
		log.Fatalf("config refused: %v", err)
	}

	c, err := Load(cfg.In, Recitations)
	if err != nil {
		log.Fatalf("read %s: %v", cfg.In, err)
	}
	if err := c.Check(cfg.Full); err != nil {
		log.Fatalf("corpus rejected: %v", err)
	}
	if err := Write(cfg.Out, c, cfg.CorpusVersion, time.Now()); err != nil {
		log.Fatalf("write %s: %v", cfg.Out, err)
	}

	fi, err := os.Stat(cfg.Out)
	if err != nil {
		log.Fatal(err)
	}
	fmt.Printf("%s\n  suras %d  ayas %d  words %d  roots %d  audio %d\n  parsed segments %d  roles %d\n  words with no French gloss %d\n  %.2f MB\n",
		cfg.Out, len(c.Surahs), len(c.Ayahs), len(c.Words), len(c.Roots), len(c.Audio),
		len(c.Irab), len(IrabRoles()), c.FrenchGlossesMissed, float64(fi.Size())/(1<<20))
	for _, r := range c.Recited {
		fmt.Printf("  %s: segments %d (clamped %d)  words with no timing %d\n",
			r.Slug, len(r.Segments), r.Clamped, r.Untimed)
	}
	for _, r := range c.Refused {
		fmt.Printf("  REFUSED %s\n", r)
	}
}
