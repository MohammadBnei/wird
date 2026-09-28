// rootdraft writes a first draft of every root's sense, from Lane's article and
// the corpus's own glosses, in English and French and in two registers.
//
// It writes DRAFTS. Nothing here reaches a reader: the output is a TSV a person
// reads and promotes into data/root_senses.tsv by hand, because the standard is
// established lexicography checked against the corpus, and the check that the
// corpus cannot perform — whether a sense is complete — is a human's. رحم shipped
// without "womb" under a gate that scored six terms; no threshold found that, a
// reader did.
//
// The output is an append-only log, and the LAST row for a root is the current
// one. A -force re-run does not replace the earlier row, it writes a newer one
// beside it — so two prompt versions sit in the file together and can be read
// against each other, which is how a prompt change is judged. Whatever promotes
// these into data/root_senses.tsv takes the last row per root.
//
// Built to be re-run. The prompt is a file, not a string in this program; every
// row records its digest; and a root already drafted is skipped unless -force,
// so iterating means editing data/root-sense-prompt.md and re-running a handful
// of roots rather than paying for 1,642 again. -dry prints the assembled prompt
// and calls nothing.
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

	"github.com/MohammadBnei/wird/server/internal/lane"
	_ "modernc.org/sqlite"
)

// A verse citation in any shape. The same expression server/cmd/etl/check.go
// uses, for the same reason: a reference inside a sense is the tafsir boundary
// crossed in machine-readable form.
var verseRef = regexp.MustCompile(`\b\d{1,3}\s*:\s*\d{1,3}\b`)

const header = "root\tsense_en\tsense_fr\tpoetic_en\tpoetic_fr\tlane\tprompt\tmodel"

func main() {
	db := flag.String("db", "./app/assets/corpus.db", "corpus.db to read the glosses from")
	laneDir := flag.String("lane", "./data/raw/lane", "the `originals` clone of Lane's TEI; gitignored, consulted, never shipped")
	promptPath := flag.String("prompt", "./data/root-sense-prompt.md", "the prompt to send; edit this to iterate")
	out := flag.String("out", "./data/root_senses_draft.tsv", "drafts land here, for a person to read and promote; append-only, last row for a root wins")
	roots := flag.String("roots", "", "comma-separated roots to draft; default is every root")
	limit := flag.Int("limit", 0, "draft at most this many, commonest first; 0 means no limit")
	model := flag.String("model", "deepseek-ai/DeepSeek-V3.2", "the model to draft with")
	baseURL := flag.String("base-url", envOr("OPENAI_BASE_URL", "https://router.huggingface.co/v1"),
		"any OpenAI-shaped endpoint: the HF router, OpenAI, OpenRouter, a local Ollama or vLLM")
	apiKey := flag.String("api-key", envOr("HF_TOKEN", os.Getenv("OPENAI_API_KEY")),
		"bearer token; falls back to `hf auth token`")
	jsonMode := flag.Bool("json-mode", true, "ask the provider for JSON; some reject the field, so turn it off for those")
	force := flag.Bool("force", false, "redraft roots already in -out")
	dry := flag.Bool("dry", false, "print the assembled prompt for each root and call nothing")
	flag.Parse()

	if err := run(*db, *laneDir, *promptPath, *out, *roots, *limit, *model, *baseURL, *apiKey, *jsonMode, *force, *dry); err != nil {
		fmt.Fprintln(os.Stderr, "rootdraft:", err)
		os.Exit(1)
	}
}

