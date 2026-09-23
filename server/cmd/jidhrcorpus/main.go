// Command jidhrcorpus writes the corpus jidhr serves out of the corpus.db the app
// bundles. corpus.db is the checked artefact — the ETL refuses to write a sense the
// root's own words no longer bear out — so the root engine and the app answer from
// one body of data rather than from two that drift.
package main

import (
	"database/sql"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"slices"

	"github.com/MohammadBnei/wird/jidhr/pkg/root"
	_ "modernc.org/sqlite"
)

// note travels with the corpus because the prose in it is Wird's own reading of
// each root, not a lexicon it is quoting, and a caller outside Wird has no other
// place to learn that.
const note = "The corpus rootd serves, written by server/cmd/jidhrcorpus from app/assets/corpus.db. " +
	"The roots and the attested forms are the Quranic Arabic Corpus morphology; the meanings are Wird's own " +
	"reading of each root, written from that root's own words in the Qur'an and kept only where their glosses " +
	"bore it out. Roots with nothing written are the majority and ship with no meaning at all. Edit corpus.db " +
	"and rebuild; editing this file by hand puts the two out of step."

func main() {
	in := flag.String("db", "./app/assets/corpus.db", "the corpus.db the app bundles")
	out := flag.String("out", "./jidhr/testdata/quran.json", "the jidhr corpus to write")
	flag.Parse()

	db, err := sql.Open("sqlite", "file:"+filepath.Clean(*in)+"?mode=ro")
	if err != nil {
		log.Fatalf("open %s: %v", *in, err)
	}
	defer db.Close()

	c, err := build(db)
	if err != nil {
		log.Fatalf("read %s: %v", *in, err)
	}
	if err := write(*out, c); err != nil {
		log.Fatalf("write %s: %v", *out, err)
	}

	fi, err := os.Stat(*out)
	if err != nil {
		log.Fatal(err)
	}
	fmt.Printf("%s\n  roots %d  attested forms %d  roots with a meaning %d  languages %v\n  %.2f MB\n",
		*out, len(c.Roots), len(c.Attested), len(c.Meanings), languages(c), float64(fi.Size())/(1<<20))
}

// corpusFile is what jidhr reads, with the provenance note the reader of the file
// needs and the loader ignores.
type corpusFile struct {
	Note string `json:"note"`
	root.Corpus
}

func build(db *sql.DB) (root.Corpus, error) {
	c := root.Corpus{Attested: map[string][]string{}, Meanings: map[string]map[string]root.Meaning{}}

	known := map[string]bool{}
	rows, err := db.Query(`SELECT letters, display, translit, quran_occurrences FROM roots ORDER BY letters`)
	if err != nil {
		return c, err
	}
	defer rows.Close()
	for rows.Next() {
		var r root.RootRecord
		var occurrences int
		if err := rows.Scan(&r.Letters, &r.Display, &r.Translit, &occurrences); err != nil {
			return c, err
		}
		// Absent rather than zero: a root the Qur'an never uses has no Qur'anic
		// statistic, and zero is a measurement.
		if occurrences > 0 {
			r.Quran = &root.QuranStats{Occurrences: occurrences}
		}
		known[r.Letters] = true
		c.Roots = append(c.Roots, r)
	}
	if err := rows.Err(); err != nil {
		return c, err
	}

	// Attestation is the bare fact that the corpus wrote this spelling under this
	// root, and it is the only thing jidhr's last rung may assert from. Forms go in
	// spelled as the corpus spells them; jidhr normalises them as it indexes them.
	forms, err := db.Query(`SELECT DISTINCT text_ar, root_letters FROM words
		WHERE root_letters IS NOT NULL AND root_letters <> '' ORDER BY text_ar, root_letters`)
	if err != nil {
		return c, err
	}
	defer forms.Close()
	for forms.Next() {
		var form, letters string
		if err := forms.Scan(&form, &letters); err != nil {
			return c, err
		}
		if !known[letters] {
			return c, fmt.Errorf("the form %q is attested under %q, which the roots table does not record", form, letters)
		}
		c.Attested[form] = append(c.Attested[form], letters)
	}
	if err := forms.Err(); err != nil {
		return c, err
	}

	// word_id IS NULL is the root's own sense rather than a note about one word of
	// it. Nothing in corpus.db authors a poetic register, so none is written here:
	// an unwritten register is absent, never blank.
	senses, err := db.Query(`SELECT root_letters, note, COALESCE(note_fr, '') FROM root_notes
		WHERE word_id IS NULL ORDER BY root_letters`)
	if err != nil {
		return c, err
	}
	defer senses.Close()
	for senses.Next() {
		var letters, en, fr string
		if err := senses.Scan(&letters, &en, &fr); err != nil {
			return c, err
		}
		if !known[letters] {
			return c, fmt.Errorf("a meaning is written for %q, which the roots table does not record, so no caller could ever reach it", letters)
		}
		by := map[string]root.Meaning{}
		if en != "" {
			by["en"] = root.Meaning{Plain: en}
		}
		if fr != "" {
			by["fr"] = root.Meaning{Plain: fr}
		}
		if len(by) > 0 {
			c.Meanings[letters] = by
		}
	}
	return c, senses.Err()
}

func write(path string, c root.Corpus) error {
	f, err := os.Create(path)
	if err != nil {
		return err
	}
	defer f.Close()
	enc := json.NewEncoder(f)
	// A line per token: the file is generated, and a generated file nobody can read
	// a diff of is re-reviewed from scratch every time it changes.
	enc.SetIndent("", "")
	enc.SetEscapeHTML(false)
	if err := enc.Encode(corpusFile{Note: note, Corpus: c}); err != nil {
		return err
	}
	return f.Close()
}

func languages(c root.Corpus) []string {
	var langs []string
	for _, by := range c.Meanings {
		for lang := range by {
			if !slices.Contains(langs, lang) {
				langs = append(langs, lang)
			}
		}
	}
	slices.Sort(langs)
	return langs
}
