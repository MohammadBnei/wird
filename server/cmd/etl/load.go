package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"

	"github.com/MohammadBnei/wird/server/internal/timings"
)

// The morphology file, as corpus.quran.com distributes it. server/cmd/ingest
// refuses to run without it and checks that it still carries its copyright block.
const corpusFile = "quranic-corpus-morphology-0.4.txt"

// Ids are natural, never generated: a re-run of this ETL must not renumber what a
// shipped corpus.db already joins against.
func ayahID(surah, ayah int) int   { return surah*1000 + ayah }
func wordID(ayahID, pos int) int64 { return int64(ayahID)*1000 + int64(pos) }

type Surah struct {
	ID              int
	NameAr, NameEn  string
	AyahCount       int
	RevelationOrder int
	RevelationPlace string
}

type Ayah struct {
	ID, SurahID, Number int
	TextUthmani         string
}

type Word struct {
	ID                                           int64
	AyahID, Position                             int
	TextAr, Translit, GlossEn, RootLetters, Form string
	Morphology                                   string
}

type Root struct {
	Letters, Display, Translit string
	Occurrences                int
}

// Audio names the file an aya is recited in and nothing else. There is no
// duration: Wird does not host the recordings and does not index them, and a
// length derived from the last word's timing would be a number we made up.
type Audio struct {
	AyahID  int
	RelPath string
}

type Segment struct {
	WordID         int64
	StartMS, EndMS int
}

type Corpus struct {
	// The notices the data ships under, carried into corpus.db so they travel with
	// what the app actually installs: the morphology file's own copyright block,
	// and the attribution CC BY 4.0 asks for over the word timings.
	Notice string

	Surahs   []Surah
	Ayahs    []Ayah
	Words    []Word
	Roots    []Root
	Audio    []Audio
	Segments []Segment

	Clamped int // segments whose timings had to be pulled straight
	Orphans int // ayas whose timings could not be reconciled with the text
}

type rawChapters struct {
	Chapters []struct {
		ID              int    `json:"id"`
		NameArabic      string `json:"name_arabic"`
		NameSimple      string `json:"name_simple"`
		VersesCount     int    `json:"verses_count"`
		RevelationOrder int    `json:"revelation_order"`
		RevelationPlace string `json:"revelation_place"`
	} `json:"chapters"`
}

type rawVerses struct {
	Verses []struct {
		VerseKey    string `json:"verse_key"`
		VerseNumber int    `json:"verse_number"`
		TextUthmani string `json:"text_uthmani"`
		Words       []struct {
			Position     int    `json:"position"`
			CharTypeName string `json:"char_type_name"`
			TextUthmani  string `json:"text_uthmani"`
			Translation  struct {
				Text string `json:"text"`
			} `json:"translation"`
			Transliteration struct {
				Text *string `json:"text"`
			} `json:"transliteration"`
		} `json:"words"`
	} `json:"verses"`
}

func readJSON(path string, v any) error {
	f, err := os.Open(path)
	if err != nil {
		return err
	}
	defer f.Close()
	return json.NewDecoder(f).Decode(v)
}

func surahOf(verseKey string) (int, int, error) {
	s, a, ok := strings.Cut(verseKey, ":")
	if !ok {
		return 0, 0, fmt.Errorf("verse key %q is not surah:ayah", verseKey)
	}
	si, err := strconv.Atoi(s)
	if err != nil {
		return 0, 0, err
	}
	ai, err := strconv.Atoi(a)
	if err != nil {
		return 0, 0, err
	}
	return si, ai, nil
}

