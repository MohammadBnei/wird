package main

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

type fakeAyah struct {
	words     int
	segments  [][]int
	morphWord int // words in the morphology table; 0 means "the same as the text"
}

// writeFixture lays out one sura the way the ingest leaves it on disk.
func writeFixture(t *testing.T, ayahs []fakeAyah) (string, []chapter) {
	t.Helper()
	dir := t.TempDir()

	ch := chapter{ID: 1, NameArabic: "الفاتحة", NameSimple: "Al-Fatihah",
		VersesCount: len(ayahs), RevelationOrder: 5, RevelationPlace: "makkah"}
	writeJSON(t, filepath.Join(dir, "chapters.json"), map[string]any{"chapters": []chapter{ch}})

	var verses, audio []map[string]any
	var morph strings.Builder
	for i, a := range ayahs {
		key := fmt.Sprintf("1:%d", i+1)
		words := make([]map[string]any, 0, a.words+1)
		for w := 0; w < a.words; w++ {
			words = append(words, map[string]any{"char_type_name": "word"})
		}
		words = append(words, map[string]any{"char_type_name": "end"})
		verses = append(verses, map[string]any{"verse_key": key, "words": words})
		audio = append(audio, map[string]any{"verse_key": key, "duration": 10,
			"url": "//host/001" + fmt.Sprintf("%03d", i+1) + ".mp3", "segments": a.segments})

		n := a.morphWord
		if n == 0 {
			n = a.words
		}
		for w := 1; w <= n; w++ {
			fmt.Fprintf(&morph, "1:%d:%d:1\tform\tN\tROOT:وصي|LEM:x\n", i+1, w)
		}
	}
	writeJSON(t, filepath.Join(dir, "verses", "001.json"),
		map[string]any{"verses": verses, "pagination": map[string]any{"next_page": nil}})
	writeJSON(t, filepath.Join(dir, "segments", "001.json"), map[string]any{"audio_files": audio})
	if err := save(filepath.Join(dir, "morphology.txt"), []byte(morph.String())); err != nil {
		t.Fatal(err)
	}
	return dir, []chapter{ch}
}

func writeJSON(t *testing.T, path string, v any) {
	t.Helper()
	b, err := json.Marshal(v)
	if err != nil {
		t.Fatal(err)
	}
	if err := save(path, b); err != nil {
		t.Fatal(err)
	}
}

func verifyFixture(t *testing.T, ayahs []fakeAyah) (*manifest, error) {
	t.Helper()
	dir, chapters := writeFixture(t, ayahs)
	return verify(dir, []int{1}, chapters, time.Now())
}

// A four-word aya, one segment per word, is the shape everything else deviates
// from. Each tuple is [word_start_index, word_end_index, start_ms, end_ms].
func fourWords() []fakeAyah {
	return []fakeAyah{{words: 4, segments: [][]int{
		{0, 1, 150, 710}, {1, 2, 720, 1170}, {2, 3, 1180, 2450}, {3, 4, 2460, 3150},
	}}}
}

func TestASegmentTupleWithoutItsWordRangeIsRejectedRatherThanReadAsATimestamp(t *testing.T) {
	_, err := verifyFixture(t, []fakeAyah{{words: 2, segments: [][]int{{0, 150, 710}, {1, 720, 1170}}}})
	if err == nil {
		t.Fatal("a 3-element tuple was accepted; every word in the corpus would be highlighted at the wrong moment")
	}
	if !strings.Contains(err.Error(), "shape has changed") {
		t.Fatalf("the error does not say the tuple shape changed: %v", err)
	}
}

func TestAMillisecondWhereAWordIndexBelongsIsRejected(t *testing.T) {
	_, err := verifyFixture(t, []fakeAyah{{words: 2, segments: [][]int{{0, 710, 150, 710}}}})
	if err == nil {
		t.Fatal("a timestamp was accepted as a word index; the corpus would look fine and mis-highlight everywhere")
	}
}

