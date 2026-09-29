// rootdraft drafts a root's senses. It ships nothing.
//
// One call per root: Lane's article and the Qur'an's own glosses, with how often
// a reader meets each, go in together and a sense comes back. An earlier version
// asked a second pass to revise a draft against the corpus, and it made senses
// worse — told it had "missed" a gloss, the model inserted that gloss verbatim as
// a clause, which turns lexicography back into the list of Qur'anic glosses the
// standard moved away from. The corpus informs the writing; it does not correct it.
//
// The output is a TSV a person reads and promotes into data/root_senses.tsv by
// hand. That step is deliberate: the standard is established lexicography checked
// against the corpus, and the check the corpus cannot perform — whether a sense is
// complete — is a human's. ر ح م shipped without "womb" under a gate that scored
// six terms; no threshold found that, a reader did.
//
// The output is an append-only log, and the LAST row for a root is the current
// one. A -force re-run does not replace the earlier row, it writes a newer one
// beside it — so two prompt versions sit in the file together and can be read
// against each other, which is how a prompt change is judged. Whatever promotes
// these into data/root_senses.tsv takes the last row per root.
//
// Built to be re-run. Each stage's prompt is a file, not a string in this
// program; every row records the digest of the prompt that wrote it; a root
// already done is skipped unless -force; and -dry assembles a prompt and calls
// nothing. Iterating means editing a prompt and re-running a handful of roots.
package main

import (
	"context"
	"database/sql"
	"encoding/csv"
	"flag"
	"fmt"
	"os"
	"os/exec"
	"regexp"
	"strings"
	"sync"

	"github.com/MohammadBnei/wird/server/internal/lane"
	_ "modernc.org/sqlite"
)

// A verse citation in any shape. The same expression server/cmd/etl/check.go
// uses, for the same reason: a reference inside a sense is the tafsir boundary
// crossed in machine-readable form.
var verseRef = regexp.MustCompile(`\b\d{1,3}\s*:\s*\d{1,3}\b`)

const draftHeader = "root\tsense_en\tsense_fr\tpoetic_en\tpoetic_fr\tlane\tprompt\tmodel"

type config struct {
	db, laneDir, prompt, out string
	roots                    string
	limit, workers           int
	model, baseURL, apiKey   string
	jsonMode, force, dry     bool
}

func main() {
	var c config
	flag.StringVar(&c.db, "db", "./app/assets/corpus.db", "corpus.db to read the glosses from")
	flag.StringVar(&c.laneDir, "lane", "./data/raw/lane", "the `originals` clone of Lane's TEI; gitignored, consulted, never shipped")
	flag.StringVar(&c.prompt, "prompt", "", "the prompt to send; edit this to iterate")
	flag.StringVar(&c.out, "out", "", "rows land here, for a person to read and promote; append-only, last row for a root wins")
	flag.StringVar(&c.roots, "roots", "", "comma-separated roots; default is every root, commonest first")
	flag.IntVar(&c.limit, "limit", 0, "do this many NEW roots; ones already done do not count against it; 0 means all")
	flag.StringVar(&c.model, "model", "deepseek-ai/DeepSeek-V3.2", "the model to use")
	flag.StringVar(&c.baseURL, "base-url", envOr("OPENAI_BASE_URL", "https://router.huggingface.co/v1"),
		"any OpenAI-shaped endpoint: the HF router, OpenAI, OpenRouter, a local Ollama or vLLM")
	flag.StringVar(&c.apiKey, "api-key", envOr("HF_TOKEN", os.Getenv("OPENAI_API_KEY")),
		"bearer token; falls back to `hf auth token`")
	flag.BoolVar(&c.jsonMode, "json-mode", true, "ask the provider for JSON; some reject the field, so turn it off for those")
	flag.IntVar(&c.workers, "workers", 6, "roots drafted at once; the run waits on the provider, "+
		"not on this machine, so raise it until the provider rate-limits and then back off")
	flag.BoolVar(&c.force, "force", false, "redo roots already in -out")
	flag.BoolVar(&c.dry, "dry", false, "print the assembled prompt for each root and call nothing")
	flag.Parse()

	if c.prompt == "" {
		c.prompt = "./data/root-sense-prompt.md"
	}
	if c.out == "" {
		c.out = "./data/root_senses_draft.tsv"
	}

	if err := draftStage(c); err != nil {
		fmt.Fprintln(os.Stderr, "rootdraft:", err)
		os.Exit(1)
	}
}