// Load reads one ingest directory: chapters.json, verses/NNN.json,
// timings/NAME.json and the morphology file. Word text and word timings are
// numbered by two different projects, and internal/timings is what reconciles
// them: that reconciliation is the only thing keeping a highlight on the word it
// belongs to.
func Load(dir, recitation, timingsFile string) (*Corpus, error) {
	var chapters rawChapters
	if err := readJSON(filepath.Join(dir, "chapters.json"), &chapters); err != nil {
		return nil, err
	}
	morph, err := loadMorphology(filepath.Join(dir, corpusFile))
	if err != nil {
		return nil, err
	}
	segs, err := timings.Load(filepath.Join(dir, "timings", timingsFile+".json"))
	if err != nil {
		return nil, err
	}

	c := &Corpus{Notice: morph.notice + "\n\n" + timings.Notice(timingsFile+".json")}
	rootCount := map[string]int{}
	wordsPerAyah := map[int]int{}

	for _, ch := range chapters.Chapters {
		c.Surahs = append(c.Surahs, Surah{
			ID: ch.ID, NameAr: ch.NameArabic, NameEn: ch.NameSimple,
			AyahCount: ch.VersesCount, RevelationOrder: ch.RevelationOrder,
			RevelationPlace: ch.RevelationPlace,
		})

		var verses rawVerses
		if err := readJSON(filepath.Join(dir, "verses", fmt.Sprintf("%03d.json", ch.ID)), &verses); err != nil {
			return nil, err
		}
		for _, v := range verses.Verses {
			su, ay, err := surahOf(v.VerseKey)
			if err != nil {
				return nil, err
			}
			aid := ayahID(su, ay)
			c.Ayahs = append(c.Ayahs, Ayah{ID: aid, SurahID: su, Number: ay, TextUthmani: v.TextUthmani})
			pos := 0
			for _, w := range v.Words {
				if w.CharTypeName != "word" { // the ayah-number glyph is not a word
					continue
				}
				pos++
				translit := ""
				if w.Transliteration.Text != nil {
					translit = *w.Transliteration.Text
				}
				m := morph.words[[2]int{aid, pos}]
				if m.root != "" {
					rootCount[m.root]++
				}
				c.Words = append(c.Words, Word{
					ID: wordID(aid, pos), AyahID: aid, Position: pos,
					TextAr: w.TextUthmani, Translit: translit, GlossEn: w.Translation.Text,
					RootLetters: m.root, Form: m.form, Morphology: m.json,
				})
			}
			wordsPerAyah[aid] = pos
			if n := morph.counts[aid]; n != 0 && n != pos {
				return nil, fmt.Errorf("aya %s: %d words in the text but %d in the morphology; "+
					"mixing two segmentations mis-highlights every word after the split", v.VerseKey, pos, n)
			}
		}

		for ayah := 1; ayah <= ch.VersesCount; ayah++ {
			aid := ayahID(ch.ID, ayah)
			c.Audio = append(c.Audio, Audio{AyahID: aid, RelPath: relPath(recitation, ch.ID, ayah)})
			spans, err := timings.Spans(segs[[2]int{ch.ID, ayah}], wordsPerAyah[aid])
			if err != nil {
				return nil, fmt.Errorf("aya %d:%d: %w", ch.ID, ayah, err)
			}
			n := normalizeSegments(spans, aid)
			c.Segments = append(c.Segments, n.segments...)
			c.Clamped += n.clamped
		}
	}

	for letters, n := range rootCount {
		c.Roots = append(c.Roots, Root{
			Letters: letters, Display: spaced(letters), Translit: translitRoot(letters), Occurrences: n,
		})
	}
	sort.Slice(c.Roots, func(i, j int) bool { return c.Roots[i].Letters < c.Roots[j].Letters })
	return c, nil
}

// relPath keeps the audio origin out of the shipped asset: a host frozen into an
// immutable bundle costs an App Store release the day it moves. Every per-aya
// archive of this recitation names its files by sura and aya, three digits each.
func relPath(recitation string, surah, ayah int) string {
	return fmt.Sprintf("%s/%03d%03d.mp3", recitation, surah, ayah)
}

type normalized struct {
	segments []Segment
	clamped  int
}

// normalizeSegments turns reconciled spans into rows, one per word. The 27 spans
// the aligner could not split cover more than one word each; a parser that writes
// one row per span leaves the other 61 words untimed and their highlight frozen.
//
// Starts are made non-decreasing. Overlaps are left alone: 141 ayas legitimately
// overlap, and pulling them apart would shorten a word the reciter really did run
// into the next.
func normalizeSegments(spans []timings.Span, aid int) normalized {
	var n normalized
	prevStart := 0
	for _, sp := range spans {
		s, e := sp.StartMS, sp.EndMS
		if s < prevStart {
			s = prevStart
		}
		if e < s {
			e = s
		}
		if s != sp.StartMS || e != sp.EndMS {
			n.clamped++
		}
		prevStart = s
		for w := sp.FirstWord; w <= sp.LastWord; w++ {
			n.segments = append(n.segments, Segment{WordID: wordID(aid, w), StartMS: s, EndMS: e})
		}
	}
	return n
}

type wordMorph struct {
	root, form, json string
}

type morphology struct {
	notice string
	words  map[[2]int]wordMorph
	counts map[int]int // words per ayah id, to catch a second segmentation sneaking in
}

// Buckwalter, the transliteration the morphology file is published in. Only the
// 28 letters a root can be made of: roots are the one field that has to come back
// as Arabic, because they key the roots table and open the root panel.
//
// A radical is never a bare alef — the published root alphabet folds every hamza
// onto A, and corpus.quran.com renders it back as أ, so أ is what a reader is shown
// (ق ر أ, not ق ر ا). The seat is lost with the fold: لؤلؤ comes back as لألأ.
var buckwalterArabic = map[rune]rune{
	'A': 'أ', 'b': 'ب', 't': 'ت', 'v': 'ث', 'j': 'ج', 'H': 'ح', 'x': 'خ',
	'd': 'د', '*': 'ذ', 'r': 'ر', 'z': 'ز', 's': 'س', '$': 'ش', 'S': 'ص',
	'D': 'ض', 'T': 'ط', 'Z': 'ظ', 'E': 'ع', 'g': 'غ', 'f': 'ف', 'q': 'ق',
	'k': 'ك', 'l': 'ل', 'm': 'م', 'n': 'ن', 'h': 'ه', 'w': 'و', 'y': 'ي',
}