func TestSegmentsNumberedPastTheLastWordAreRejectedSoTwoSegmentationsNeverMix(t *testing.T) {
	_, err := verifyFixture(t, []fakeAyah{{words: 2, segments: [][]int{
		{0, 1, 0, 100}, {1, 2, 110, 200}, {2, 3, 210, 300}, {3, 4, 310, 400},
	}}})
	if err == nil {
		t.Fatal("a segment source with more words than the text was accepted")
	}
	if !strings.Contains(err.Error(), "two different segmentations") {
		t.Fatalf("the error does not name the cause: %v", err)
	}
}

func TestTheRecitersExtraSegmentOnASingleWordIsCountedNotRejected(t *testing.T) {
	m, err := verifyFixture(t, []fakeAyah{{words: 2, segments: [][]int{
		{0, 1, 0, 100}, {1, 2, 110, 200}, {2, 3, 210, 300},
	}}})
	if err != nil {
		t.Fatalf("the muqatta'at, where the reciter splits one written word, were rejected: %v", err)
	}
	if got := m.Reconciliation.AyahsWithASegmentPastTheLastWord; got != 1 {
		t.Fatalf("trailing segment not reported: got %d, want 1", got)
	}
	if got := m.Counts.WordsTimed; got != 2 {
		t.Fatalf("the trailing segment timed a word that does not exist: got %d, want 2", got)
	}
}

func TestAMultiWordSegmentTimesEveryWordItCoversNotOnlyItsLast(t *testing.T) {
	m, err := verifyFixture(t, []fakeAyah{{words: 4, segments: [][]int{
		{0, 1, 0, 100}, {1, 4, 110, 900},
	}}})
	if err != nil {
		t.Fatal(err)
	}
	if m.Reconciliation.WordsWithNoTiming != 0 {
		t.Fatalf("words inside a span were read as untimed, which is what a one-word-per-segment parser does: %+v",
			m.Reconciliation)
	}
	if m.Reconciliation.WordsTimedOnlyByAMultiWordSpan != 2 || m.Reconciliation.MultiWordSegmentSpans != 1 {
		t.Fatalf("the span the ETL would drop is not reported: %+v", m.Reconciliation)
	}
}

func TestSegmentsOutOfWordOrderAreRejectedBecauseTheHighlightWouldJumpBackwards(t *testing.T) {
	_, err := verifyFixture(t, []fakeAyah{{words: 3, segments: [][]int{
		{0, 1, 0, 100}, {2, 3, 110, 200}, {1, 2, 210, 300},
	}}})
	if err == nil {
		t.Fatal("segments that walk the words out of order were accepted")
	}
}

func TestAWordWithNoTimingIsCountedSoTheFrozenHighlightIsNotSilent(t *testing.T) {
	m, err := verifyFixture(t, []fakeAyah{{words: 4, segments: [][]int{
		{0, 1, 0, 100}, {1, 2, 110, 200},
	}}})
	if err != nil {
		t.Fatalf("a short segment list is a gap to report, not a reason to fail: %v", err)
	}
	if m.Reconciliation.WordsWithNoTiming != 2 || m.Reconciliation.AyahsWithAnUntimedWord != 1 {
		t.Fatalf("untimed words not reported: %+v", m.Reconciliation)
	}
}

func TestOverlappingSegmentsAreCountedRatherThanRejected(t *testing.T) {
	m, err := verifyFixture(t, []fakeAyah{{words: 3, segments: [][]int{
		{0, 1, 0, 500}, {1, 2, 400, 900}, {2, 3, 800, 1200},
	}}})
	if err != nil {
		t.Fatalf("overlapping timings are real in this data and must not stop an ingest: %v", err)
	}
	if got := m.Reconciliation.OverlappingSegmentPairs; got != 2 {
		t.Fatalf("overlaps not reported: got %d, want 2", got)
	}
}

func TestASegmentEndingBeforeItStartsIsCountedRatherThanStoppingTheIngest(t *testing.T) {
	m, err := verifyFixture(t, []fakeAyah{{words: 2, segments: [][]int{
		{0, 1, 0, 100}, {1, 2, 13480, 13470},
	}}})
	if err != nil {
		t.Fatalf("inverted timings are real in this data and the ETL clamps them: %v", err)
	}
	if got := m.Reconciliation.SegmentsEndingBeforeTheyStart; got != 1 {
		t.Fatalf("inverted timing not reported: got %d, want 1", got)
	}
}

