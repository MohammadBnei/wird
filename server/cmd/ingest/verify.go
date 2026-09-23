package main

import (
	"bufio"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"time"
)

type chapter struct {
	ID              int    `json:"id"`
	NameArabic      string `json:"name_arabic"`
	NameSimple      string `json:"name_simple"`
	VersesCount     int    `json:"verses_count"`
	RevelationOrder int    `json:"revelation_order"`
	RevelationPlace string `json:"revelation_place"`
}

type chaptersFile struct {
	Chapters []chapter `json:"chapters"`
}

type versesFile struct {
	Verses []struct {
		VerseKey string `json:"verse_key"`
		Words    []struct {
			CharTypeName string `json:"char_type_name"`
		} `json:"words"`
	} `json:"verses"`
	Pagination struct {
		NextPage *int `json:"next_page"`
	} `json:"pagination"`
}

type segmentsFile struct {
	AudioFiles []struct {
		VerseKey string  `json:"verse_key"`
		URL      string  `json:"url"`
		Duration float64 `json:"duration"`
		Segments [][]int `json:"segments"`
	} `json:"audio_files"`
	Pagination struct {
		NextPage *int `json:"next_page"`
	} `json:"pagination"`
}

type counts struct {
	Surahs             int `json:"surahs"`
	Ayahs              int `json:"ayahs"`
	Words              int `json:"words"`
	AudioFiles         int `json:"audio_files"`
	SegmentTuples      int `json:"segment_tuples"`
	WordsTimed         int `json:"words_timed"`
	MorphologySegments int `json:"morphology_segments"`
	Roots              int `json:"roots"`
}

type reconciliation struct {
	// The number the whole ingest exists to keep at zero: an aya whose word
	// source and segment source number words differently highlights every word
	// after the disagreement on the wrong one.
	AyahsWhereWordNumberingDisagrees int `json:"ayahs_where_word_numbering_disagrees"`
	AyahsWithASegmentPastTheLastWord int `json:"ayahs_with_a_segment_past_the_last_word"`
	MultiWordSegmentSpans            int `json:"multi_word_segment_spans"`
	WordsTimedOnlyByAMultiWordSpan   int `json:"words_timed_only_by_a_multi_word_span"`
	WordsWithNoTiming                int `json:"words_with_no_timing"`
	AyahsWithAnUntimedWord           int `json:"ayahs_with_an_untimed_word"`
	OverlappingSegmentPairs          int `json:"overlapping_segment_pairs"`
	SegmentsEndingBeforeTheyStart    int `json:"segments_ending_before_they_start"`
}

type fileSum struct {
	Path   string `json:"path"`
	Bytes  int64  `json:"bytes"`
	SHA256 string `json:"sha256"`
}

type manifest struct {
	GeneratedAt    string         `json:"generated_at"`
	Complete       bool           `json:"complete"`
	Suras          []int          `json:"suras"`
	Sources        []string       `json:"sources"`
	Counts         counts         `json:"counts"`
	Reconciliation reconciliation `json:"reconciliation"`
	Files          []fileSum      `json:"files"`
}

// The lines that make a copy of the morphology the file corpus.quran.com
// distributes rather than one of the forks. The terms grant verbatim copying and
// nothing else, and require the notice to travel with the data; a fork that drops
// the block breaks both at once, which is the mistake this ingest exists to not
// repeat.
var copyrightMarkers = []string{
	"Quranic Arabic Corpus",
	"Copyright (C) 2011 Kais Dukes",
	"CHANGING IT IS NOT ALLOWED",
	"corpus.quran.com",
}

