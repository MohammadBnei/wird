package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
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

	// One translation, in French, as a reader meets it. Empty when the ingest
	// was run without it; Check refuses a corpus where only some ayas carry one,
	// because a reading that is French for a page and then English is worse than
	// one that is honestly English throughout.
	TextFr string

	// Pickthall's English, 1930, public domain by age (data/SOURCES.md). Held
	// to the same all-or-none rule as the French.
	TextEn string
}

// The resource id of Rashid Maash's French, which is what quran.com identifies a
// translation by. There is no French word-by-word gloss anywhere on quran.com —
// `language=fr` answers English and says `language_name: "english"` while doing
// it — so the French under each word comes from elsewhere (glosses_fr.go).
// data/SOURCES.md has the provenance and the licence position of both.
const frenchTranslation = 779

// Marmaduke Pickthall's English, quran.com's resource 19.
const englishTranslation = 19

// footnote is the markup quran.com wraps a translator's note in:
// `<sup foot_note=203920>1</sup>`. The note itself is in no field of the
// response, so the marker points at nothing a reader could open. It is dropped
// rather than left to render as a stray digit mid-sentence, and SOURCES.md
// records the drop because removing it is a modification of the text.
var footnote = regexp.MustCompile(`<sup[^>]*>.*?</sup>`)

type Word struct {
	ID                                           int64
	AyahID, Position                             int
	TextAr, Translit, GlossEn, RootLetters, Form string
	Morphology                                   string

	// The word's French, from The Last Dialogue's pages (glosses_fr.go). Empty
	// where no card on those pages is this word; the reader then sees GlossEn.
	GlossFr string

	// The word spoken on its own, relative to quran.com's word-by-word host.
	// Built from the position: the host numbers its files by word. The API's
	// own audio_url counts the pause marks as words, so after the first mark
	// in an aya it names the next word's file, or one that does not exist
	// (ADR 0029).
	WbwPath string

	// The lemma of the segment the root came from: LemmaKey as the corpus
	// writes it, digit and all, for grouping; Lemma decoded for the reader.
	// Empty on a word with no root.
	LemmaKey, Lemma string
}

type Root struct {
	Letters, Display, Translit string
	Occurrences                int
}

// Audio names the file an aya is recited in and nothing else. There is no
// duration: Wird does not host the recordings and does not index them, and a
// length derived from the last word's timing would be a number we made up.
//
// One row per aya for every reciter: everyayah names an aya's file the same
// way in each reciter's folder, and the folder is the app's to know, beside
// the host it lives on.
type Audio struct {
	AyahID  int
	RelPath string
}

type Segment struct {
	WordID         int64
	StartMS, EndMS int
}

// Recitation is one of quran-align's recordings: the slug the app keys it by,
// the timings file it was aligned as, and who recites it.
type Recitation struct {
	Slug, Timings, ReciterName, Style string
}

// defaultSlug is the reciter a fresh install hears. Check refuses a corpus
// without it, because the app falls back to it.
const defaultSlug = "husary-muallim"

// Recitations are the ones ingest's defaultRecitations extracts. The other six
// of quran-align's twelve do not pass and ADR 0023 lists why.
var Recitations = []Recitation{
	{defaultSlug, "Husary_Muallim_128kbps", "Mahmoud Khalil Al-Husary", "Muallim"},
	{"husary", "Husary_64kbps", "Mahmoud Khalil Al-Husary", "Murattal"},
	{"alafasy", "Alafasy_128kbps", "Mishary Rashid Alafasy", "Murattal"},
	{"abdul-basit-murattal", "Abdul_Basit_Murattal_64kbps", "Abdul Basit Abdus Samad", "Murattal"},
	{"shaatree", "Abu_Bakr_Ash-Shaatree_128kbps", "Abu Bakr Ash-Shaatree", "Murattal"},
	{"hani-rifai", "Hani_Rifai_192kbps", "Hani Ar-Rifai", "Murattal"},
}

// maxUntimedWords is how many words one recitation may leave without a
// timing before it is refused. An untimed word holds the previous highlight
// while it is recited, which reads as a lag; across a whole recitation a few
// dozen are tolerable and hundreds are not. Husary Muallim, the reciter this
// app shipped with, leaves 22.
//
// ponytail: one figure for the whole recitation, not a share per aya. Make it
// per aya the day one reciter concentrates its gaps in a single sura.
const maxUntimedWords = 100

