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
	duration := make(map[int]int, len(c.Audio))
	for _, a := range c.Audio {
		duration[a.AyahID] = a.DurationMS
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
		if d := duration[aid]; d > 0 && (s.EndMS > d || s.StartMS > d) {
			errs = append(errs, fmt.Errorf("aya %d: segment %d-%d runs past the %dms audio file",
				aid, s.StartMS, s.EndMS, d))
			break
		}
	}
	return errors.Join(errs...)
}
