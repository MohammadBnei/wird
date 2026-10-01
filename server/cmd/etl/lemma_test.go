package main

import (
	"os"
	"path/filepath"
	"testing"
)

func TestALemmaWithUthmaniMarksLosesThemOrComesBackAsSomethingElse(t *testing.T) {
	for key, want := range map[string]string{
		"r~aHiym":    "ر\u0651\u064Eح\u0650يم",
		"r~aHoma`n":  "ر\u0651\u064Eح\u0652م\u064E\u0670ن",
		">aroHaAm":   "أ\u064Eر\u0652ح\u064Eام",
		"say~i_#aAt": "س\u064Eي\u0651\u0650ـ\u0654\u064Eات",
		"yarojuwA@":  "ي\u064Eر\u0652ج\u064Fوا\u06DF",
		">an[bata":   "أ\u064Eن\u06E2ب\u064Eت\u064E",
		"baEol2":     "ب\u064Eع\u0652ل",
	} {
		got, err := lemmaArabic(key)
		if err != nil || got != want {
			t.Errorf("lemmaArabic(%q) = %q, %v; want %q", key, got, err, want)
		}
	}
}

func TestALemmaWithALetterTheTableDoesNotKnowIsShownWithoutIt(t *testing.T) {
	if got, err := lemmaArabic("ra?Hiym"); err == nil {
		t.Fatalf("lemmaArabic decoded an unknown letter to %q instead of refusing", got)
	}
}

// 20:94:2 is yā + ibna + umma: two stems, two roots. The word's root is the
// first, so its lemma has to be that stem's, not the last one read.
func TestAWordWithTwoStemsIsCountedUnderTheOtherStemsLemma(t *testing.T) {
	path := filepath.Join(t.TempDir(), "morph.txt")
	lines := "# header\n\n" +
		"(20:94:2:1)\tya\tVOC\tPREFIX|ya+\n" +
		"(20:94:2:2)\tbona\tN\tSTEM|POS:N|LEM:{bon|ROOT:bny|M|ACC\n" +
		"(20:94:2:3)\t&um~a\tN\tSTEM|POS:N|LEM:>um~|ROOT:Amm|FS|GEN\n" +
		"(20:94:2:4)\t\tPRON\tSUFFIX|PRON:1S\n" +
		"(7:50:12:1)\tmin\tP\tSTEM|POS:P|LEM:min\n" +
		"(7:50:12:2)\tmaA\tREL\tSTEM|POS:REL|LEM:maA\n"
	if err := os.WriteFile(path, []byte(lines), 0o644); err != nil {
		t.Fatal(err)
	}
	m, err := loadMorphology(path)
	if err != nil {
		t.Fatal(err)
	}
	w := m.words[[2]int{ayahID(20, 94), 2}]
	if w.lemmaKey != "{bon" || w.lemma != "\u0671ب\u0652ن" {
		t.Errorf("20:94:2 has lemma %q (%q), want {bon from the segment its root bny came from",
			w.lemmaKey, w.lemma)
	}
	if p := m.words[[2]int{ayahID(7, 50), 12}]; p.lemmaKey != "" {
		t.Errorf("a word with no root was given the lemma %q, and would be counted as a form", p.lemmaKey)
	}
}