func run(dbPath, laneDir, promptPath, outPath, only string, limit int, model, baseURL, apiKey string, jsonMode, force, dry bool) error {
	prompt, err := readPrompt(promptPath)
	if err != nil {
		return err
	}
	conn, err := sql.Open("sqlite", dbPath)
	if err != nil {
		return err
	}
	defer conn.Close()

	articles, err := lane.Articles(laneDir)
	if err != nil {
		return err
	}

	want, err := chooseRoots(conn, only, limit)
	if err != nil {
		return err
	}
	done := map[string]bool{}
	// -dry never skips. It exists to show what WOULD be sent, and a root already
	// drafted is exactly the one you want to inspect when its row looks wrong.
	if !force && !dry {
		if done, err = alreadyDrafted(outPath); err != nil {
			return err
		}
	}

	var writer drafter
	if !dry {
		key := apiKey
		if key == "" {
			// The token already on this machine, rather than a second one to
			// manage: `hf auth login` puts it where the CLI can print it.
			if out, err := exec.Command("hf", "auth", "token").Output(); err == nil {
				key = strings.TrimSpace(string(out))
			}
		}
		if key == "" {
			return fmt.Errorf("no API key: pass -api-key, set HF_TOKEN or OPENAI_API_KEY, " +
				"or run `hf auth login` so `hf auth token` can print one")
		}
		if writer, err = newDrafter(baseURL, key, model, jsonMode); err != nil {
			return err
		}
	}

	file, err := os.OpenFile(outPath, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o644)
	if err != nil {
		return err
	}
	defer file.Close()
	if info, err := file.Stat(); err == nil && info.Size() == 0 {
		fmt.Fprintln(file, header)
	}

	var drafts, skipped, failed, refused int
	for _, root := range want {
		if done[root] {
			skipped++
			continue
		}
		subject, err := subjectFor(conn, articles, root)
		if err != nil {
			fmt.Fprintf(os.Stderr, "  %s: %v\n", root, err)
			failed++
			continue
		}
		text := prompt.for_(subject)
		if dry {
			fmt.Printf("───── %s (%d occurrences, Lane: %s %d chars)\n%s\n",
				root, subject.Occurrences, subject.LaneHow, subject.LaneChars, text)
			continue
		}
		got, raw, err := writer.draft(context.Background(), text)
		if err != nil {
			fmt.Fprintf(os.Stderr, "  %s: %v\n", root, err)
			if raw != "" {
				fmt.Fprintf(os.Stderr, "    %s\n", firstLine(raw))
			}
			failed++
			// No body came back at all: the request never reached a model.
			if raw == "" {
				refused++
			}
			continue
		}
		fmt.Fprintf(file, "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n",
			root, tab(got.SenseEn), tab(got.SenseFr), tab(got.PoeticEn), tab(got.PoeticFr),
			subject.LaneHow, prompt.sha, model)
		drafts++
		fmt.Fprintf(os.Stderr, "  %s ✓ %s\n", root, firstLine(got.SenseEn))
	}
	if dry {
		fmt.Fprintf(os.Stderr, "%d prompts assembled, nothing sent\n", len(want))
		return nil
	}
	fmt.Fprintf(os.Stderr, "%d drafted, %d already there, %d failed → %s\n",
		drafts, skipped, failed, outPath)
	if failed > 0 {
		// Two different failures, and conflating them sends you to the wrong file.
		// A provider that refused — no credit, rate limited, unreachable — says
		// nothing about the prompt, and re-running picks up exactly what is left
		// because the rows already written are skipped.
		if refused > 0 {
			return fmt.Errorf("%d roots failed because the provider refused (%d of them): "+
				"credit, rate limit, or reachability. Nothing to change here — re-run to "+
				"resume, or point -base-url and -model somewhere else", failed, refused)
		}
		return fmt.Errorf("%d roots failed on what came back; the prompt is what to change, "+
			"not the rows", failed)
	}
	return nil
}

func envOr(name, fallback string) string {
	if v := os.Getenv(name); v != "" {
		return v
	}
	return fallback
}

// Commonest first, so a truncated run leaves the roots a reader actually meets
// drafted rather than an alphabetical prefix.
func chooseRoots(db *sql.DB, only string, limit int) ([]string, error) {
	if only != "" {
		var out []string
		for _, r := range strings.Split(only, ",") {
			if r = strings.TrimSpace(r); r != "" {
				out = append(out, r)
			}
		}
		return out, nil
	}
	q := `SELECT letters FROM roots ORDER BY quran_occurrences DESC, letters`
	if limit > 0 {
		q += fmt.Sprintf(" LIMIT %d", limit)
	}
	rows, err := db.Query(q)
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

// Which roots the output already holds, so a re-run costs only what is new. A
// missing file is not an error: the first run has nothing to resume.
func alreadyDrafted(path string) (map[string]bool, error) {
	done := map[string]bool{}
	file, err := os.Open(path)
	if os.IsNotExist(err) {
		return done, nil
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
	for _, row := range rows {
		if len(row) > 0 && row[0] != "root" {
			done[row[0]] = true
		}
	}
	return done, nil
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
