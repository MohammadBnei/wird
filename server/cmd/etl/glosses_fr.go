package main

import (
	"html"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"unicode"

	"golang.org/x/text/unicode/norm"
)

// French word glosses, from The Last Dialogue's "Coran Mot à Mot". quran.com has
// none (see load.go), and this is the one complete French word-by-word found.
// Used by permission; data/SOURCES.md quotes it.
//
// The source is web pages, one per sura and one per fifty ayas of the seven long
// ones, which server/cmd/ingest saves under data/raw/tld/. Each word is a card
// of four cells in a fixed order — a part-of-speech label, the Arabic, the
// French, a transliteration — under a "sura:aya" cell naming the aya.
const tldDir = "tld"

type tldWord struct{ Arabic, French string }

var (
	tldScript = regexp.MustCompile(`(?is)<(script|style)[^>]*>.*?</(script|style)>`)
	tldTag    = regexp.MustCompile(`<[^>]+>`)
	tldRef    = regexp.MustCompile(`^(\d{1,3}):(\d{1,3})$`)
	tldArabic = regexp.MustCompile(`[\x{0600}-\x{06FF}]`)
)

// The labels a card opens with, lowercased. The pages were written over time and
// spell them several ways; a label outside this set is not a card.
var tldLabels = map[string]bool{
	"nom": true, "nom propre": true, "nom / pronom": true, "pronom": true,
	"adjectif": true, "verbe": true, "particule": true, "particule (harf)": true,
	"particle": true,
}

// loadFrenchGlosses reads every saved page into the words of each aya, keyed by
// aya id. No directory is no French, not an error, and Check accepts a corpus
// with no French at all: it refuses only one that is French for some ayas.
func loadFrenchGlosses(dir string) (map[int][]tldWord, error) {
	pages, err := filepath.Glob(filepath.Join(dir, tldDir, "sourate-*.html"))
	if err != nil || len(pages) == 0 {
		return nil, err
	}
	out := map[int][]tldWord{}
	for _, page := range pages {
		b, err := os.ReadFile(page)
		if err != nil {
			return nil, err
		}
		for aid, words := range parseTLDPage(string(b)) {
			// The first page to carry an aya keeps it. No aya is on two pages
			// today; if one ever is, the sura page and its section page agree.
			if _, seen := out[aid]; !seen {
				out[aid] = words
			}
		}
	}
	return out, nil
}

func parseTLDPage(page string) map[int][]tldWord {
	text := html.UnescapeString(tldTag.ReplaceAllString(tldScript.ReplaceAllString(page, " "), "\x1f"))
	var cells []string
	for _, c := range strings.Split(text, "\x1f") {
		if c = strings.TrimSpace(c); c != "" {
			cells = append(cells, c)
		}
	}
	out := map[int][]tldWord{}
	aid := 0
	for i := 0; i < len(cells); i++ {
		if m := tldRef.FindStringSubmatch(cells[i]); m != nil {
			su, _ := strconv.Atoi(m[1])
			ay, _ := strconv.Atoi(m[2])
			aid = ayahID(su, ay)
			continue
		}
		if aid != 0 && tldLabels[strings.ToLower(cells[i])] && i+2 < len(cells) &&
			tldArabic.MatchString(cells[i+1]) {
			out[aid] = append(out[aid], tldWord{Arabic: cells[i+1], French: cells[i+2]})
			i += 3
		}
	}
	return out
}

// pinFrenchGlosses gives each word the French of the card whose Arabic is that
// word, and returns how many words were left without one.
//
// Matched by the Arabic and never by position. The pages skip a word here and
// there — 2:54 has no card for ذَٰلِكُمْ — and pairing by position would hand
// every later word in the aya its neighbour's meaning. So the two sequences are
// aligned on their letters (longest common subsequence), and a word with no
// matching card keeps its English gloss rather than borrowing someone else's.
func pinFrenchGlosses(words []Word, pages map[int][]tldWord) (unmatched int) {
	for start := 0; start < len(words); {
		end := start
		for end < len(words) && words[end].AyahID == words[start].AyahID {
			end++
		}
		cards := pages[words[start].AyahID]
		ours := make([]string, end-start)
		for i := range ours {
			ours[i] = letters(words[start+i].TextAr)
		}
		theirs := make([]string, len(cards))
		for i, c := range cards {
			theirs[i] = letters(c.Arabic)
		}
		for i, j := range alignLCS(ours, theirs) {
			if j >= 0 && strings.TrimSpace(cards[j].French) != "" {
				words[start+i].GlossFr = strings.TrimSpace(cards[j].French)
			} else {
				unmatched++
			}
		}
		start = end
	}
	return unmatched
}

// letters is the word reduced to its base letters, so two renderings of the
// same Uthmani word compare equal: decomposed, then every mark, pause sign and
// tatweel dropped. آ and ا then agree, which the pages and quran.com write
// differently in إِلَّآ.
func letters(s string) string {
	var b strings.Builder
	for _, r := range norm.NFD.String(s) {
		if unicode.Is(unicode.Lo, r) {
			b.WriteRune(r)
		}
	}
	return b.String()
}

// alignLCS pairs a with b along a longest common subsequence: out[i] is the index
// in b equal to a[i], or -1.
func alignLCS(a, b []string) []int {
	dp := make([][]int, len(a)+1)
	for i := range dp {
		dp[i] = make([]int, len(b)+1)
	}
	for i := len(a) - 1; i >= 0; i-- {
		for j := len(b) - 1; j >= 0; j-- {
			if a[i] == b[j] {
				dp[i][j] = dp[i+1][j+1] + 1
			} else {
				dp[i][j] = max(dp[i+1][j], dp[i][j+1])
			}
		}
	}
	out := make([]int, len(a))
	i, j := 0, 0
	for i < len(a) {
		switch {
		case j < len(b) && a[i] == b[j]:
			out[i] = j
			i++
			j++
		case j < len(b) && dp[i][j+1] >= dp[i+1][j]:
			j++
		default:
			out[i] = -1
			i++
		}
	}
	return out
}
