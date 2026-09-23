package main

import (
	"errors"
	"fmt"
	"strings"
)

const (
	quranSurahs = 114
	quranAyahs  = 6236
)

// Check is the build gate. Every failure here is a way the shipped asset teaches
// the app something false, so it stops the build instead of being reported.
func (c *Corpus) Check(full bool) error {
	var errs []error

	// Both sources require their notice to be reproduced in works derived from
	// them — the morphology's terms in as many words, and CC BY 4.0 in Section
	// 3(a)(1). corpus.db is what reaches a reader; a repo file does not.
	for _, marker := range []string{
		"Quranic Arabic Corpus", "Kais Dukes", "corpus.quran.com",
		"quran-align", "Collin Fair", "creativecommons.org/licenses/by/4.0/",
	} {
		if !strings.Contains(c.Notice, marker) {
			errs = append(errs, fmt.Errorf("the corpus notice does not mention %q, so the shipped "+
				"database would carry data whose licence requires it to be attributed and is not", marker))
			break
		}
	}

	if full {
		if len(c.Surahs) != quranSurahs {
			errs = append(errs, fmt.Errorf("%d suras, want %d", len(c.Surahs), quranSurahs))
		}
		if len(c.Ayahs) != quranAyahs {
			errs = append(errs, fmt.Errorf("%d ayas, want %d", len(c.Ayahs), quranAyahs))
		}
		if len(c.Audio) != len(c.Ayahs) {
			errs = append(errs, fmt.Errorf("%d ayas but %d audio rows: an aya would play nothing",
				len(c.Ayahs), len(c.Audio)))
		}
	}
	if c.Orphans > 0 {
		errs = append(errs, fmt.Errorf("%d segments name a word the corpus does not have", c.Orphans))
	}

	words := make(map[int64]bool, len(c.Words))
	for _, w := range c.Words {
		words[w.ID] = true
	}
	for _, a := range c.Audio {
		if strings.Contains(a.RelPath, "://") || strings.HasPrefix(a.RelPath, "/") {
			errs = append(errs, fmt.Errorf("aya %d audio %q is not a relative path: a host frozen "+
				"into the asset costs a release the day it moves", a.AyahID, a.RelPath))
			break
		}
	}

	known := make(map[string]bool, len(c.Roots))
	for _, r := range c.Roots {
		known[r.Letters] = true
	}
	for _, w := range c.Words {
		if w.RootLetters != "" && !known[w.RootLetters] {
			errs = append(errs, fmt.Errorf("word %d names root %q, which the roots table does not "+
				"have, so its root panel would open empty", w.ID, w.RootLetters))
			break
		}
	}

	lastStart := map[int]int{}
	for _, s := range c.Segments {
		if !words[s.WordID] {
			errs = append(errs, fmt.Errorf("segment for word %d, which is not in the corpus", s.WordID))
			break
		}
		aid := int(s.WordID / 1000)
		if s.StartMS < lastStart[aid] {
			errs = append(errs, fmt.Errorf("aya %d: segment starts at %d after one starting at %d, "+
				"so the highlight jumps backwards", aid, s.StartMS, lastStart[aid]))
			break
		}
		lastStart[aid] = s.StartMS
	}
	return errors.Join(errs...)
}
