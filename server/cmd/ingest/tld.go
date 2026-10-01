package main

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"
)

// The French under each word, from The Last Dialogue's "Coran Mot à Mot", used
// by permission (data/SOURCES.md). quran.com has no French word-by-word, see
// versesURL. The source is web pages: an index linking one page per sura, and
// for the seven long suras that page links one page per fifty ayas. They are
// saved as served; server/cmd/etl reads the word cards out of them.
const tldIndexURL = "https://www.thelastdialogue.org/coran-mot-a-mot-francais/"

var (
	tldSuraPage    = regexp.MustCompile(`href="(https://www\.thelastdialogue\.org/sourate-[a-z0-9-]+-mot-a-mot-francais/)"`)
	tldSectionPage = regexp.MustCompile(`href="(https://www\.thelastdialogue\.org/sourate-[a-z0-9-]+-verse-\d+-\d+/)"`)
)

// downloadFrenchGlosses saves every page into dir/tld/, named by its slug. The
// sura a page covers is read from the aya numbers inside it, not from the slug:
// Al-Baqara's section pages are published under "sourate-fatiha-…-verse-…".
func downloadFrenchGlosses(ctx context.Context, f *fetcher, dir string, force bool) error {
	out := filepath.Join(dir, "tld")
	index := filepath.Join(out, "index.html")
	if err := f.download(ctx, tldIndexURL, index, force); err != nil {
		return err
	}
	suras, err := linksIn(index, tldSuraPage)
	if err != nil {
		return err
	}
	if len(suras) != 114 {
		return fmt.Errorf("%s links %d sura pages, want 114; the index has changed shape", tldIndexURL, len(suras))
	}
	for _, u := range suras {
		page := filepath.Join(out, slug(u)+".html")
		if err := f.download(ctx, u, page, force); err != nil {
			return err
		}
		sections, err := linksIn(page, tldSectionPage)
		if err != nil {
			return err
		}
		for _, s := range sections {
			if err := f.download(ctx, s, filepath.Join(out, slug(s)+".html"), force); err != nil {
				return err
			}
		}
	}
	return nil
}

func linksIn(path string, re *regexp.Regexp) ([]string, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	seen := map[string]bool{}
	var out []string
	for _, m := range re.FindAllStringSubmatch(string(b), -1) {
		if !seen[m[1]] {
			seen[m[1]] = true
			out = append(out, m[1])
		}
	}
	return out, nil
}

func slug(url string) string {
	parts := strings.Split(strings.TrimSuffix(url, "/"), "/")
	return parts[len(parts)-1]
}
