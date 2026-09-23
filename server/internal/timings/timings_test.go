package timings

import (
	"strings"
	"testing"
)

func spans(t *testing.T, raw [][]int, words int) []Span {
	t.Helper()
	got, err := Spans(raw, words)
	if err != nil {
		t.Fatalf("Spans(%v, %d): %v", raw, words, err)
	}
	return got
}

func TestASegmentJoinsToTheWordAfterTheOneItTimesBecauseTwoSourcesNumberWordsDifferently(t *testing.T) {
	// 13:1 in miniature. The aligner's recogniser hears the opening letters as
	// several words and gives them two indices; the text has one word there, so
	// index 1 is aligned by nothing and every index after it names the word before
	// the one it looks like. Taken at face value, word 2 goes untimed and word 3
	// lights up while word 2 is being recited — and so on to the end of the aya.
	got := spans(t, [][]int{
		{0, 1, 300, 9050}, // the letter group, eight seconds of it
		{2, 3, 12600, 13210},
		{3, 4, 13220, 14750},
	}, 3)
	want := []Span{
		{FirstWord: 1, LastWord: 1, StartMS: 300, EndMS: 9050},
		{FirstWord: 2, LastWord: 2, StartMS: 12600, EndMS: 13210},
		{FirstWord: 3, LastWord: 3, StartMS: 13220, EndMS: 14750},
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("span %d is %+v, want %+v: the highlight sits one word ahead of the voice",
				i, got[i], want[i])
		}
	}
}

func TestTheHighlightGoesDarkWhileTheReciterIsStillOnTheLastWord(t *testing.T) {
	// 37:130, where the aligner splits إِلْ يَاسِينَ on the space the text writes
	// inside one word. The trailing index belongs to the last word; dropped, the
	// highlight goes out while the recitation is still going.
	got := spans(t, [][]int{
		{0, 1, 450, 1380}, {1, 2, 1390, 3130}, {2, 3, 3140, 3540}, {3, 4, 3550, 5170},
	}, 3)
	if len(got) != 4 {
		t.Fatalf("got %d spans, want 4", len(got))
	}
	if last := got[3]; last.FirstWord != 3 || last.LastWord != 3 || last.EndMS != 5170 {
		t.Fatalf("the trailing span is %+v, want the last word held until 5170", last)
	}
}

func TestAMultiWordSpanTimesEveryWordItCoversNotOnlyItsLast(t *testing.T) {
	// 27 spans cover more than one word: the aligner could not find the boundary.
	// One row per span leaves the other 61 words of the corpus with no timing.
	got := spans(t, [][]int{{0, 1, 0, 100}, {1, 4, 110, 900}}, 4)
	if got[1].FirstWord != 2 || got[1].LastWord != 4 {
		t.Fatalf("span covers words %d..%d, want 2..4", got[1].FirstWord, got[1].LastWord)
	}
}

func TestATimingTupleReadAsThreeElementsHighlightsTheWrongWord(t *testing.T) {
	// The shape quran.com documents is [segment_index, start_ms, end_ms]. A reader
	// that believes it puts a word index where a timestamp belongs, everywhere.
	_, err := Spans([][]int{{0, 150, 710}, {1, 720, 1170}}, 2)
	if err == nil || !strings.Contains(err.Error(), "shape has changed") {
		t.Fatalf("a 3-element tuple was accepted: %v", err)
	}
}

func TestAMillisecondWhereAWordIndexBelongsIsRejected(t *testing.T) {
	if _, err := Spans([][]int{{0, 710, 150, 710}}, 2); err == nil {
		t.Fatal("a timestamp passed as a word index; the corpus would look fine and mis-highlight everywhere")
	}
}

func TestTimingsNumberedOverAThirdSegmentationAreRejectedRatherThanReconciled(t *testing.T) {
	// One index too many is the muqaṭṭaʿāt and is reconciled above. Two is a
	// different tokenisation of the whole text, and guessing at it is how every
	// word after the divergence ends up on the wrong sound.
	_, err := Spans([][]int{{0, 1, 0, 100}, {1, 2, 110, 200}, {2, 3, 210, 300}, {3, 4, 310, 400}}, 2)
	if err == nil || !strings.Contains(err.Error(), "two") {
		t.Fatalf("a second segmentation was accepted: %v", err)
	}
}

func TestTheNoticeLeavesOutSomethingTheLicenceAsksFor(t *testing.T) {
	n := Notice("Husary_Muallim_128kbps.json")
	for _, want := range []string{
		"Collin Fair",                          // 3(a)(1)(A)(i), the creator
		"Copyright (c) 2016",                   // (ii), a copyright notice
		"creativecommons.org/licenses/by/4.0/", // (iii) and 3(a)(1)(C), the licence
		"disclaims all warranties",             // (iv), the disclaimer
		"github.com/cpfair/quran-align",        // (v), a link to the material
		"Modified",                             // 3(a)(1)(B)
		LicenceMarker,                          // the sentence the ingest re-reads
	} {
		if !strings.Contains(n, want) {
			t.Errorf("the notice does not carry %q, which CC BY 4.0 Section 3(a)(1) requires", want)
		}
	}
}
