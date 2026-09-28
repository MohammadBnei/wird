package main

import (
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"fmt"
	"os"
	"regexp"
	"strings"

	"github.com/MohammadBnei/wird/server/internal/lane"
)

// A root, with everything a sense has to be written from.
type subject struct {
	Root        string
	Occurrences int
	Glosses     []string
	Lane        string // Lane's article, or noLane
	LaneChars   int
	LaneHow     string // exact, geminate, filed under X, or none
}

// HTML comments in the prompt file are notes to its editor, not prompt text.
var comments = regexp.MustCompile(`(?s)<!--.*?-->`)

const noLane = "NO LANE ARTICLE. Lane's Lexicon has no division for this root; " +
	"45 of the 1,642 do not."

// promptFile is the knob. It is read once per run, never compiled in, and its
// digest travels into every row it produced — so a draft can always be traced to
// the prompt that wrote it, and a re-run with an edited prompt is visibly a
// different generation rather than a silent one.
type promptFile struct {
	text string
	sha  string
}

func readPrompt(path string) (promptFile, error) {
	raw, err := os.ReadFile(path)
	if err != nil {
		return promptFile{}, err
	}
	// The digest covers the whole file, comments included: any edit is a new
	// generation. What is SENT has the comments stripped — they document the
	// placeholders for whoever is editing, so leaving them in would substitute
	// the root into its own documentation and send that to the model.
	sum := sha256.Sum256(raw)
	return promptFile{
		text: strings.TrimSpace(comments.ReplaceAllString(string(raw), "")),
		sha:  hex.EncodeToString(sum[:])[:12],
	}, nil
}

func (p promptFile) for_(s subject) string {
	glosses := "(none — this root's words carry no English gloss)"
	if len(s.Glosses) > 0 {
		glosses = "  " + strings.Join(s.Glosses, "\n  ")
	}
	r := strings.NewReplacer(
		"{{ROOT}}", s.Root,
		"{{OCCURRENCES}}", fmt.Sprint(s.Occurrences),
		"{{GLOSSES}}", glosses,
		"{{LANE}}", s.Lane,
	)
	return r.Replace(p.text)
}

// subjectFor gathers one root's inputs. Lane is read from the clone; the glosses
// and the count from the shipped corpus, which is what the sense is checked
// against rather than derived from.
func subjectFor(db *sql.DB, articles map[string]string, root string) (subject, error) {
	s := subject{Root: root, Lane: noLane, LaneHow: "none"}
	if err := db.QueryRow(
		`SELECT quran_occurrences FROM roots WHERE letters = ?`, root,
	).Scan(&s.Occurrences); err != nil {
		return s, fmt.Errorf("%s is not a root in this corpus: %w", root, err)
	}
	// With counts, heaviest first. The count is the whole point: it separates what
	// the corpus contains from what a reader meets, so a branch carrying a hundred
	// occurrences is visible as such while the sense is being written. An earlier
	// version sent an alphabetical list with no counts and then had a second pass
	// complain about "missed" glosses, which taught the model to paste corpus
	// glosses in as clauses.
	rows, err := db.Query(
		`SELECT gloss_en, COUNT(*) n FROM words
		  WHERE root_letters = ? AND gloss_en IS NOT NULL AND gloss_en <> ''
		  GROUP BY LOWER(gloss_en) ORDER BY n DESC, gloss_en
		  LIMIT 40`, root)
	if err != nil {
		return s, err
	}
	defer rows.Close()
	for rows.Next() {
		var g string
		var n int
		if err := rows.Scan(&g, &n); err != nil {
			return s, err
		}
		s.Glosses = append(s.Glosses, fmt.Sprintf("%s  ×%d", g, n))
	}
	if err := rows.Err(); err != nil {
		return s, err
	}
	if key, how := lane.Look(articles, root); key != "" {
		s.Lane = strings.TrimSpace(articles[key])
		s.LaneChars = len(s.Lane)
		s.LaneHow = how
	}
	return s, nil
}