// Everything a run needs: the corpus, the prompt, the output, and a model to
// talk to unless this is a dry run.
type stage struct {
	cfg    config
	conn   *sql.DB
	prompt promptFile
	done   map[string]bool
	file   *os.File
	writer drafter
}

func begin(c config, header string) (*stage, error) {
	p, err := readPrompt(c.prompt)
	if err != nil {
		return nil, err
	}
	conn, err := sql.Open("sqlite", c.db)
	if err != nil {
		return nil, err
	}
	s := &stage{cfg: c, conn: conn, prompt: p, done: map[string]bool{}}
	// -dry never skips. It exists to show what WOULD be sent, and a root already
	// done is exactly the one you want to inspect when its row looks wrong.
	if !c.force && !c.dry {
		if s.done, err = alreadyDone(c.out); err != nil {
			return nil, err
		}
	}
	if !c.dry {
		key := c.apiKey
		if key == "" {
			// The token already on this machine, rather than a second one to
			// manage: `hf auth login` puts it where the CLI can print it.
			if out, err := exec.Command("hf", "auth", "token").Output(); err == nil {
				key = strings.TrimSpace(string(out))
			}
		}
		if key == "" {
			return nil, fmt.Errorf("no API key: pass -api-key, set HF_TOKEN or OPENAI_API_KEY, " +
				"or run `hf auth login` so `hf auth token` can print one")
		}
		if s.writer, err = newDrafter(c.baseURL, key, c.model, c.jsonMode); err != nil {
			return nil, err
		}
		if s.file, err = os.OpenFile(c.out, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o644); err != nil {
			return nil, err
		}
		if info, err := s.file.Stat(); err == nil && info.Size() == 0 {
			fmt.Fprintln(s.file, header)
		}
	}
	return s, nil
}

func (s *stage) close() {
	if s.file != nil {
		s.file.Close()
	}
	s.conn.Close()
}

// tally is what a run reports, and it keeps a provider's refusal apart from a
// fault in what came back: conflating them sends you to the wrong file.
type tally struct {
	did, skipped, failed, refused int
	// Which roots failed, so a run that is piped through `tail` — which every
	// long one is — can still say what to re-run. The per-root reason is printed
	// as it happens and scrolls away; this line is at the end, where it survives.
	fell []string
}

func (t tally) report(what, where string, dry bool) error {
	if dry {
		fmt.Fprintf(os.Stderr, "%d prompts assembled, nothing sent\n", t.did)
		return nil
	}
	fmt.Fprintf(os.Stderr, "%d %s, %d already there, %d failed → %s\n", t.did, what, t.skipped, t.failed, where)
	if t.failed == 0 {
		return nil
	}
	fmt.Fprintf(os.Stderr, "re-run them with:  -roots %s\n", strings.Join(t.fell, ","))
	if t.refused > 0 {
		return fmt.Errorf("%d roots failed because the provider refused (%d of them): credit, "+
			"rate limit, or reachability. Nothing to change here — re-run to resume, or point "+
			"-base-url and -model somewhere else", t.failed, t.refused)
	}
	return fmt.Errorf("%d roots failed on what came back; the prompt is what to change, not the rows", t.failed)
}

func (t *tally) blame(root string, err error, raw string) {
	fmt.Fprintf(os.Stderr, "  %s: %v\n", root, err)
	if raw != "" {
		fmt.Fprintf(os.Stderr, "    %s\n", firstLine(raw))
	}
	t.failed++
	t.fell = append(t.fell, root)
	// No body came back at all: the request never reached a model.
	if raw == "" {
		t.refused++
	}
}

