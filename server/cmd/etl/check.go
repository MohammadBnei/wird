package main

import (
	"errors"
	"fmt"
	"regexp"
	"strings"

	"github.com/MohammadBnei/wird/server/internal/rootsense"
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

	errs = append(errs, c.checkSenses()...)
	return errors.Join(errs...)
}

// verseRef matches a verse citation in any of the shapes a reference is written
// in. A verse reference inside a root's sense is the tafsir boundary crossed,
// in machine-readable form: the sense has stopped being about the word.
var verseRef = regexp.MustCompile(`\b\d{1,3}\s*:\s*\d{1,3}\b`)

// checkSenses is the gate over the only prose in corpus.db that Wird wrote.
// It re-derives every number rather than reading the ones the sense file
// carries: a gate that trusts the figure written next to the claim checks
// nothing. The file's scores are there for a reader, not for this.
func (c *Corpus) checkSenses() []error {
	if c.Senses == nil || len(c.Senses.Senses) == 0 {
		return nil
	}
	var errs []error
	if strings.TrimSpace(c.Senses.Attribution) == "" {
		errs = append(errs, errors.New("the sense file carries no attribution, so corpus.db would "+
			"ship authored prose a reader could mistake for a quoted lexicon"))
	}

	rows := make([]rootsense.WordRow, 0, len(c.Words))
	for _, w := range c.Words {
		rows = append(rows, rootsense.WordRow{Root: w.RootLetters, Gloss: w.GlossEn,
			Text: w.TextAr, Form: w.Form, Morphology: w.Morphology})
	}
	roots := rootsense.Bucket(rows)
	sep, err := rootsense.Calibrate(roots)
	if err != nil {
		return append(errs, fmt.Errorf("the senses cannot be checked against this corpus: %w", err))
	}

	// Sura names are transliterated Arabic and capitalised, so they cannot
	// collide with a sense written in plain lower-case English. The match is
	// case-sensitive for exactly that reason: "Sad" is a sura, "sad" is a word.
	names := make([]string, 0, len(c.Surahs))
	for _, s := range c.Surahs {
		names = append(names, s.NameEn)
	}

	known := make(map[string]bool, len(c.Roots))
	for _, r := range c.Roots {
		known[r.Letters] = true
	}

	for _, s := range c.Senses.Senses {
		where := fmt.Sprintf("root %s sense %q", s.Root, s.SenseEn)
		if !known[s.Root] {
			errs = append(errs, fmt.Errorf("%s: the roots table has no such root", where))
			continue
		}
		if len(s.Support) == 0 {
			errs = append(errs, fmt.Errorf("%s: no provenance, so nothing says which of the "+
				"root's own words the sense was checked against", where))
		}
		for _, text := range []string{s.SenseEn, s.SenseFr} {
			if m := verseRef.FindString(text); m != "" {
				errs = append(errs, fmt.Errorf("%s: cites verse %s; a root's sense is a claim "+
					"about the word and never about a verse", where, m))
			}
			for _, n := range names {
				if strings.Contains(text, n) {
					errs = append(errs, fmt.Errorf("%s: names the sura %s; a root's sense is a "+
						"claim about the word and never about a verse", where, n))
					break
				}
			}
		}
		res := rootsense.Check(roots[s.Root], s.SenseEn)
		if !res.Verified(sep.Threshold) {
			errs = append(errs, fmt.Errorf("%s: scores %.3f in %d of %d shapes against a threshold "+
				"of %.3f; this corpus does not bear it out", where, res.Score, res.SlotsHit,
				len(res.Slots), sep.Threshold))
		}
		if strings.TrimSpace(s.SenseFr) == "" {
			errs = append(errs, fmt.Errorf("%s: no French, and a verified sense ships in both "+
				"languages or neither", where))
		}
	}
	return errs
}
