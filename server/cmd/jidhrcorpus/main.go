// Command jidhrcorpus writes the corpus jidhr serves. The morphology — the roots,
// the attested spellings, and the forms the corpus records under no root — comes out
// of the app/assets/corpus.db the app bundles, because it is the Quranic Arabic
// Corpus and Wird neither wrote it nor may correct it. The meanings come out of the
// Wird server's Postgres, because Wird wrote them and a correction to one has to
// reach a reader without a release (docs/adr/0010).
//
// So this command now needs a database. The paragraph that stood here argued that
// corpus.db was the single checked artefact both the root engine and the app answer
// from; that argument has moved to Postgres for the half of the data Wird authors,
// and corpus.db keeps it for the half it does not. Point -pg at the same database
// GET /v1/senses serves, or the exported meanings are whatever was last seeded
// somewhere else and rootd answers with prose no reader is being shown.
package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"slices"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/MohammadBnei/wird/jidhr/pkg/root"
	"github.com/MohammadBnei/wird/server/internal/store"
	_ "modernc.org/sqlite"
)

// note travels with the corpus because a caller outside Wird has no other place to
// learn which half of the file came from where, or how much authority the prose in
// it carries — which is none.
//
// It does not repeat the sentence a reader is shown under a sense. That sentence is
// served with the senses by GET /v1/senses and has exactly one holder, beside that
// handler; ADR 0010 exists to collapse three copies of it to one, and this file is
// not going to be the fourth.
const note = "The corpus rootd serves, written by server/cmd/jidhrcorpus. The roots, the attested " +
	"forms and the forms recorded under no root are the Quranic Arabic Corpus morphology, read out of " +
	"app/assets/corpus.db. The meanings are Wird's own, read out of the Wird server's database: drafts " +
	"written by a language model from each root's own words in the Qur'an, checked by no person, quoted " +
	"from no lexicon, and carrying nobody's authority. Rebuild from both sources; editing this file by " +
	"hand puts it out of step with the corpus and with the server."

func main() {
	// -db keeps its name and its meaning: the corpus.db the morphology is read out
	// of. The new flag is -pg, so a run that has not learnt about it fails on a
	// database it cannot reach rather than quietly exporting a corpus with no
	// meanings in it.
	in := flag.String("db", "./app/assets/corpus.db", "the corpus.db the app bundles")
	dsn := flag.String("pg", env("DATABASE_URL", "postgres://wird:wird@localhost:5432/wird"),
		"the Wird database the root senses are read out of")
	out := flag.String("out", "./jidhr/testdata/quran.json", "the jidhr corpus to write")
	flag.Parse()

	db, err := sql.Open("sqlite", "file:"+filepath.Clean(*in)+"?mode=ro")
	if err != nil {
		log.Fatalf("open %s: %v", *in, err)
	}
	defer db.Close()

	ctx := context.Background()
	// pgxpool.New rather than store.Open, which migrates on the way in. This is a
	// read, and a read-only tool that migrates the database it reads couples a
	// corpus rebuild to whatever migrations the operator's tree happens to carry.
	// senseseed makes the same choice for the same reason.
	pool, err := pgxpool.New(ctx, *dsn)
	if err != nil {
		log.Fatalf("database unavailable: %v", err)
	}
	defer pool.Close()

	// store.Senses rather than the SELECT written out a second time here. It is the
	// same read GET /v1/senses answers from, in the same order, so the export and
	// the route cannot hold different prose — which is the divergence ADR 0010
	// exists to end, and writing the query again here would reopen it one refactor
	// later. It also makes the poetic register absent rather than dropped: that read
	// does not select those columns at all.
	pack, err := store.New(pool).Senses(ctx)
	if err != nil {
		log.Fatalf("read the senses from %s: %v", *dsn, err)
	}

	c, err := build(db, pack.Senses)
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
	fmt.Printf("%s\n  roots %d  attested forms %d  rootless forms %d  roots with a meaning %d  languages %v\n  %.2f MB\n",
		*out, len(c.Roots), len(c.Attested), len(c.Rootless), len(c.Meanings), languages(c), float64(fi.Size())/(1<<20))
}