// requireCorpusMorphology refuses to run without the upstream file, and refuses a
// copy whose copyright block has been removed.
func requireCorpusMorphology(path string) error {
	b, err := os.ReadFile(path)
	if errors.Is(err, fs.ErrNotExist) {
		return fmt.Errorf(`%s is missing, and this ingest will not download it.

%s serves a form, not the file: it asks for an email address and for the terms of
use to be accepted before it hands over %s. Accepting those terms is a person
taking the licence, so it is not something to work around.

  1. open %s
  2. give an email address and accept the terms
  3. save %s at %s

Then run this again. Everything else downloads on its own.`,
			path, corpusPage, corpusFile, corpusPage, corpusFile, path)
	}
	if err != nil {
		return err
	}
	head := string(b[:min(len(b), 8192)])
	for _, marker := range copyrightMarkers {
		if !strings.Contains(head, marker) {
			return fmt.Errorf("%s does not carry %q in its header. The file distributed at %s "+
				"opens with a copyright block; a copy without it is an edited fork, and the terms "+
				"permit verbatim copies only and require the notice to be kept. Replace it with the "+
				"file from %s", path, marker, corpusPage, corpusPage)
		}
	}
	return nil
}

func readJSON(path string, v any) error {
	b, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	if err := json.Unmarshal(b, v); err != nil {
		return fmt.Errorf("%s: %w", path, err)
	}
	return nil
}

func readChapters(dir string) ([]chapter, error) {
	var cf chaptersFile
	if err := readJSON(filepath.Join(dir, "chapters.json"), &cf); err != nil {
		return nil, err
	}
	if len(cf.Chapters) == 0 {
		return nil, fmt.Errorf("chapters.json carries no chapters")
	}
	return cf.Chapters, nil
}

// verify reads back what is on disk and refuses to write a manifest for a corpus
// that would mis-highlight. Nothing here trusts the download that just ran: a
// resumed run verifies files it did not fetch.
func verify(dir string, suras []int, chapters []chapter, now time.Time) (*manifest, error) {
	byID := map[int]chapter{}
	for _, ch := range chapters {
		byID[ch.ID] = ch
	}
	complete := len(suras) == 114

	if complete {
		if err := checkRevelationOrder(chapters); err != nil {
			return nil, err
		}
	}

	morphWords, morphSegs, roots, err := loadMorphologyCounts(filepath.Join(dir, corpusFile))
	if err != nil {
		return nil, err
	}

	m := &manifest{
		GeneratedAt: now.UTC().Format(time.RFC3339),
		Complete:    complete,
		Suras:       suras,
		Sources:     sourceURLs,
		Counts:      counts{Surahs: len(suras), MorphologySegments: morphSegs, Roots: roots},
	}

	var problems []string
	for _, n := range suras {
		ch, ok := byID[n]
		if !ok {
			return nil, fmt.Errorf("sura %d is not in chapters.json", n)
		}
		wordCount, err := countWords(dir, ch)
		if err != nil {
			return nil, err
		}
		for key, n := range wordCount {
			m.Counts.Ayahs++
			m.Counts.Words += n
			if mw, ok := morphWords[key]; ok && mw != n {
				problems = append(problems, fmt.Sprintf(
					"%s: %d words in the text but %d in the morphology", key, n, mw))
			}
		}
		if err := countSegments(dir, ch, wordCount, m, &problems); err != nil {
			return nil, err
		}
	}
	m.Reconciliation.AyahsWhereWordNumberingDisagrees = len(problems)
	if len(problems) > 0 {
		return nil, fmt.Errorf("word text and segment timings come from two different segmentations, "+
			"which mis-highlights every word after the split — %d ayas disagree:\n  %s",
			len(problems), strings.Join(capped(problems, 10), "\n  "))
	}

	files, err := checksums(dir, suras)
	if err != nil {
		return nil, err
	}
	m.Files = files
	return m, nil
}

// checkRevelationOrder guards the app's default reading order: a duplicated or
// missing chronological rank sends the reader to the wrong sura next.
func checkRevelationOrder(chapters []chapter) error {
	seen := map[int]int{}
	for _, ch := range chapters {
		if ch.RevelationOrder < 1 || ch.RevelationOrder > 114 {
			return fmt.Errorf("sura %d has revelation_order %d, outside 1..114", ch.ID, ch.RevelationOrder)
		}
		if other, dup := seen[ch.RevelationOrder]; dup {
			return fmt.Errorf("suras %d and %d share revelation_order %d", other, ch.ID, ch.RevelationOrder)
		}
		seen[ch.RevelationOrder] = ch.ID
	}
	if len(seen) != 114 {
		return fmt.Errorf("revelation_order covers %d suras, not 114", len(seen))
	}
	return nil
}