// Recited is one recitation that passed, with its rows.
type Recited struct {
	Recitation
	Segments []Segment
	Untimed  int
	Clamped  int
}

type Corpus struct {
	// The notices the data ships under, carried into corpus.db so they travel with
	// what the app actually installs: the morphology file's own copyright block,
	// and the attribution CC BY 4.0 asks for over the word timings.
	Notice string

	Surahs []Surah
	Ayahs  []Ayah
	Words  []Word
	Roots  []Root
	Audio  []Audio

	// The recitations that passed, and the ones refused with the reason.
	Recited []Recited
	Refused []string

	// One row per morphological segment: the parsing a reader is shown, derived
	// from the same lines Words.Morphology keeps verbatim.
	Irab []IrabRow

	// The senses Wird wrote for its roots, checked once when they were written
	// and checked again by Check before any of them reaches corpus.db.
	Senses *Senses

	// Words no French card matched, which a French reader reads in English.
	FrenchGlossesMissed int

	Orphans int // segments that name a word the corpus does not have
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
		VerseKey     string `json:"verse_key"`
		VerseNumber  int    `json:"verse_number"`
		TextUthmani  string `json:"text_uthmani"`
		Translations []struct {
			ResourceID int    `json:"resource_id"`
			Text       string `json:"text"`
		} `json:"translations"`
		Words []struct {
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

// wbwPath is where quran.com keeps a word spoken alone, relative to its host.
func wbwPath(surah, ayah, pos int) string {
	return fmt.Sprintf("wbw/%03d_%03d_%03d.mp3", surah, ayah, pos)
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
// timings/NAME.json for each recitation, and the morphology file. Word text and
// word timings are numbered by two different projects, and internal/timings is
// what reconciles them: that reconciliation is the only thing keeping a
// highlight on the word it belongs to. A recitation it cannot reconcile is
// refused and left out, and the others are kept.
func Load(dir string, recitations []Recitation) (*Corpus, error) {
	var chapters rawChapters
	if err := readJSON(filepath.Join(dir, "chapters.json"), &chapters); err != nil {
		return nil, err
	}
	morph, err := loadMorphology(filepath.Join(dir, corpusFile))
	if err != nil {
		return nil, err
	}
	c := &Corpus{Notice: morph.notice}
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
			fr, en := "", ""
			for _, t := range v.Translations {
				text := strings.TrimSpace(footnote.ReplaceAllString(t.Text, ""))
				switch t.ResourceID {
				case frenchTranslation:
					fr = text
				case englishTranslation:
					en = text
				}
			}
			c.Ayahs = append(c.Ayahs, Ayah{
				ID: aid, SurahID: su, Number: ay,
				TextUthmani: v.TextUthmani, TextFr: fr, TextEn: en,
			})
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
				wid := wordID(aid, pos)
				c.Words = append(c.Words, Word{
					ID: wid, AyahID: aid, Position: pos, WbwPath: wbwPath(su, ay, pos),
					TextAr: w.TextUthmani, Translit: translit, GlossEn: w.Translation.Text,
					RootLetters: m.root, Form: m.form, Morphology: m.json,
					LemmaKey: m.lemmaKey, Lemma: m.lemma,
				})
				for i, seg := range m.segments {
					c.Irab = append(c.Irab, irabRow(wid, i+1, seg))
				}
			}
			wordsPerAyah[aid] = pos
			if n := morph.counts[aid]; n != 0 && n != pos {
				return nil, fmt.Errorf("aya %s: %d words in the text but %d in the morphology; "+
					"mixing two segmentations mis-highlights every word after the split", v.VerseKey, pos, n)
			}
		}

		for ayah := 1; ayah <= ch.VersesCount; ayah++ {
			c.Audio = append(c.Audio, Audio{AyahID: ayahID(ch.ID, ayah), RelPath: relPath(ch.ID, ayah)})
		}
	}

	for _, rec := range recitations {
		r, err := loadRecitation(dir, rec, c.Surahs, wordsPerAyah)
		if err != nil {
			c.Refused = append(c.Refused, fmt.Sprintf("%s (%s): %v", rec.Slug, rec.Timings, err))
			continue
		}
		c.Recited = append(c.Recited, r)
		c.Notice += "\n\n" + timings.Notice(rec.Timings+".json")
	}

	glosses, err := loadFrenchGlosses(dir)
	if err != nil {
		return nil, err
	}
	if glosses != nil {
		c.FrenchGlossesMissed = pinFrenchGlosses(c.Words, glosses)
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
// archive names its files by sura and aya, three digits each, and the reciter's
// folder is the app's to add.
func relPath(surah, ayah int) string {
	return fmt.Sprintf("%03d%03d.mp3", surah, ayah)
}

// loadRecitation reconciles one recitation's timings with the text, or says
// why it cannot ship.
func loadRecitation(dir string, rec Recitation, surahs []Surah, wordsPerAyah map[int]int) (Recited, error) {
	r := Recited{Recitation: rec}
	segs, err := timings.Load(filepath.Join(dir, "timings", rec.Timings+".json"))
	if err != nil {
		return r, err
	}
	for _, su := range surahs {
		for ayah := 1; ayah <= su.AyahCount; ayah++ {
			aid := ayahID(su.ID, ayah)
			raw, ok := segs[[2]int{su.ID, ayah}]
			// A missing aya and an aya with no segments are the same to a reader:
			// it plays with no highlight at all.
			if !ok || len(raw) == 0 {
				return r, fmt.Errorf("aya %d:%d has no timing, so it would play with no highlight", su.ID, ayah)
			}
			spans, err := timings.Spans(raw, wordsPerAyah[aid])
			if err != nil {
				return r, fmt.Errorf("aya %d:%d: %w", su.ID, ayah, err)
			}
			n := normalizeSegments(spans, aid)
			r.Segments = append(r.Segments, n.segments...)
			r.Clamped += n.clamped
			timed := map[int64]bool{}
			for _, s := range n.segments {
				timed[s.WordID] = true
			}
			r.Untimed += wordsPerAyah[aid] - len(timed)
		}
	}
	if r.Untimed > maxUntimedWords {
		return r, fmt.Errorf("%d words have no timing, over the %d a recitation may leave "+
			"before its highlight reads as broken", r.Untimed, maxUntimedWords)
	}
	return r, nil
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
	root, lemmaKey, lemma, form, json string

	// The segments the json above holds, kept in the file's own order so the
	// iʿrāb table can be written without parsing back what was just written.
	segments []morphSegment
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

// lemmaOf is the LEM: feature of one segment, or "" when it has none.
func lemmaOf(features []string) string {
	for _, ft := range features {
		if l, ok := strings.CutPrefix(ft, "LEM:"); ok {
			return l
		}
	}
	return ""
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
// Forms and tags stay in the Buckwalter transliteration the file publishes;
// roots and lemmas are decoded, because the reading screen shows them.
func loadMorphology(path string) (morphology, error) {
	f, err := os.Open(path)
	if err != nil {
		return morphology{}, err
	}
	defer f.Close()

	segs := map[[2]int][]morphSegment{}
	roots := map[[2]int]string{}
	lemmas := map[[2]int]string{}
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
		// The fourth part of the location is the segment's own number, and the
		// iʿrāb table records a segment's place from its position in this list.
		// A file that numbers them any other way would silently label a
		// suffix's role as the stem's.
		if sg, err := strconv.Atoi(loc[3]); err != nil || sg != len(segs[key]) {
			return morphology{}, fmt.Errorf("segment %s is numbered %q but arrives at place %d of its "+
				"word; read in order, its parsing would be shown against another segment",
				cols[0], loc[3], len(segs[key]))
		}
		for _, ft := range features {
			if r, ok := strings.CutPrefix(ft, "ROOT:"); ok && roots[key] == "" {
				roots[key] = arabicRoot(r)
				// From this segment and no other: a word can carry a lemma on a
				// particle segment too (min + maA), and 20:94:2 has two stems
				// with two roots, of which the first is the one kept.
				lemmas[key] = lemmaOf(features)
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
		var lemma string
		if roots[key] != "" {
			if lemma, err = lemmaArabic(lemmas[key]); err != nil {
				return morphology{}, fmt.Errorf("%d:%d:%d: %w", key[0]/1000, key[0]%1000, key[1], err)
			}
		}
		m.words[key] = wordMorph{root: roots[key], lemmaKey: lemmas[key], lemma: lemma,
			form: forms[key], json: string(b), segments: list}
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
