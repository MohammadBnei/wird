package main

import (
	"encoding/json"
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

	errs = append(errs, c.checkIrab()...)
	// All of the French or none of it. A reading that is French for a page and
	// then English is worse than one that is honestly English throughout, and it
	// is the failure a presence check cannot see: `language=fr` on the word gloss
	// answers English and calls it english, so "the column is populated" proves
	// nothing about what is in it. Counted rather than sampled.
	if full {
		var french, english int
		for _, a := range c.Ayahs {
			if a.TextFr != "" {
				french++
			}
			if a.TextEn != "" {
				english++
			}
		}
		if french != 0 && french != len(c.Ayahs) {
			errs = append(errs, fmt.Errorf("%d of %d ayas carry a French translation, so a "+
				"French reader would read some of the Qur'an in French and the rest in "+
				"Arabic with an English gloss; ingest all of it or none of it",
				french, len(c.Ayahs)))
		}
		if english != 0 && english != len(c.Ayahs) {
			errs = append(errs, fmt.Errorf("%d of %d ayas carry Pickthall's English, so an "+
				"English reader would meet a translation under some ayas and none under "+
				"others; ingest all of it or none of it", english, len(c.Ayahs)))
		}
	}

	errs = append(errs, c.checkFrenchGlosses()...)
	errs = append(errs, c.checkLemmas(full)...)
	errs = append(errs, c.checkSenses()...)
	return errors.Join(errs...)
}

// checkIrab gates the parsing per SEGMENT.
//
// Per word it would be vacuous twice over. A word keeps the rows of its other
// segments when one segment's tag is unmapped, so "every word carrying
// morphology has iʿrāb rows" passes on a parsing with a hole in the middle of
// it. And the word-count guard in Load (`n != 0 && n != pos`) lets `n == 0`
// through, so an aya missing from the morphology file gets NULL morphology for
// every word and no error at all — today closed only by luck, all 77,429 words
// carrying morphology.
//
// So the count is taken from the JSON that ships in words.morphology, parsed
// back here rather than trusted: the derived table and the provenance it was
// derived from have to agree, or one of the two is lying to a reader.
func (c *Corpus) checkIrab() []error {
	var errs []error

	roles := IrabRoles()
	named := make(map[string]bool, len(roles))
	for _, r := range roles {
		named[r.Code] = true
		if strings.TrimSpace(r.En) == "" || strings.TrimSpace(r.Fr) == "" {
			errs = append(errs, fmt.Errorf("the role %q is named %q in English and %q in French; a "+
				"parsing ships in both languages or neither, and an empty half reaches a reader as a "+
				"blank where a word's role should be", r.Code, r.En, r.Fr))
		}
	}

	rows := make(map[int64][]IrabRow, len(c.Words))
	for _, s := range c.Irab {
		rows[s.WordID] = append(rows[s.WordID], s)
	}
	// One unnamed code is the diagnosis; 128,219 of them is a wall of text.
unnamed:
	for _, s := range c.Irab {
		for _, code := range append([]string{s.Code}, strings.Fields(s.Features)...) {
			if !named[code] {
				errs = append(errs, fmt.Errorf("word %d segment %d is coded %q, which the parsing "+
					"vocabulary does not name, so that segment's role would be read as blank",
					s.WordID, s.Position, code))
				break unnamed
			}
		}
	}

	for _, w := range c.Words {
		var segs []morphSegment
		if w.Morphology != "" {
			if err := json.Unmarshal([]byte(w.Morphology), &segs); err != nil {
				errs = append(errs, fmt.Errorf("word %d: its morphology does not parse: %w", w.ID, err))
				break
			}
		}
		if len(segs) == 0 {
			errs = append(errs, fmt.Errorf("word %d carries no morphology, so it has no parsing at "+
				"all — an aya absent from the morphology file passes every other check here", w.ID))
			break
		}
		if got := len(rows[w.ID]); got != len(segs) {
			errs = append(errs, fmt.Errorf("word %d has %d segments and %d parsing rows; a word whose "+
				"parsing is short of a segment shows a reader a role belonging to another one",
				w.ID, len(segs), got))
			break
		}
		place := make(map[int]bool, len(segs))
		for _, s := range rows[w.ID] {
			place[s.Position] = true
		}
		for i := range segs {
			if !place[i+1] {
				errs = append(errs, fmt.Errorf("word %d has no parsing for segment %d", w.ID, i+1))
				break
			}
		}
	}
	return errs
}

// verseRef matches a verse citation in any shape a reference is written in. A
// verse reference inside a root's sense is the tafsir boundary crossed in
// machine-readable form: the sense has stopped being about the word.
var verseRef = regexp.MustCompile(`\b\d{1,3}\s*:\s*\d{1,3}\b`)