// countWords returns words per aya, counting what the app renders: the
// end-of-aya glyph is a word to the API and not to a reader.
func countWords(dir string, ch chapter) (map[string]int, error) {
	var vf versesFile
	path := filepath.Join(dir, "verses", fmt.Sprintf("%03d.json", ch.ID))
	if err := readJSON(path, &vf); err != nil {
		return nil, err
	}
	if vf.Pagination.NextPage != nil {
		return nil, fmt.Errorf("%s: the sura is longer than one page, so the file is short by design", path)
	}
	if len(vf.Verses) != ch.VersesCount {
		return nil, fmt.Errorf("%s: %d ayas on disk, %d in chapters.json", path, len(vf.Verses), ch.VersesCount)
	}
	out := make(map[string]int, len(vf.Verses))
	for _, v := range vf.Verses {
		n := 0
		for _, w := range v.Words {
			if w.CharTypeName == "word" {
				n++
			}
		}
		if n == 0 {
			return nil, fmt.Errorf("%s: aya %s has no words", path, v.VerseKey)
		}
		out[v.VerseKey] = n
	}
	return out, nil
}

// countSegments asserts the tuple shape before reading a millisecond from it.
//
// A tuple is [word_start_index, word_end_index, start_ms, end_ms]: zero-based,
// the end index exclusive, over the same word numbering the word source uses.
// The published documentation says [segment_index, start_ms, end_ms], and a
// parser that believes it reads a word index as a timestamp and highlights the
// wrong word everywhere. Reading element 1 as a one-based word position is the
// subtler version of the same mistake: it agrees with the real shape for every
// segment that covers exactly one word, which is all but 27 of them, and drops
// the timing of the other 61 words.
//
// The assertion that separates the readings is that both indices are word
// indices: a millisecond in either slot lands far past the last word.
func countSegments(dir string, ch chapter, wordCount map[string]int, m *manifest, problems *[]string) error {
	var sf segmentsFile
	path := filepath.Join(dir, "segments", fmt.Sprintf("%03d.json", ch.ID))
	if err := readJSON(path, &sf); err != nil {
		return err
	}
	if sf.Pagination.NextPage != nil {
		return fmt.Errorf("%s: the timings run past one page, so the file is short by design", path)
	}
	if len(sf.AudioFiles) != ch.VersesCount {
		return fmt.Errorf("%s: %d audio files, %d ayas in the sura", path, len(sf.AudioFiles), ch.VersesCount)
	}

	for _, af := range sf.AudioFiles {
		words, ok := wordCount[af.VerseKey]
		if !ok {
			return fmt.Errorf("%s: timings for %s, which the word source does not have", path, af.VerseKey)
		}
		m.Counts.AudioFiles++

		timed := make(map[int]bool, words)
		prevTo, prevEnd := 0, -1
		for _, t := range af.Segments {
			if len(t) != 4 {
				return fmt.Errorf("%s: aya %s has a %d-element segment %v; this parser reads "+
					"[word_start_index, word_end_index, start_ms, end_ms] and the shape has changed under it",
					path, af.VerseKey, len(t), t)
			}
			from, to, start, end := t[0], t[1], t[2], t[3]
			if from < 0 || to <= from || from < prevTo {
				*problems = append(*problems, fmt.Sprintf(
					"%s: segment [%d,%d) does not follow [_,%d) as a walk over the words",
					af.VerseKey, from, to, prevTo))
				break
			}
			if to > words+1 {
				*problems = append(*problems, fmt.Sprintf(
					"%s: a segment ends after word %d of %d", af.VerseKey, to, words))
				break
			}
			m.Counts.SegmentTuples++
			if end < start {
				// 3:22 ends a word ten milliseconds before it starts. The ETL clamps it;
				// refusing the whole corpus over it would be worse than counting it.
				m.Reconciliation.SegmentsEndingBeforeTheyStart++
			}
			if prevEnd >= 0 && start < prevEnd {
				m.Reconciliation.OverlappingSegmentPairs++
			}
			// The reciter's phrasing splits a word the text keeps whole in five ayas,
			// all of them muqatta'at. The ETL folds that trailing segment into the last
			// word; here it is counted, because the same symptom at scale is two
			// segmentations rather than one reciter.
			last := to
			if to == words+1 {
				m.Reconciliation.AyahsWithASegmentPastTheLastWord++
				last = words
			}
			if last-from > 1 {
				m.Reconciliation.MultiWordSegmentSpans++
				m.Reconciliation.WordsTimedOnlyByAMultiWordSpan += last - from - 1
			}
			for i := from; i < last; i++ {
				timed[i+1] = true
			}
			prevTo, prevEnd = to, end
		}

		// A word with no timing is a highlight that freezes mid-aya. Counting them is
		// what keeps a silent gap from passing for working audio.
		missing := 0
		for i := 1; i <= words; i++ {
			if !timed[i] {
				missing++
			}
		}
		m.Counts.WordsTimed += words - missing
		if missing > 0 {
			m.Reconciliation.WordsWithNoTiming += missing
			m.Reconciliation.AyahsWithAnUntimedWord++
		}
	}
	return nil
}

