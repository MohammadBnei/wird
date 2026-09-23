package main

import (
	"bytes"
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

const (
	chaptersURL   = "https://api.quran.com/api/v4/chapters?language=en"
	versesURL     = "https://api.quran.com/api/v4/verses/by_chapter/%d?words=true&word_fields=text_uthmani,transliteration&language=en&fields=text_uthmani&per_page=300"
	segmentsURL   = "https://api.quran.com/api/v4/recitations/%d/by_chapter/%d?fields=segments,duration,url&per_page=300"

	// The morphology is not fetched. corpus.quran.com/download serves a form that
	// asks for an email address and for the terms to be accepted before it hands
	// over the file, and that acceptance is a person taking the licence, not a
	// request this program is entitled to make on their behalf.
	corpusPage = "https://corpus.quran.com/download/"
	corpusFile = "quranic-corpus-morphology-0.4.txt"
)

var sourceURLs = []string{chaptersURL, versesURL, segmentsURL, corpusPage}

func main() {
	out := flag.String("out", "./data/raw/", "directory the downloads land in; gitignored")
	manifestPath := flag.String("manifest", "./data/manifest.json", "manifest to write; this is what git holds")
	only := flag.String("suras", "", "suras to fetch, e.g. 1,2,103,112 or 1-5 (default: all 114)")
	recitation := flag.Int("recitation", 12, "quran.com recitation id; 12 is al-Husari, Muallim")
	delay := flag.Duration("delay", 200*time.Millisecond, "pause between requests")
	retries := flag.Int("retries", 5, "retries per request before giving up")
	force := flag.Bool("force", false, "re-download files that are already on disk")
	flag.Parse()

	if err := run(*out, *manifestPath, *only, *recitation, *delay, *retries, *force); err != nil {
		log.Fatal(err)
	}
}

func run(dir, manifestPath, only string, recitation int, delay time.Duration, retries int, force bool) error {
	ctx := context.Background()
	// Before 38 MB of downloads: the one file a person has to put there by hand.
	if err := requireCorpusMorphology(filepath.Join(dir, corpusFile)); err != nil {
		return err
	}
	f := &fetcher{hc: &http.Client{Timeout: 2 * time.Minute}, delay: delay, retries: retries}

	if err := f.download(ctx, chaptersURL, filepath.Join(dir, "chapters.json"), force); err != nil {
		return err
	}
	chapters, err := readChapters(dir)
	if err != nil {
		return err
	}

	suras, err := selectSuras(only, chapters)
	if err != nil {
		return err
	}
	if len(suras) != 114 {
		if err := refusePartialOverwrite(manifestPath); err != nil {
			return err
		}
	}

	for _, n := range suras {
		v := filepath.Join(dir, "verses", fmt.Sprintf("%03d.json", n))
		if err := f.download(ctx, fmt.Sprintf(versesURL, n), v, force); err != nil {
			return err
		}
		s := filepath.Join(dir, "segments", fmt.Sprintf("%03d.json", n))
		if err := f.download(ctx, fmt.Sprintf(segmentsURL, recitation, n), s, force); err != nil {
			return err
		}
	}

	m, err := verify(dir, suras, chapters, time.Now())
	if err != nil {
		return err
	}
	var buf bytes.Buffer
	enc := json.NewEncoder(&buf)
	enc.SetEscapeHTML(false) // the manifest is read by people; \u0026 is not an ampersand to them
	enc.SetIndent("", "  ")
	if err := enc.Encode(m); err != nil {
		return err
	}
	if err := save(manifestPath, buf.Bytes()); err != nil {
		return err
	}

	r := m.Reconciliation
	fmt.Printf("%s\n  requests %d  suras %d  ayas %d  words %d\n"+
		"  audio %d  segment tuples %d  words timed %d  morphology segments %d  roots %d\n"+
		"  ayas where word numbering disagrees %d\n"+
		"  ayas with a segment past the last word %d\n"+
		"  multi-word spans %d, timing %d words a one-word-per-segment parser drops\n"+
		"  words with no timing %d across %d ayas\n"+
		"  overlapping segment pairs %d  segments ending before they start %d\n",
		manifestPath, f.requests, m.Counts.Surahs, m.Counts.Ayahs, m.Counts.Words,
		m.Counts.AudioFiles, m.Counts.SegmentTuples, m.Counts.WordsTimed,
		m.Counts.MorphologySegments, m.Counts.Roots,
		r.AyahsWhereWordNumberingDisagrees, r.AyahsWithASegmentPastTheLastWord,
		r.MultiWordSegmentSpans, r.WordsTimedOnlyByAMultiWordSpan,
		r.WordsWithNoTiming, r.AyahsWithAnUntimedWord,
		r.OverlappingSegmentPairs, r.SegmentsEndingBeforeTheyStart)
	return nil
}

// refusePartialOverwrite keeps a four-sura run from replacing the manifest that
// stands for the whole corpus.
func refusePartialOverwrite(path string) error {
	b, err := os.ReadFile(path)
	if err != nil {
		return nil
	}
	var m manifest
	if json.Unmarshal(b, &m) == nil && m.Complete {
		return fmt.Errorf("%s covers all 114 suras; a partial run would replace it. "+
			"Pass -manifest elsewhere, or drop -suras", path)
	}
	return nil
}

func selectSuras(spec string, chapters []chapter) ([]int, error) {
	if strings.TrimSpace(spec) == "" {
		out := make([]int, 0, len(chapters))
		for _, ch := range chapters {
			out = append(out, ch.ID)
		}
		return out, nil
	}
	var out []int
	for _, part := range strings.Split(spec, ",") {
		part = strings.TrimSpace(part)
		lo, hi, isRange := strings.Cut(part, "-")
		if !isRange {
			hi = lo
		}
		a, err1 := strconv.Atoi(strings.TrimSpace(lo))
		b, err2 := strconv.Atoi(strings.TrimSpace(hi))
		if err1 != nil || err2 != nil || a < 1 || b > 114 || a > b {
			return nil, fmt.Errorf("-suras %q: %q is not a sura or a range within 1-114", spec, part)
		}
		for n := a; n <= b; n++ {
			out = append(out, n)
		}
	}
	return out, nil
}
