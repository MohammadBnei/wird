package main

import (
	"database/sql"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/MohammadBnei/wird/server/internal/timings"
)

const (
	fixtureDir     = "testdata/corpus"
	fixtureTimings = "Husary_Muallim_128kbps"
)

var testRecitation = Recitation{Slug: "husary-muallim", ReciterName: "Mahmoud Khalil Al-Husary", Style: "Muallim"}

func load(t *testing.T, dir string) *Corpus {
	t.Helper()
	c, err := Load(dir, testRecitation.Slug, fixtureTimings)
	if err != nil {
		t.Fatalf("load %s: %v", dir, err)
	}
	return c
}

func build(t *testing.T, dir string) string {
	t.Helper()
	out := filepath.Join(t.TempDir(), "corpus.db")
	c := load(t, dir)
	if err := c.Check(false); err != nil {
		t.Fatalf("fixture rejected: %v", err)
	}
	if err := Write(out, c, testRecitation, 1, time.Now()); err != nil {
		t.Fatalf("write: %v", err)
	}
	return out
}

func TestTheAyahNumberGlyphIsCountedAsAWordAndShiftsEveryLaterId(t *testing.T) {
	c := load(t, fixtureDir)
	var first []Word
	for _, w := range c.Words {
		if w.AyahID == 1001 {
			first = append(first, w)
		}
	}
	if len(first) != 4 {
		t.Fatalf("1:1 has %d words, want 4 — the ayah-number glyph is not a word", len(first))
	}
	if first[3].ID != 1001004 || first[3].TextAr == "١" {
		t.Errorf("last word of 1:1 is id %d %q, want the fourth word at 1001004",
			first[3].ID, first[3].TextAr)
	}
}

func TestTheHighlightJumpsBackwardsWhenATimingArrivesEarly(t *testing.T) {
	n := normalizeSegments([]timings.Span{
		{FirstWord: 1, LastWord: 1, StartMS: 2000, EndMS: 3000},
		{FirstWord: 2, LastWord: 2, StartMS: 500, EndMS: 3500},
	}, 1001)
	prev := -1
	for _, s := range n.segments {
		if s.StartMS < prev {
			t.Fatalf("start %d follows %d: the highlight rewinds mid-aya", s.StartMS, prev)
		}
		prev = s.StartMS
	}
}

func TestWordsTheReciterRunsTogetherLoseTheirOverlap(t *testing.T) {
	// 141 ayas legitimately overlap. Clamping them apart would shorten a real word.
	n := normalizeSegments([]timings.Span{
		{FirstWord: 1, LastWord: 1, StartMS: 0, EndMS: 1200},
		{FirstWord: 2, LastWord: 2, StartMS: 1000, EndMS: 2000},
	}, 1001)
	if n.segments[1].StartMS != 1000 || n.segments[0].EndMS != 1200 {
		t.Errorf("overlap rewritten to %d-%d / %d-%d", n.segments[0].StartMS, n.segments[0].EndMS,
			n.segments[1].StartMS, n.segments[1].EndMS)
	}
	if n.clamped != 0 {
		t.Errorf("clamped %d segments, want 0: an overlap is not a defect", n.clamped)
	}
}

func TestASecondBuildRenumbersWhatAShippedAppAlreadyJoinsAgainst(t *testing.T) {
	first, second := build(t, fixtureDir), build(t, fixtureDir)
	for _, q := range []string{
		"SELECT group_concat(id) FROM (SELECT id FROM ayahs ORDER BY id)",
		"SELECT group_concat(id) FROM (SELECT id FROM words ORDER BY id)",
		"SELECT group_concat(letters) FROM (SELECT letters FROM roots ORDER BY letters)",
		"SELECT count(*) FROM words",
		"SELECT count(*) FROM word_segments",
		"SELECT count(*) FROM ayah_audio",
		"SELECT group_concat(word_id || ':' || start_ms) FROM (SELECT word_id, start_ms FROM word_segments ORDER BY word_id, start_ms)",
	} {
		if a, b := scalar(t, first, q), scalar(t, second, q); a != b {
			t.Errorf("two builds of the same input disagree on %s", q)
		}
	}
}

func TestAWordsTimingPointsAtAWordThatIsNotInTheCorpus(t *testing.T) {
	c := load(t, fixtureDir)
	c.Segments = append(c.Segments, Segment{WordID: wordID(1001, 99), StartMS: 0, EndMS: 10})
	if err := c.Check(false); err == nil {
		t.Fatal("a segment for a word that does not exist passed the build")
	}
}

func TestEveryAyahCanStillFindItsAudioWhenTheHostMoves(t *testing.T) {
	c := load(t, fixtureDir)
	for _, a := range c.Audio {
		if strings.Contains(a.RelPath, "://") || strings.HasPrefix(a.RelPath, "/") {
			t.Fatalf("aya %d stores %q, an origin frozen into an immutable asset", a.AyahID, a.RelPath)
		}
	}
	c.Audio[0].RelPath = "https://audio-cdn.example.com/husary/001001.mp3"
	if err := c.Check(false); err == nil {
		t.Fatal("an absolute audio URL passed the build")
	}
}

func TestTheAppShipsWithSurasMissingFromTheCorpus(t *testing.T) {
	c := load(t, fixtureDir)
	if err := c.Check(true); err == nil {
		t.Fatal("a corpus of two suras passed the whole-Qur'an check")
	}
}

