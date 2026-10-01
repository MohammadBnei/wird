package main

import (
	"database/sql"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestAFixtureWordReadsItsNeighboursFrenchOrNone(t *testing.T) {
	c := load(t, fixtureDir)
	if c.FrenchGlossesMissed != 0 {
		t.Errorf("%d fixture words matched no French card, want 0", c.FrenchGlossesMissed)
	}
	db, err := sql.Open("sqlite", build(t, fixtureDir))
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	var fr string
	// 103:2, third word لَفِى — its own card, not its neighbour's.
	if err := db.QueryRow(`SELECT gloss_fr FROM words WHERE id = 103002003`).Scan(&fr); err != nil {
		t.Fatal(err)
	}
	if fr != "est certes dans" {
		t.Errorf("103:2:3 gloss_fr = %q, want %q", fr, "est certes dans")
	}
}

func TestAFrenchGlossIsNeverPinnedToTheWrongWord(t *testing.T) {
	// The page skips the second word, as 2:54 skips ذَٰلِكُمْ. By position the
	// third word would read the second card; by its Arabic it reads its own.
	words := []Word{
		{AyahID: 2054, Position: 1, TextAr: "إِنَّكُمْ"},
		{AyahID: 2054, Position: 2, TextAr: "ذَٰلِكُمْ"},
		{AyahID: 2054, Position: 3, TextAr: "خَيْرٌ"},
	}
	cards := map[int][]tldWord{2054: {
		{Arabic: "إِنَّكُمْ", French: "vous"},
		{Arabic: "خَيْرٌ", French: "meilleur"},
	}}
	if missed := pinFrenchGlosses(words, cards); missed != 1 {
		t.Errorf("missed %d, want 1", missed)
	}
	got := []string{words[0].GlossFr, words[1].GlossFr, words[2].GlossFr}
	want := []string{"vous", "", "meilleur"}
	for i := range want {
		if got[i] != want[i] {
			t.Errorf("word %d gloss_fr = %q, want %q", i+1, got[i], want[i])
		}
	}
}

func TestAWordSpelledWithMaddaLosesItsFrenchToTheCardsSpelling(t *testing.T) {
	// quran.com writes إِلَّآ where the pages write إِلَّا, in 2:237 and three more.
	words := []Word{{AyahID: 2237, Position: 1, TextAr: "إِلَّآ"}}
	cards := map[int][]tldWord{2237: {{Arabic: "إِلَّا", French: "sauf"}}}
	if pinFrenchGlosses(words, cards); words[0].GlossFr != "sauf" {
		t.Errorf("gloss_fr = %q, want %q", words[0].GlossFr, "sauf")
	}
}

func TestACorpusFrenchForSomeAyasAndEnglishForOthersIsRefused(t *testing.T) {
	dir := t.TempDir()
	copyTree(t, fixtureDir, dir)
	// Sura 114's page did not arrive.
	if err := os.Remove(filepath.Join(dir, tldDir, "sourate-nas-mot-a-mot-francais.html")); err != nil {
		t.Fatal(err)
	}
	err := load(t, dir).Check(false)
	if err == nil || !strings.Contains(err.Error(), "114:1") {
		t.Fatalf("Check = %v, want a refusal naming 114:1", err)
	}
}

func copyTree(t *testing.T, from, to string) {
	t.Helper()
	err := filepath.Walk(from, func(path string, fi os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		rel, _ := filepath.Rel(from, path)
		if fi.IsDir() {
			return os.MkdirAll(filepath.Join(to, rel), 0o755)
		}
		b, err := os.ReadFile(path)
		if err != nil {
			return err
		}
		return os.WriteFile(filepath.Join(to, rel), b, 0o644)
	})
	if err != nil {
		t.Fatal(err)
	}
}

// The failure: some suras' pages arrived with Pickthall's English and some
// without it, and an English reader meets a translation under one aya and
// nothing under the next.
func TestACorpusWithPickthallForSomeAyasOnlyIsShipped(t *testing.T) {
	c := load(t, fixtureDir)
	c.Ayahs[0].TextEn = "In the name of Allah, the Beneficent, the Merciful."
	err := c.Check(true)
	if err == nil || !strings.Contains(err.Error(), "Pickthall") {
		t.Fatalf("Check = %v, want a refusal of an English translation for some ayas only", err)
	}
}
