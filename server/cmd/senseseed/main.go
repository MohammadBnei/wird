// Command senseseed writes the drafted root senses into the server's Postgres,
// which is where a reader's phone fetches them from (docs/adr/0010).
//
// It is a command rather than a goose migration on purpose. ADR 0010's stated
// win is that a sense correction reaches readers in minutes rather than a
// release cycle, and if the only way to write a sense were a migration then a
// correction would need a new file, a review and a deploy — a release cycle
// with extra steps. The seed has to take the path a correction takes, so this
// is that path, run again.
//
// It is a full replace. What is in root_senses afterwards is what the file
// says, and a root the file has stopped carrying is removed, because that is
// the only way a sense nobody stands behind any more stops being served.
//
// The 523 curated senses are not thrown away by this. Zero of them survive as
// prose — the drafts cover all 1,642 roots and not one of them keeps the
// sentence the bundle has today — but data/root_senses.tsv and
// data/root_senses.json stay in the tree, and a second pass over either of them
// can promote them the day a person signs the first one.
package main

import (
	"bufio"
	"context"
	"database/sql"
	"errors"
	"flag"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"regexp"
	"strings"

	_ "modernc.org/sqlite"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/MohammadBnei/wird/server/internal/store"
)

func main() {
	tsv := flag.String("tsv", "./data/root_senses_draft.tsv", "the drafting log to seed from")
	roots := flag.String("roots", "./app/assets/corpus.db", "the corpus.db whose roots table every root is checked against")
	dsn := flag.String("db", env("DATABASE_URL", "postgres://wird:wird@localhost:5432/wird"), "the database to seed")
	dry := flag.Bool("dry", false, "read and check the file, write nothing, and touch no database")
	flag.Parse()

	known, err := knownRoots(*roots)
	if err != nil {
		log.Fatalf("read the roots from %s: %v", *roots, err)
	}
	senses, err := load(*tsv, known)
	if err != nil {
		log.Fatalf("read %s:\n%v", *tsv, err)
	}

	distinct := map[string]bool{}
	for _, s := range senses {
		distinct[s.Root] = true
	}
	fmt.Printf("%s\n  rows %d  roots %d  of %d in the corpus\n",
		*tsv, len(senses), len(distinct), len(known))

	if *dry {
		fmt.Println("  nothing written (-dry)")
		return
	}

	ctx := context.Background()
	// pgxpool.New and store.New rather than store.Open, because Open runs the
	// goose migrations on the way in. This command exists so a correction does
	// not need a deploy, and a tool that migrates whatever database it is aimed
	// at would couple every correction to the operator's working tree — which
	// can be ahead of the image actually serving. api and adminweb migrate on
	// start because they are the deployed artefact; a one-shot run against
	// production is not.
	pool, err := pgxpool.New(ctx, *dsn)
	if err != nil {
		log.Fatalf("database unavailable: %v", err)
	}
	defer pool.Close()
	db := store.New(pool)

	if err := db.ReplaceSenses(ctx, senses); err != nil {
		log.Fatalf("write the senses: %v", err)
	}
	// The version, so whoever ran this can compare it against what the route
	// answers with and see the new pack land rather than hope it did.
	version, err := db.SensesVersion(ctx)
	if err != nil {
		log.Fatalf("read the pack version back: %v", err)
	}
	fmt.Printf("  written; /v1/senses now hashes to %s, and answers it as an\n"+
		"  ETag of \"<revision>-%s\" — the revision is the provenance prose's,\n"+
		"  bumped by hand in package api when that prose changes.\n", version, version)
}

// The columns of the drafting log, in the order it writes them. Only the first
// five are read here: lane, prompt and model are how a row was produced and
// belong to the log rather than to what is served.
const (
	colRoot = iota
	colSenseEn
	colSenseFr
	colPoeticEn
	colPoeticFr
	colsRead
)

// verseRef is check.go's guard, re-applied. A verse reference inside a root's
// sense is the tafsir boundary crossed in machine-readable form: the sense has
// stopped being about the word.
//
// ponytail: copied from server/cmd/etl/check.go rather than shared. Both are
// package main, so sharing it means a third package for one regexp, and the ETL
// is the half of this boundary that is being taken apart anyway.
var verseRef = regexp.MustCompile(`\b\d{1,3}\s*:\s*\d{1,3}\b`)

