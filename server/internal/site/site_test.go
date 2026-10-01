package site

import (
	"bytes"
	"encoding/json"
	"os"
	"regexp"
	"strings"
	"testing"
)

const stylesheet = "static/_ds/nocturne-f1420674-3c74-41e9-8af5-2fa684fcd021/styles.css"

// The page carries its own copy of Nocturne because embed cannot reach docs/.
// Two copies drift apart without anyone noticing, and the site stops looking
// like the app it advertises.
func TestThePageStylesheetDriftsFromNocturne(t *testing.T) {
	ours, err := static.ReadFile(stylesheet)
	if err != nil {
		t.Fatal(err)
	}
	design, err := os.ReadFile("../../../docs/design/nocturne-styles.css")
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(bytes.TrimSpace(ours), bytes.TrimSpace(design)) {
		t.Error("the site's stylesheet differs from docs/design/nocturne-styles.css: re-fetch one of them")
	}
}

// The design mockups wrote their own Qur'an text, senses, form notes and
// commentary. A fresh copy of a demo from the design project brings them back
// and the public page then teaches something nobody wrote.
func TestADemoShipsTheMockupsInventedScholarship(t *testing.T) {
	for file, invented := range map[string]string{
		"static/Wird Reader.dc.html": "W('بِسْمِ'",
		"static/Wird Prayer.dc.html": "const FATIHA = mk(1, [",
	} {
		b, err := static.ReadFile(file)
		if err != nil {
			t.Fatal(err)
		}
		if strings.Contains(string(b), invented) || !strings.Contains(string(b), "window.WIRD_SITE") {
			t.Errorf("%s carries the mockup's own tables, not the corpus", file)
		}
	}
}

// The demos read everything from site-data.js. A root a word points at with no
// entry, or no senses, renders as a blank sheet the moment a visitor swipes to it.
func TestTheReaderDemoSwipesOntoAWordWithNothingBehindIt(t *testing.T) {
	b, err := static.ReadFile("static/site-data.js")
	if err != nil {
		t.Fatal(err)
	}
	s := string(b)
	s = strings.TrimSuffix(strings.TrimSpace(s[strings.Index(s, "=")+1:]), ";")
	var data struct {
		Reader struct {
			Words []struct {
				Ar string  `json:"ar"`
				R  *string `json:"r"`
				A  int     `json:"a"`
			} `json:"words"`
			Roots map[string]struct {
				Senses []string `json:"senses"`
				Forms  []any    `json:"forms"`
			} `json:"roots"`
		} `json:"reader"`
	}
	if err := json.Unmarshal([]byte(s), &data); err != nil {
		t.Fatalf("site-data.js is not the generator's output: %v", err)
	}
	if n := len(data.Reader.Words); n != 29 {
		t.Errorf("Al-Fātiḥa has 29 words in the corpus, the demo has %d", n)
	}
	rootless := 0
	for _, w := range data.Reader.Words {
		if w.R == nil {
			rootless++
			continue
		}
		root, ok := data.Reader.Roots[*w.R]
		if !ok || len(root.Senses) == 0 || len(root.Forms) == 0 {
			t.Errorf("%s (1:%d) points at root %s with nothing behind it", w.Ar, w.A, *w.R)
		}
	}
	if rootless == 0 {
		t.Error("no rootless word to swipe onto, so the fallback below is untested by the data")
	}
}

// The mockup fell back to ROOTS.rhm for a word with no root. The corpus keys
// roots by their Arabic letters, so that key no longer exists, and swiping
// onto إِيَّاكَ threw before anything rendered.
func TestTheReaderDemoCrashesOnAParticle(t *testing.T) {
	b, err := static.ReadFile("static/Wird Reader.dc.html")
	if err != nil {
		t.Fatal(err)
	}
	if regexp.MustCompile(`ROOTS\.[A-Za-z]`).Match(b) {
		t.Error("the Reader reaches a root by a Latin key, which site-data.js never has")
	}
}