func TestWordTextAndTimingsComeFromTwoDifferentSegmentations(t *testing.T) {
	dir := copyFixture(t)
	// One word short in the morphology is how a second segmentation announces itself.
	morph := filepath.Join(dir, corpusFile)
	b, err := os.ReadFile(morph)
	if err != nil {
		t.Fatal(err)
	}
	lines := strings.Split(strings.TrimRight(string(b), "\n"), "\n")
	var kept []string
	for _, l := range lines {
		if !strings.HasPrefix(l, "(1:1:4:") {
			kept = append(kept, l)
		}
	}
	if err := os.WriteFile(morph, []byte(strings.Join(kept, "\n")+"\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if _, err := Load(dir, testRecitation.Slug, fixtureTimings); err == nil {
		t.Fatal("a corpus whose words and morphology disagree on the word count was accepted")
	}
}

func TestARootAWordNamesIsMissingFromTheRootsTable(t *testing.T) {
	c := load(t, fixtureDir)
	c.Roots = nil
	if err := c.Check(false); err == nil {
		t.Fatal("words naming roots the table does not hold passed the build")
	}
}

func copyFixture(t *testing.T) string {
	t.Helper()
	dst := t.TempDir()
	err := filepath.Walk(fixtureDir, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		rel, err := filepath.Rel(fixtureDir, path)
		if err != nil {
			return err
		}
		target := filepath.Join(dst, rel)
		if info.IsDir() {
			return os.MkdirAll(target, 0o755)
		}
		b, err := os.ReadFile(path)
		if err != nil {
			return err
		}
		return os.WriteFile(target, b, 0o644)
	})
	if err != nil {
		t.Fatal(err)
	}
	return dst
}

func scalar(t *testing.T, dbPath, query string) string {
	t.Helper()
	db, err := sql.Open("sqlite", dbPath)
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	var v sql.NullString
	if err := db.QueryRow(query).Scan(&v); err != nil {
		t.Fatalf("%s: %v", query, err)
	}
	return v.String
}

func TestAWordIdStopsNamingTheAyaAndPositionItCameFrom(t *testing.T) {
	// The ids are the join between a shipped asset and a later server. Derived from
	// the text rather than counted out, they survive a re-run of this ETL.
	c := load(t, fixtureDir)
	for _, a := range c.Ayahs {
		if a.ID != a.SurahID*1000+a.Number {
			t.Fatalf("aya %d:%d has id %d", a.SurahID, a.Number, a.ID)
		}
	}
	for _, w := range c.Words {
		if w.ID != int64(w.AyahID)*1000+int64(w.Position) {
			t.Fatalf("word %d of aya %d has id %d", w.Position, w.AyahID, w.ID)
		}
	}
}

func TestTheShippedCorpusCarriesNoAttributionForTheMorphologyItIsBuiltFrom(t *testing.T) {
	notice := scalar(t, build(t, fixtureDir), "SELECT notice FROM corpus_meta")
	for _, want := range []string{"Quranic Arabic Corpus", "Kais Dukes", "corpus.quran.com"} {
		if !strings.Contains(notice, want) {
			t.Errorf("corpus.db does not mention %q, so the app ships the morphology with no notice "+
				"attached to it", want)
		}
	}
	c := load(t, fixtureDir)
	c.Notice = ""
	if err := c.Check(false); err == nil {
		t.Fatal("a database with no copyright notice passed the build")
	}
}

func TestARootArrivesAsTransliterationAndTheRootPanelOpensOnLatinLetters(t *testing.T) {
	c := load(t, fixtureDir)
	for _, r := range c.Roots {
		for _, ch := range r.Letters {
			if ch < 0x0600 || ch > 0x06FF {
				t.Fatalf("root %q is not Arabic: the file publishes Buckwalter and the root panel "+
					"would render it", r.Letters)
			}
		}
	}
}

func TestTheShippedCorpusCarriesNoAttributionForTheTimingsItHighlightsWith(t *testing.T) {
	// CC BY 4.0 Section 3(a)(1) is what lets these timings be bundled at all, and
	// it asks for the attribution to travel with the material. The database is what
	// reaches a reader; a line in a repo file does not.
	notice := scalar(t, build(t, fixtureDir), "SELECT notice FROM corpus_meta")
	for _, want := range []string{"quran-align", "Collin Fair", "creativecommons.org/licenses/by/4.0/"} {
		if !strings.Contains(notice, want) {
			t.Errorf("corpus.db does not mention %q, so the app ships word timings under a licence "+
				"whose one condition it does not meet", want)
		}
	}
	c := load(t, fixtureDir)
	c.Notice = strings.ReplaceAll(c.Notice, "Collin Fair", "")
	if err := c.Check(false); err == nil {
		t.Fatal("a database that credits nobody for its word timings passed the build")
	}
}

func TestAMultiWordSpanLeavesTheWordsInsideItUntimed(t *testing.T) {
	// The aligner could not split 27 spans. One row per span, and the 61 words
	// inside them never light up — the failure a one-word-per-segment parser makes
	// and reports as success.
	n := normalizeSegments([]timings.Span{{FirstWord: 2, LastWord: 4, StartMS: 110, EndMS: 900}}, 1001)
	if len(n.segments) != 3 {
		t.Fatalf("a span over three words wrote %d rows", len(n.segments))
	}
	for i, w := range []int{2, 3, 4} {
		if n.segments[i].WordID != wordID(1001, w) {
			t.Errorf("row %d joins to word %d, want %d", i, n.segments[i].WordID, wordID(1001, w))
		}
	}
}
