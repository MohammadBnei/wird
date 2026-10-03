package main

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/MohammadBnei/wird/server/internal/timings"
)

const fixtureDir = "testdata/corpus"

// The fixture carries one recitation's timings, the default reciter's.
var testRecitation = Recitations[0]

func load(t *testing.T, dir string) *Corpus {
	t.Helper()
	c, err := Load(dir, []Recitation{testRecitation})
	if err != nil {
		t.Fatalf("load %s: %v", dir, err)
	}
	if len(c.Refused) > 0 {
		t.Fatalf("fixture recitation refused: %v", c.Refused)
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
	if err := Write(out, c, 1, time.Now()); err != nil {
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
		"SELECT group_concat(recitation_id || ':' || word_id || ':' || start_ms) FROM (SELECT recitation_id, word_id, start_ms FROM word_segments ORDER BY recitation_id, word_id, seq)",
	} {
		if a, b := scalar(t, first, q), scalar(t, second, q); a != b {
			t.Errorf("two builds of the same input disagree on %s", q)
		}
	}
}

func TestAWordsTimingPointsAtAWordThatIsNotInTheCorpus(t *testing.T) {
	c := load(t, fixtureDir)
	c.Recited[0].Segments = append(c.Recited[0].Segments, Segment{WordID: wordID(1001, 99), StartMS: 0, EndMS: 10})
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
	c = load(t, fixtureDir)
	c.Words[0].WbwPath = "https://audio.qurancdn.com/wbw/001_001_001.mp3"
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
	if _, err := Load(dir, []Recitation{testRecitation}); err == nil {
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

// withSecondRecitation copies the fixture and gives it a second reciter whose
// timings are the first's, rewritten by edit.
func withSecondRecitation(t *testing.T, edit func(ayahs []timings.File)) (string, Recitation) {
	t.Helper()
	dir := copyFixture(t)
	var ayahs []timings.File
	src := filepath.Join(dir, "timings", testRecitation.Timings+".json")
	b, err := os.ReadFile(src)
	if err != nil {
		t.Fatal(err)
	}
	if err := json.Unmarshal(b, &ayahs); err != nil {
		t.Fatal(err)
	}
	edit(ayahs)
	out, err := json.Marshal(ayahs)
	if err != nil {
		t.Fatal(err)
	}
	second := Recitation{"second", "Second_Reciter", "A Reciter", "Murattal"}
	if err := os.WriteFile(filepath.Join(dir, "timings", second.Timings+".json"), out, 0o644); err != nil {
		t.Fatal(err)
	}
	return dir, second
}

func TestOneReciterWhoseAlignmentSplitsAWordIntoThreeShipsNoReciterAtAll(t *testing.T) {
	dir, second := withSecondRecitation(t, func(ayahs []timings.File) {
		last := ayahs[0].Segments[len(ayahs[0].Segments)-1]
		ayahs[0].Segments[len(ayahs[0].Segments)-1] = []int{last[0], last[1] + 2, last[2], last[3]}
	})
	c, err := Load(dir, []Recitation{testRecitation, second})
	if err != nil {
		t.Fatalf("one reciter's bad alignment stopped the build: %v", err)
	}
	if len(c.Recited) != 1 || c.Recited[0].Slug != testRecitation.Slug {
		t.Fatalf("recited %d recitations, want only %s", len(c.Recited), testRecitation.Slug)
	}
	if len(c.Refused) != 1 || !strings.Contains(c.Refused[0], second.Slug) {
		t.Fatalf("the refusal does not name the reciter: %v", c.Refused)
	}
	if err := c.Check(false); err != nil {
		t.Fatalf("the reciter that passed did not build: %v", err)
	}
	if strings.Contains(c.Notice, second.Timings) {
		t.Fatal("the notice credits timings that do not ship")
	}
}

func TestAnAyaWithNoTimingPlaysWithNoHighlightAtAll(t *testing.T) {
	dir, second := withSecondRecitation(t, func(ayahs []timings.File) {
		ayahs[1].Segments = nil // Shuraym's 12:76 in the 2016 release
	})
	c, err := Load(dir, []Recitation{testRecitation, second})
	if err != nil {
		t.Fatal(err)
	}
	if len(c.Refused) != 1 || !strings.Contains(c.Refused[0], "no timing") {
		t.Fatalf("a recitation with an untimed aya was not refused: %v", c.Refused)
	}
}

func TestTheReciterAFreshInstallFallsBackToIsMissingFromTheCorpus(t *testing.T) {
	dir, second := withSecondRecitation(t, func([]timings.File) {})
	c, err := Load(dir, []Recitation{second})
	if err != nil {
		t.Fatal(err)
	}
	if err := c.Check(false); err == nil {
		t.Fatal("a corpus without the default reciter passed the build")
	}
}

func TestTwoRecitersTimingsMixIntoOneHighlight(t *testing.T) {
	dir, second := withSecondRecitation(t, func(ayahs []timings.File) {
		for _, a := range ayahs {
			for _, seg := range a.Segments {
				seg[2] += 50000
				seg[3] += 50000
			}
		}
	})
	c, err := Load(dir, []Recitation{testRecitation, second})
	if err != nil {
		t.Fatal(err)
	}
	out := filepath.Join(t.TempDir(), "corpus.db")
	if err := Write(out, c, 1, time.Now()); err != nil {
		t.Fatal(err)
	}
	q := `SELECT count(*) FROM word_segments s JOIN recitations r ON r.id = s.recitation_id
	       WHERE r.slug = '%s' AND s.start_ms %s 50000`
	if n := scalar(t, out, fmt.Sprintf(q, testRecitation.Slug, ">=")); n != "0" {
		t.Errorf("%s carries %s of the second reciter's rows", testRecitation.Slug, n)
	}
	if n := scalar(t, out, fmt.Sprintf(q, second.Slug, "<")); n != "0" {
		t.Errorf("%s carries %s of the first reciter's rows", second.Slug, n)
	}
}

func TestAWordAfterAPauseMarkPlaysItsOwnFileNotTheNext(t *testing.T) {
	// The API's audio_url counts a pause mark as a word, so after one it names
	// the next word's file. The host numbers files by word: the path comes
	// from the position, whatever the API says. The fixture has no pause mark,
	// so this one is drifted by hand the way the API drifts it after 2:2's ۛ.
	dir := copyFixture(t)
	verses := filepath.Join(dir, "verses", "001.json")
	b, err := os.ReadFile(verses)
	if err != nil {
		t.Fatal(err)
	}
	drifted := strings.Replace(string(b), "wbw/001_001_004.mp3", "wbw/001_001_005.mp3", 1)
	if drifted == string(b) {
		t.Fatal("fixture no longer carries 1:1 word 4's audio_url")
	}
	if err := os.WriteFile(verses, []byte(drifted), 0o644); err != nil {
		t.Fatal(err)
	}
	c := load(t, dir)
	for _, w := range c.Words {
		if w.ID == wordID(1001, 4) && w.WbwPath != "wbw/001_001_004.mp3" {
			t.Fatalf("1:1 word 4 plays %q", w.WbwPath)
		}
	}
	db := build(t, fixtureDir)
	if n := scalar(t, db, "SELECT count(*) FROM words WHERE wbw_path IS NULL"); n != "0" {
		t.Errorf("%s fixture words have no word audio", n)
	}
}