// corpusFile is what jidhr reads, with the provenance note the reader of the file
// needs and the loader ignores.
type corpusFile struct {
	Note string `json:"note"`
	root.Corpus
}

// build reads the morphology out of corpus.db and takes the meanings already read
// out of Postgres. The senses come in as an argument rather than being fetched here
// because the two halves have different owners and different failure modes, and
// because it keeps every test below able to state a sense without a database.
func build(db *sql.DB, senses []store.Sense) (root.Corpus, error) {
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
	// spelled as the corpus spells them, diacritics and all, less the recitation
	// marks: corpus.db keeps the pause and sajda marks glued to the word they
	// follow, space and all, and a form shipped that way is keyed under a spelling
	// with a space in it that no reader can type. jidhr normalises what it indexes
	// but decides one code point at a time, so the space outlives the mark; the
	// cleaning belongs here, where the word is read out of the database, and is the
	// same range app/lib/data/root_repo.dart strips at its own read.
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
		// Cleaning merges spellings that differed only by the mark, so the same
		// pair arrives twice.
		if form = root.TrimMarks(form); form != "" && !slices.Contains(c.Attested[form], letters) {
			c.Attested[form] = append(c.Attested[form], letters)
		}
	}
	if err := forms.Err(); err != nil {
		return c, err
	}

	// The morphology records a particle or a pronoun under no root deliberately, and
	// that is as much a corpus fact as a root is. Shipping those spellings is what
	// lets jidhr answer مِنْ with "it has no root" instead of with منن, which is what
	// the letters say once the diacritics are gone and what the authority denies.
	// Same cleaning, for the same reason as the attested forms.
	rootless, err := db.Query(`SELECT DISTINCT text_ar FROM words
		WHERE root_letters IS NULL OR root_letters = '' ORDER BY text_ar`)
	if err != nil {
		return c, err
	}
	defer rootless.Close()
	seen := map[string]bool{}
	for rootless.Next() {
		var form string
		if err := rootless.Scan(&form); err != nil {
			return c, err
		}
		if form = root.TrimMarks(form); form != "" && !seen[form] {
			seen[form] = true
			c.Rootless = append(c.Rootless, form)
		}
	}
	if err := rootless.Err(); err != nil {
		return c, err
	}

	// The senses come from the server, which is the only place they are written now.
	// The check that every one of them names a root the morphology records is kept
	// exactly as it was: the two halves of this file come from two databases that
	// nothing joins, so this is the only place a sense written for a root no caller
	// can look up gets caught. senseseed makes the same check on the way in, and
	// this makes it again on the way out, because the two can be run against
	// different corpus.db files.
	//
	// No poetic register is written: store.Sense carries the columns and the read
	// above does not select them, so an unwritten register is absent, never blank —
	// which jidhr/pkg/root/meaning_test.go fails the corpus over.
	for _, sn := range senses {
		if !known[sn.Root] {
			return c, fmt.Errorf("a meaning is written for %q, which the roots table does not record, so no caller could ever reach it", sn.Root)
		}
		by := map[string]root.Meaning{}
		if sn.En != "" {
			by["en"] = root.Meaning{Plain: sn.En}
		}
		if sn.Fr != "" {
			by["fr"] = root.Meaning{Plain: sn.Fr}
		}
		if len(by) > 0 {
			c.Meanings[sn.Root] = by
		}
	}
	return c, nil
}

// env reads the DSN default from the environment, so a run against a deployed
// database is a variable rather than a password in a shell history.
func env(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func write(path string, c root.Corpus) error {
	f, err := os.Create(path)
	if err != nil {
		return err
	}
	enc := json.NewEncoder(f)
	// A line per token: the file is generated, and a generated file nobody can read
	// a diff of is re-reviewed from scratch every time it changes.
	enc.SetIndent("", "")
	enc.SetEscapeHTML(false)
	if err := enc.Encode(corpusFile{Note: note, Corpus: c}); err != nil {
		f.Close()
		return err
	}
	// The close is the write: a deferred one drops the error that says the file on
	// disk is short, and a corpus that is half-written is not a corpus.
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