// verbForm reads the derived form, which the file writes as a roman numeral in
// parentheses. It tags II to XII and never I, so a verb carrying no tag is Form I:
// read as "no form", the label goes blank on 14,555 words. Only verbs — a
// participle of a Form I verb is not itself a verb form.
func verbForm(features []string) string {
	verb := false
	for _, ft := range features {
		if strings.HasPrefix(ft, "(") && strings.HasSuffix(ft, ")") {
			return strings.Trim(ft, "()")
		}
		verb = verb || ft == "POS:V"
	}
	if verb {
		return "I"
	}
	return ""
}

func arabicRoot(buckwalter string) string {
	var b strings.Builder
	for _, r := range buckwalter {
		if a, ok := buckwalterArabic[r]; ok {
			b.WriteRune(a)
		} else {
			return "" // a letter no root is built from: not a root
		}
	}
	return b.String()
}

type morphSegment struct {
	Form     string   `json:"form"`
	POS      string   `json:"pos"`
	Features []string `json:"features"`
}

// loadMorphology reads the Quranic Arabic Corpus morphology table, one line per
// segment, and folds it into one row per word. The file is read and never written:
// its terms permit verbatim copies only, and a derived database is a different act
// from an edited copy.
//
// Forms, lemmas and tags stay in the Buckwalter transliteration the file publishes.
// ponytail: decode them the way roots are decoded if a screen ever renders them.
func loadMorphology(path string) (morphology, error) {
	f, err := os.Open(path)
	if err != nil {
		return morphology{}, err
	}
	defer f.Close()

	segs := map[[2]int][]morphSegment{}
	roots := map[[2]int]string{}
	forms := map[[2]int]string{}
	var notice []string
	header := true
	sc := bufio.NewScanner(f)
	sc.Buffer(make([]byte, 0, 64*1024), 1024*1024)
	for sc.Scan() {
		line := strings.TrimRight(sc.Text(), "\r")
		if header {
			if line == "" || strings.HasPrefix(line, "#") {
				notice = append(notice, line)
				continue
			}
			header = false
		}
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
		key := [2]int{ayahID(su, ay), wd}
		features := strings.Split(cols[3], "|")
		segs[key] = append(segs[key], morphSegment{Form: cols[1], POS: cols[2], Features: features})
		for _, ft := range features {
			if r, ok := strings.CutPrefix(ft, "ROOT:"); ok && roots[key] == "" {
				roots[key] = arabicRoot(r)
			}
		}
		if forms[key] == "" {
			forms[key] = verbForm(features)
		}
	}
	if err := sc.Err(); err != nil {
		return morphology{}, err
	}

	m := morphology{
		notice: strings.TrimSpace(strings.Join(notice, "\n")),
		words:  map[[2]int]wordMorph{},
		counts: map[int]int{},
	}
	for key, list := range segs {
		b, err := json.Marshal(list)
		if err != nil {
			return morphology{}, err
		}
		m.words[key] = wordMorph{root: roots[key], form: forms[key], json: string(b)}
		m.counts[key[0]]++
	}
	return m, nil
}

func spaced(letters string) string {
	return strings.Join(strings.Split(letters, ""), " ")
}

var arabicLatin = map[rune]string{
	'ء': "ʾ", 'آ': "ā", 'أ': "ʾ", 'ؤ': "ʾ", 'إ': "ʾ", 'ئ': "ʾ", 'ا': "ā", 'ب': "b",
	'ة': "t", 'ت': "t", 'ث': "th", 'ج': "j", 'ح': "ḥ", 'خ': "kh", 'د': "d", 'ذ': "dh",
	'ر': "r", 'ز': "z", 'س': "s", 'ش': "sh", 'ص': "ṣ", 'ض': "ḍ", 'ط': "ṭ", 'ظ': "ẓ",
	'ع': "ʿ", 'غ': "gh", 'ف': "f", 'ق': "q", 'ك': "k", 'ل': "l", 'م': "m", 'ن': "n",
	'ه': "h", 'و': "w", 'ى': "y", 'ي': "y",
}

func translitRoot(letters string) string {
	parts := make([]string, 0, len([]rune(letters)))
	for _, r := range letters {
		if s, ok := arabicLatin[r]; ok {
			parts = append(parts, s)
		} else {
			parts = append(parts, string(r))
		}
	}
	return strings.Join(parts, "-")
}