// checkSenses is the gate over the only prose in corpus.db that Wird wrote. It
// re-derives every number rather than reading the ones the sense file carries:
// a gate that trusts the figure written next to the claim checks nothing. The
// file's numbers are there for a reader, not for this.
func (c *Corpus) checkSenses() []error {
	if c.Senses == nil || len(c.Senses.Senses) == 0 {
		return nil
	}
	var errs []error
	for _, missing := range []struct{ what, text string }{
		{"attribution", c.Senses.Attribution},
		{"source", c.Senses.Source},
		{"basis", c.Senses.Basis},
	} {
		if strings.TrimSpace(missing.text) == "" {
			errs = append(errs, fmt.Errorf("the sense file carries no %s, so corpus.db would ship "+
				"authored prose with nothing on the screen to say whose reading it is", missing.what))
		}
	}

	rows := make([]rootsense.WordRow, 0, len(c.Words))
	for _, w := range c.Words {
		rows = append(rows, rootsense.WordRow{Root: w.RootLetters, Gloss: w.GlossEn,
			Text: w.TextAr, Form: w.Form, Morphology: w.Morphology})
	}
	roots := rootsense.Bucket(rows)
	sep, calErr := rootsense.Calibrate(roots)
	if calErr != nil {
		// Not a reason to skip the rest: what a sense claims about a verse, and
		// whether it says whose reading it is, are true or false whatever the
		// bar comes out at.
		errs = append(errs, fmt.Errorf("the senses cannot be checked against this corpus: %w", calErr))
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

	// Two roots handed the same words is a signal that at least one of them is
	// wrong, and no per-root term can see it. rootcheck refuses to write such a
	// pair, but a refusal that lives only in the builder is not a gate: the
	// file it writes can be edited. This is where the bundle is verified.
	twice := map[string][]string{}
	for _, s := range c.Senses.Senses {
		if k := strings.Join(rootsense.Content(s.SenseEn), " "); k != "" {
			twice[k] = append(twice[k], s.Root)
		}
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
		if calErr != nil {
			continue
		}
		res := rootsense.Check(roots[s.Root], s.SenseEn)
		switch {
		case !res.Verified(sep.Bar):
			errs = append(errs, fmt.Errorf("%s: scores %.3f/%.3f in %d of %d shapes, covers %.3f/%.3f "+
				"of its root's occurrences, dispersion %s/%d, leaves %.3f/%.3f of the root in one "+
				"branch it does not name, leads with its dominant branch %v; this corpus does not bear it out",
				where, res.Score, sep.Bar.Score, res.SlotsHit, len(res.Slots), res.Coverage,
				sep.Bar.Coverage, rootsense.Disp(res.Dispersion), sep.Bar.Dispersion,
				res.Branch, sep.Bar.Branch, res.Leads))
		case len(twice[strings.Join(rootsense.Content(s.SenseEn), " ")]) > 1:
			errs = append(errs, fmt.Errorf("%s: the same words are also this corpus's sense for %v, "+
				"and one prose for two roots means at least one of them is wrong",
				where, twice[strings.Join(rootsense.Content(s.SenseEn), " ")]))
		case strings.TrimSpace(s.SenseFr) == "":
			errs = append(errs, fmt.Errorf("%s: no French, and a verified sense ships in both "+
				"languages or neither", where))
		}
	}
	return errs
}

// checkFrenchGlosses refuses a corpus where the French word glosses stop at an
// aya. A page that failed to download, or one whose cards the parser no longer
// reads, leaves every word of its ayas English while the rest of the Qur'an is
// French — the failure a count of filled rows cannot see, because the other
// suras fill it. So every aya has to carry French on at least one word.
//
// Not every word: the pages skip a word here and there, and those keep their
// English (pinFrenchGlosses). How many is printed by the build, not bounded.
func (c *Corpus) checkFrenchGlosses() []error {
	french := map[int]bool{}
	for _, w := range c.Words {
		if w.GlossFr != "" {
			french[w.AyahID] = true
		}
	}
	if len(french) == 0 {
		return nil
	}
	var bare []string
	for _, a := range c.Ayahs {
		if !french[a.ID] {
			bare = append(bare, fmt.Sprintf("%d:%d", a.SurahID, a.Number))
		}
	}
	if len(bare) == 0 {
		return nil
	}
	shown := bare
	if len(shown) > 10 {
		shown = shown[:10]
	}
	return []error{fmt.Errorf("%d ayas carry no French word gloss (%s), so a French reader "+
		"would meet them in English among French ones; is data/raw/%s missing their page?",
		len(bare), strings.Join(shown, ", "), tldDir)}
}

// checkLemmas refuses a rooted word with no lemma, which the reading screen
// would count under no form, and on a full build holds the three forms of
// r-ḥ-m to the counts corpus.quran.com gives. A parser that took the lemma from
// the wrong segment, or folded two lemmas into one, moves those counts.
func (c *Corpus) checkLemmas(full bool) []error {
	var errs []error
	mercy := map[string]int{}
	for _, w := range c.Words {
		if w.RootLetters != "" && w.Lemma == "" {
			errs = append(errs, fmt.Errorf("word %d has the root %s and no lemma, so the "+
				"reading screen would count it under no form", w.ID, w.RootLetters))
			break
		}
		if w.RootLetters == "رحم" {
			mercy[w.LemmaKey]++
		}
	}
	if !full {
		return errs
	}
	for key, want := range map[string]int{"r~aHiym": 116, "raHomap": 114, "r~aHoma`n": 57} {
		if mercy[key] != want {
			errs = append(errs, fmt.Errorf("the lemma %s of r-ḥ-m occurs %d times, want %d: "+
				"lemmas are being read from the wrong segment or merged", key, mercy[key], want))
		}
	}
	return errs
}
