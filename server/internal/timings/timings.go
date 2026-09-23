// Package timings reads the word timings cpfair/quran-align publishes and maps
// their word indices onto the corpus's own word positions.
//
// One reader, used by both the ingest and the ETL. Two readers of the same
// tuples is how this project shipped a database whose untimed-word count was 87
// where the manifest said 26: the manifest's reader was right and the ETL's was
// not, and nothing compared them.
//
// The data is CC BY 4.0. Notice is the attribution Section 3(a)(1) asks for.
package timings

import (
	"encoding/json"
	"fmt"
	"os"
)

// Notice travels into corpus.db so the attribution ships inside the app rather
// than sitting in a repo file no reader opens. CC BY 4.0 Section 3(a)(1) asks
// for the creator, a copyright notice, a reference to the licence and to its
// disclaimer of warranties, a link to the material, and — 3(a)(1)(B) — an
// indication that it was modified. Section 3(a)(2) allows a URI in place of the
// licence text, which is why the legal code is linked and not copied.
//
// The quoted sentence is quran-align's own, from the README inside the release
// package. The ingest refuses a package whose README no longer carries it.
func Notice(file string) string {
	return fmt.Sprintf(`# quran-align word timings (%s)
# Copyright (c) 2016 Collin Fair
# https://github.com/cpfair/quran-align
#
# TERMS OF USE, verbatim from the README inside the release package:
#
# - "These data files are licensed under a Creative Commons Attribution 4.0
#   International License (https://creativecommons.org/licenses/by/4.0/)."
#
# That licence disclaims all warranties and liability (Section 5). Modified:
# the timings are reindexed onto this database's word ids, one row per word.`, file)
}

// LicenceMarker is the sentence above, reduced to what has to still be in the
// package's README for the notice above to be a quote rather than a claim.
const LicenceMarker = "Creative Commons Attribution 4.0"

// File is one recitation's timings: [{surah, ayah, segments: [[...], ...]}].
// A tuple is [word_start_index, word_end_index, start_ms, end_ms], zero-based
// over the aligner's words and with the end index exclusive.
type File struct {
	Surah    int     `json:"surah"`
	Ayah     int     `json:"ayah"`
	Segments [][]int `json:"segments"`
}

// Load reads one recitation's file, keyed by surah and ayah.
func Load(path string) (map[[2]int][][]int, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var ayahs []File
	if err := json.Unmarshal(b, &ayahs); err != nil {
		return nil, fmt.Errorf("%s: %w", path, err)
	}
	if len(ayahs) == 0 {
		return nil, fmt.Errorf("%s carries no ayas", path)
	}
	out := make(map[[2]int][][]int, len(ayahs))
	for _, a := range ayahs {
		out[[2]int{a.Surah, a.Ayah}] = a.Segments
	}
	return out, nil
}

// Span is one stretch of audio and the words it covers, in the corpus's own
// one-based word positions. FirstWord and LastWord are inclusive, and equal for
// all but the 27 spans the aligner could not split.
type Span struct {
	FirstWord, LastWord int
	StartMS, EndMS      int
}

// Spans maps one aya's tuples onto word positions.
//
// The aligner and the corpus number words the same way in 6,231 of 6,236 ayas.
// The exception is the muqaṭṭaʿāt: the recogniser's language model treats the
// opening letters as several words where the text keeps one, so those ayas carry
// one index too many and every index after the split sits one ahead of the word
// it belongs to. Reading them as they come hands word 2 the timing of word 3 and
// mis-highlights every word after it to the end of the aya — five ayas of the
// shipped recitation did exactly that.
func Spans(raw [][]int, wordCount int) ([]Span, error) {
	slots, prevTo := wordCount, 0
	aligned := map[int]bool{}
	for _, t := range raw {
		if len(t) != 4 {
			return nil, fmt.Errorf("a %d-element segment %v: this reads "+
				"[word_start_index, word_end_index, start_ms, end_ms] and the shape has changed under it",
				len(t), t)
		}
		if t[0] < 0 || t[1] <= t[0] || t[0] < prevTo {
			return nil, fmt.Errorf("segment [%d,%d) does not follow [_,%d) as a walk over the words",
				t[0], t[1], prevTo)
		}
		for k := t[0]; k < t[1]; k++ {
			aligned[k] = true
		}
		prevTo = t[1]
		if t[1] > slots {
			slots = t[1]
		}
	}

	// split is the index the two numberings part at: at and after it, an index
	// names the word before the one it looks like. Past the end when they agree.
	split := slots
	switch slots - wordCount {
	case 0:
	case 1:
		// The index too many is the one nothing aligned — the second half of the
		// letter group, already timed by the first. When every index was aligned
		// the split is at the tail, where the reciter carries the last word past
		// where the text ends it.
		split = slots - 1
		for k := 0; k < slots; k++ {
			if !aligned[k] {
				split = k
				break
			}
		}
	default:
		return nil, fmt.Errorf("the timings number %d words where the text has %d: two "+
			"segmentations in one aya mis-highlight every word after they diverge", slots, wordCount)
	}

	word := func(slot int) int {
		w := slot + 1
		if slot >= split {
			w = slot
		}
		return min(max(w, 1), wordCount)
	}
	out := make([]Span, 0, len(raw))
	for _, t := range raw {
		out = append(out, Span{
			FirstWord: word(t[0]), LastWord: word(t[1] - 1),
			StartMS: t[2], EndMS: t[3],
		})
	}
	return out, nil
}