// load reads the log in file order and checks every row. Order is the whole of
// the last-row-per-root rule: the rows go to the database as they are read, the
// primary key collapses them, and the last row for a root wins — which is the
// log's own rule with no selection code under it.
//
// Nothing here reorders a sense's clauses. 40 of the 1,642 rows have a
// different number of English and French clauses, and rootcheck's Order refuses
// exactly that pair — but its refusal protects a permutation, and this permutes
// nothing. Clause order is one of the six terms of a bar these drafts never
// passed, and their basis says so; reordering them here would dress an unsigned
// draft in one term of a standard it has not met.
//
// Every bad row is reported rather than the first, because an operator fixing a
// file wants the whole list and a seed is all-or-nothing anyway.
func load(path string, known map[string]bool) ([]store.Sense, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()

	var senses []store.Sense
	var errs []error
	sc := bufio.NewScanner(f)
	for line := 1; sc.Scan(); line++ {
		text := sc.Text()
		if strings.TrimSpace(text) == "" {
			continue
		}
		// A byte-order mark makes the first column "\ufeffroot" rather than
		// "root", which is not a root either and would refuse the run with a
		// message about a root instead of about the file.
		text = strings.TrimPrefix(text, "\ufeff")
		col := strings.Split(text, "\t")
		// The header, which rootcheck's own reader does not skip — and left in,
		// the root check below would refuse the whole run over the literal
		// word "root". Not anchored to line 1: a leading blank line moves it,
		// and `root` is not an Arabic root wherever it sits, so the check below
		// would refuse it from any line anyway.
		if col[colRoot] == "root" {
			continue
		}
		if len(col) < colsRead {
			errs = append(errs, fmt.Errorf("line %d: %d columns, and a row is root, English, French and the two poetic registers", line, len(col)))
			continue
		}
		s := store.Sense{
			Root: strings.TrimSpace(col[colRoot]),
			En:   strings.TrimSpace(col[colSenseEn]),
			Fr:   strings.TrimSpace(col[colSenseFr]),
			// The poetic register is stored and never served. It is read here
			// because this file is the only thing that holds it.
			PoeticEn: strings.TrimSpace(col[colPoeticEn]),
			PoeticFr: strings.TrimSpace(col[colPoeticFr]),
		}
		bad := len(errs)
		switch {
		case !known[s.Root]:
			// By name, because the answer is almost always a spelling: a root
			// the corpus does not record is a sense no reader could reach.
			errs = append(errs, fmt.Errorf("line %d: the corpus records no root %q", line, s.Root))
		case s.En == "":
			errs = append(errs, fmt.Errorf("line %d: root %s has no English, and a sense ships in both languages or neither", line, s.Root))
		case s.Fr == "":
			errs = append(errs, fmt.Errorf("line %d: root %s has no French, and a sense ships in both languages or neither", line, s.Root))
		}
		for _, text := range []string{s.En, s.Fr} {
			if m := verseRef.FindString(text); m != "" {
				errs = append(errs, fmt.Errorf("line %d: root %s cites verse %s; a root's sense is a claim about the word and never about a verse",
					line, s.Root, m))
			}
		}
		if len(errs) == bad {
			senses = append(senses, s)
		}
	}
	if err := sc.Err(); err != nil {
		return nil, err
	}
	if len(senses) == 0 && len(errs) == 0 {
		// A full replace over an empty file would empty the table and the route
		// would answer 200 with no senses, which every phone would apply.
		return nil, errors.New("no senses in the file, and a seed of nothing would unpublish every sense there is")
	}
	return senses, errors.Join(errs...)
}

// knownRoots is the 1,642 roots the bundled corpus records, which is what a
// root is checked against. This is better than an Arabic-range CHECK in the
// schema and it is what jidhrcorpus already does at its own read: a root that
// is spelled in Arabic and is not in the corpus is a row no caller can reach.
func knownRoots(path string) (map[string]bool, error) {
	db, err := sql.Open("sqlite", "file:"+filepath.Clean(path)+"?mode=ro")
	if err != nil {
		return nil, err
	}
	defer db.Close()

	rows, err := db.Query(`SELECT letters FROM roots`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	known := map[string]bool{}
	for rows.Next() {
		var letters string
		if err := rows.Scan(&letters); err != nil {
			return nil, err
		}
		known[letters] = true
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	if len(known) == 0 {
		return nil, errors.New("the roots table is empty, so every root would be refused as unknown")
	}
	return known, nil
}

func env(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
