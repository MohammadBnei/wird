package main

import (
	"database/sql"
	"testing"
)

// The reader's before and after. Before this step al-ʿAṣr 3 word 4 drew "The
// parsing of this phrase is fetched per aya, and no aya has been downloaded
// yet"; after it, the three segments of وَعَمِلُوا are named from the bundle.
func TestTheParsingOfAWordIsFetchedPerAyaAndNoAyaHasBeenDownloaded(t *testing.T) {
	db, err := sql.Open("sqlite", build(t, fixtureDir))
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	rows, err := db.Query(`SELECT i.position, r.role_en, r.role_fr, i.features
	                         FROM irab i JOIN irab_roles r ON r.code = i.code
	                        WHERE i.word_id = ?
	                        ORDER BY i.position`, 103003004)
	if err != nil {
		t.Fatal(err)
	}
	defer rows.Close()

	type seg struct{ en, fr, features string }
	var got []seg
	for rows.Next() {
		var pos int
		var s seg
		if err := rows.Scan(&pos, &s.en, &s.fr, &s.features); err != nil {
			t.Fatal(err)
		}
		if pos != len(got)+1 {
			t.Fatalf("segment %d arrives at place %d", pos, len(got)+1)
		}
		got = append(got, s)
	}
	if err := rows.Err(); err != nil {
		t.Fatal(err)
	}

	want := []seg{
		{"Coordinating conjunction", "Conjonction de coordination", "PREFIX w:CONJ+"},
		{"Verb", "Verbe", "STEM PERF 3MP"},
		{"Personal pronoun", "Pronom personnel", "SUFFIX PRON:3MP"},
	}
	if len(got) != len(want) {
		t.Fatalf("word 103003004 has %d parsing rows, want %d: wa + Eamilu + wA is three segments",
			len(got), len(want))
	}
	for i := range want {
		if got[i] != want[i] {
			t.Errorf("segment %d reads %+v, want %+v", i+1, got[i], want[i])
		}
	}
}

// Every code either column uses has to be in the vocabulary in both languages,
// because an unnamed code reaches the reader as a blank where the role goes.
func TestASegmentIsCodedWithSomethingTheVocabularyDoesNotName(t *testing.T) {
	c := load(t, fixtureDir)
	c.Irab[0].Features += " NOT:A:ROLE"
	if err := c.Check(false); err == nil {
		t.Fatal("a segment coded with something nothing names passed the build")
	}
}

// The gate is per segment. A word keeps the rows of its other segments when one
// is dropped, so a per-word check passes on a parsing with a hole in it.
func TestAWordLosesOneSegmentsParsingAndKeepsTheOthers(t *testing.T) {
	c := load(t, fixtureDir)
	var kept []IrabRow
	for _, s := range c.Irab {
		if s.WordID == 103003004 && s.Position == 2 {
			continue // the verb in the middle of wa + Eamilu + wA
		}
		kept = append(kept, s)
	}
	c.Irab = kept
	if err := c.Check(false); err == nil {
		t.Fatal("a word whose middle segment has no parsing passed the build")
	}
}

// load.go's word-count guard reads `n != 0 && n != pos`, so an aya absent from
// the morphology file leaves every one of its words with no morphology at all
// and raises nothing. This is the check that notices.
func TestAnAyaIsMissingFromTheMorphologyFileAndEveryWordOfItIsUnparsed(t *testing.T) {
	c := load(t, fixtureDir)
	for i := range c.Words {
		if c.Words[i].AyahID == 103003 {
			c.Words[i].Morphology = ""
		}
	}
	if err := c.Check(false); err == nil {
		t.Fatal("an aya with no morphology at all passed the build")
	}
}

// A role ships in both languages or neither: half a vocabulary is a French
// reader shown English where a word's role should be.
func TestARoleShipsInOneLanguageOnly(t *testing.T) {
	saved := irabRoles["POS:V"]
	irabRoles["POS:V"] = [2]string{saved[0], "  "}
	t.Cleanup(func() { irabRoles["POS:V"] = saved })
	if err := load(t, fixtureDir).Check(false); err == nil {
		t.Fatal("a role with no French passed the build")
	}
}