func draftStage(c config) error {
	s, err := begin(c, draftHeader)
	if err != nil {
		return err
	}
	defer s.close()

	articles, err := lane.Articles(c.laneDir)
	if err != nil {
		return err
	}
	want, err := chooseRoots(s.conn, c.roots)
	if err != nil {
		return err
	}

	// Settle what this run will attempt before attempting any of it. -limit then
	// means the same under one worker as under twenty, which it would not if the
	// loop stopped on a count several goroutines were racing to raise.
	var t tally
	var todo []string
	for _, root := range want {
		if s.done[root] {
			t.skipped++
			continue
		}
		if c.limit > 0 && len(todo) >= c.limit {
			break
		}
		todo = append(todo, root)
	}

	if c.dry {
		for _, root := range todo {
			subject, err := subjectFor(s.conn, articles, root)
			if err != nil {
				t.blame(root, err, "")
				continue
			}
			fmt.Printf("───── %s (%d occurrences, Lane: %s %d chars)\n%s\n",
				root, subject.Occurrences, subject.LaneHow, subject.LaneChars,
				s.prompt.for_(subject))
			t.did++
		}
		return t.report("drafted", c.out, c.dry)
	}

	// A root's draft is one request and a wait, so the run is bound by the
	// provider rather than by this machine: 1,642 of them in series is hours of
	// mostly waiting. Everything a worker reads is safe to share — database/sql
	// pools its own connections, and the Lane articles and the prompt are built
	// once and never written again — so the lock covers only the two things that
	// are not: the output file and the tally.
	//
	// The log stops being ordered commonest-first, which costs nothing: every row
	// names its own root, and the file was already append-only with the last row
	// for a root winning. A run killed mid-flight still leaves whole rows, because
	// each is written under the lock in one call.
	var mu sync.Mutex
	var wg sync.WaitGroup
	gate := make(chan struct{}, c.workers)
	for _, root := range todo {
		wg.Add(1)
		go func(root string) {
			defer wg.Done()
			gate <- struct{}{}
			defer func() { <-gate }()

			subject, err := subjectFor(s.conn, articles, root)
			if err != nil {
				mu.Lock()
				t.blame(root, err, "")
				mu.Unlock()
				return
			}
			got, raw, err := s.writer.draft(context.Background(), s.prompt.for_(subject))

			mu.Lock()
			defer mu.Unlock()
			if err != nil {
				t.blame(root, err, raw)
				return
			}
			fmt.Fprintf(s.file, "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n",
				root, tab(got.SenseEn), tab(got.SenseFr), tab(got.PoeticEn), tab(got.PoeticFr),
				subject.LaneHow, s.prompt.sha, c.model)
			t.did++
			fmt.Fprintf(os.Stderr, "  %s ✓ %s\n", root, firstLine(got.SenseEn))
		}(root)
	}
	wg.Wait()
	return t.report("drafted", c.out, c.dry)
}

// Commonest first, so a truncated run leaves the roots a reader actually meets
// done rather than an alphabetical prefix.
func chooseRoots(db *sql.DB, only string) ([]string, error) {
	if only != "" {
		return splitRoots(only), nil
	}
	rows, err := db.Query(`SELECT letters FROM roots ORDER BY quran_occurrences DESC, letters`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []string
	for rows.Next() {
		var r string
		if err := rows.Scan(&r); err != nil {
			return nil, err
		}
		out = append(out, r)
	}
	return out, rows.Err()
}

func splitRoots(csv string) []string {
	var out []string
	for _, r := range strings.Split(csv, ",") {
		if r = strings.TrimSpace(r); r != "" {
			out = append(out, r)
		}
	}
	return out
}

// Which roots the output already holds, so a re-run costs only what is new. A
// missing file is not an error: the first run has nothing to resume.
func alreadyDone(path string) (map[string]bool, error) {
	done := map[string]bool{}
	rows, err := readTSV(path)
	if err != nil {
		return nil, err
	}
	for _, r := range rows {
		if len(r) > 0 && r[0] != "root" {
			done[r[0]] = true
		}
	}
	return done, nil
}

func readTSV(path string) ([][]string, error) {
	file, err := os.Open(path)
	if os.IsNotExist(err) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	defer file.Close()
	r := csv.NewReader(file)
	r.Comma = '\t'
	r.FieldsPerRecord = -1
	rows, err := r.ReadAll()
	if err != nil {
		return nil, fmt.Errorf("%s is not readable as TSV: %w", path, err)
	}
	return rows, nil
}

func envOr(name, fallback string) string {
	if v := os.Getenv(name); v != "" {
		return v
	}
	return fallback
}

// A tab or a newline inside a field would silently shift every column after it.
func tab(s string) string {
	return strings.NewReplacer("\t", " ", "\n", " ", "\r", " ").Replace(strings.TrimSpace(s))
}

func firstLine(s string) string {
	if i := strings.IndexByte(s, '\n'); i >= 0 {
		s = s[:i]
	}
	if len(s) > 110 {
		s = s[:110] + "…"
	}
	return s
}