func TestAMorphologyTableWithMoreWordsThanTheTextIsRejected(t *testing.T) {
	ayahs := fourWords()
	ayahs[0].morphWord = 5 // the QPC script splits a vocative the text keeps whole
	_, err := verifyFixture(t, ayahs)
	if err == nil {
		t.Fatal("a morphology table on a different segmentation was accepted; every root after the split would be wrong")
	}
}

func TestASuraTruncatedByPaginationIsRejectedRatherThanIngestedShort(t *testing.T) {
	dir, chapters := writeFixture(t, fourWords())
	next := 2
	writeJSON(t, filepath.Join(dir, "verses", "001.json"), map[string]any{
		"verses":     []map[string]any{{"verse_key": "1:1", "words": []map[string]any{{"char_type_name": "word"}}}},
		"pagination": map[string]any{"next_page": &next},
	})
	if _, err := verify(dir, []int{1}, chapters, time.Now()); err == nil {
		t.Fatal("a sura that did not fit on one page was accepted, losing its tail silently")
	}
}

func TestADuplicateRevelationOrderIsRejectedSoTheChronologicalWalkCannotSkipASura(t *testing.T) {
	chapters := make([]chapter, 0, 114)
	for i := 1; i <= 114; i++ {
		order := i
		if i == 114 {
			order = 1 // two suras claiming to be the first revealed
		}
		chapters = append(chapters, chapter{ID: i, VersesCount: 1, RevelationOrder: order})
	}
	if err := checkRevelationOrder(chapters); err == nil {
		t.Fatal("a duplicated revelation order was accepted; the default reading order would skip a sura")
	}
}

func TestAFinishedDownloadIsNotFetchedAgainOnARerun(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprint(w, `{"ok":true}`)
	}))
	defer srv.Close()

	f := &fetcher{hc: srv.Client(), base: time.Millisecond}
	path := filepath.Join(t.TempDir(), "verses", "002.json")
	for i := 0; i < 3; i++ {
		if err := f.download(context.Background(), srv.URL, path, false); err != nil {
			t.Fatal(err)
		}
	}
	if f.requests != 1 {
		t.Fatalf("a re-run downloaded %d times; 38 MB is re-fetched on every retry", f.requests)
	}
}

func TestAFailedDownloadLeavesNoFileForTheNextRunToSkip(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		http.Error(w, "boom", http.StatusInternalServerError)
	}))
	defer srv.Close()

	f := &fetcher{hc: srv.Client(), base: time.Millisecond, retries: 1}
	path := filepath.Join(t.TempDir(), "verses", "002.json")
	if err := f.download(context.Background(), srv.URL, path, false); err == nil {
		t.Fatal("a failing download reported success")
	}
	if _, err := os.Stat(path); !os.IsNotExist(err) {
		t.Fatal("a half-written file was left behind, and the next run would accept it as complete")
	}
}

func TestARateLimitedRequestIsRetriedInsteadOfLosingTheSura(t *testing.T) {
	var hits int
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		hits++
		if hits == 1 {
			w.Header().Set("Retry-After", "0")
			w.WriteHeader(http.StatusTooManyRequests)
			return
		}
		fmt.Fprint(w, `{"ok":true}`)
	}))
	defer srv.Close()

	f := &fetcher{hc: srv.Client(), base: time.Millisecond, retries: 3}
	b, err := f.get(context.Background(), srv.URL)
	if err != nil {
		t.Fatalf("a 429 ended the ingest instead of pausing it: %v", err)
	}
	if string(b) != `{"ok":true}` {
		t.Fatalf("body after retry: %q", b)
	}
}

func TestAPartialRunRefusesToReplaceTheManifestForTheWholeCorpus(t *testing.T) {
	path := filepath.Join(t.TempDir(), "manifest.json")
	writeJSON(t, path, manifest{Complete: true})
	if err := refusePartialOverwrite(path); err == nil {
		t.Fatal("a four-sura run would have overwritten the record of all 114")
	}
}