// loadMorphologyCounts returns words per aya keyed "surah:ayah", total segments
// and distinct roots. The word count is the one that matters: it is the third
// segmentation in the pipeline and the one that historically disagreed.
func loadMorphologyCounts(path string) (map[string]int, int, int, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, 0, 0, err
	}
	defer f.Close()

	words := map[string]map[int]bool{}
	roots := map[string]bool{}
	segments := 0
	sc := bufio.NewScanner(f)
	sc.Buffer(make([]byte, 0, 64*1024), 1024*1024)
	for sc.Scan() {
		line := strings.TrimRight(sc.Text(), "\r")
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		cols := strings.Split(line, "\t")
		if len(cols) < 4 {
			continue
		}
		loc := strings.Split(strings.Trim(cols[0], "()"), ":")
		if len(loc) != 4 {
			continue
		}
		su, err1 := strconv.Atoi(loc[0])
		ay, err2 := strconv.Atoi(loc[1])
		wd, err3 := strconv.Atoi(loc[2])
		if err1 != nil || err2 != nil || err3 != nil {
			continue
		}
		segments++
		key := fmt.Sprintf("%d:%d", su, ay)
		if words[key] == nil {
			words[key] = map[int]bool{}
		}
		words[key][wd] = true
		for _, ft := range strings.Split(cols[3], "|") {
			if r, ok := strings.CutPrefix(ft, "ROOT:"); ok {
				roots[r] = true
			}
		}
	}
	if err := sc.Err(); err != nil {
		return nil, 0, 0, err
	}
	out := make(map[string]int, len(words))
	for k, set := range words {
		out[k] = len(set)
	}
	return out, segments, len(roots), nil
}

func checksums(dir string, suras []int) ([]fileSum, error) {
	paths := []string{"chapters.json", corpusFile}
	for _, n := range suras {
		paths = append(paths, fmt.Sprintf("verses/%03d.json", n), fmt.Sprintf("segments/%03d.json", n))
	}
	sort.Strings(paths)

	out := make([]fileSum, 0, len(paths))
	for _, rel := range paths {
		f, err := os.Open(filepath.Join(dir, rel))
		if err != nil {
			return nil, err
		}
		h := sha256.New()
		n, err := io.Copy(h, f)
		f.Close()
		if err != nil {
			return nil, err
		}
		out = append(out, fileSum{Path: "data/raw/" + rel, Bytes: n, SHA256: hex.EncodeToString(h.Sum(nil))})
	}
	return out, nil
}

func capped(s []string, n int) []string {
	if len(s) <= n {
		return s
	}
	return append(s[:n:n], fmt.Sprintf("… and %d more", len(s)-n))
}
