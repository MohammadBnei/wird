package main

import (
	"cmp"
	"errors"
	"flag"
	"fmt"
	"os"
	"os/exec"
	"strings"
)

// Config is the whole of rootdraft's configuration, read once at start. The
// table under "### `rootdraft`" in docs/architecture/pipelines.md lists every
// flag and variable with its default, and TestConfigDocumented holds the two
// to the same set.
type Config struct {
	DB, LaneDir, Prompt, Out string
	Roots                    string
	Limit, Workers           int
	Model, BaseURL, APIKey   string
	JSONMode, Force, Dry     bool
}

// loadConfig reads the flags and then the environment, with every problem in
// one error. The token is never a flag, nor any flag's default: a flag default
// is printed by -h and by every flag error, so a token there lands in a
// terminal, a screenshot or a CI log. No default here reads the environment at
// all; the env fills a flag left empty after parsing, so -h only ever names a
// variable.
//
// hfToken is `hf auth token`, asked only by a run that will call a model and
// has no token in the environment.
func loadConfig(fs *flag.FlagSet, args []string, getenv func(string) string, hfToken func() string) (Config, error) {
	var c Config
	fs.StringVar(&c.DB, "db", "./app/assets/corpus.db", "corpus.db to read the glosses from")
	fs.StringVar(&c.LaneDir, "lane", "./data/raw/lane", "the `originals` clone of Lane's TEI; gitignored, consulted, never shipped")
	fs.StringVar(&c.Prompt, "prompt", "", "the prompt to send; edit this to iterate")
	fs.StringVar(&c.Out, "out", "", "rows land here, for a person to read and promote; append-only, last row for a root wins")
	fs.StringVar(&c.Roots, "roots", "", "comma-separated roots; default is every root, commonest first")
	fs.IntVar(&c.Limit, "limit", 0, "do this many NEW roots; ones already done do not count against it; 0 means all")
	fs.StringVar(&c.Model, "model", "deepseek-ai/DeepSeek-V3.2", "the model to use")
	fs.StringVar(&c.BaseURL, "base-url", "", "any OpenAI-shaped endpoint: the HF router, OpenAI, OpenRouter, a local Ollama or vLLM; "+
		"default $OPENAI_BASE_URL, else "+defaultBaseURL)
	fs.BoolVar(&c.JSONMode, "json-mode", true, "ask the provider for JSON; some reject the field, so turn it off for those")
	fs.IntVar(&c.Workers, "workers", 6, "roots drafted at once; the run waits on the provider, "+
		"not on this machine, so raise it until the provider rate-limits and then back off")
	fs.BoolVar(&c.Force, "force", false, "redo roots already in -out")
	fs.BoolVar(&c.Dry, "dry", false, "print the assembled prompt for each root and call nothing")
	fs.Usage = func() {
		fmt.Fprintf(fs.Output(), "Usage of %s:\n", fs.Name())
		fs.PrintDefaults()
		fmt.Fprintln(fs.Output(), "\nEnvironment (read, never printed):\n"+
			"  HF_TOKEN, else OPENAI_API_KEY, else `hf auth token`  the bearer token\n"+
			"  OPENAI_BASE_URL  the endpoint when -base-url is not given")
	}
	if err := fs.Parse(args); err != nil {
		return c, err
	}
	if c.Prompt == "" {
		c.Prompt = "./data/root-sense-prompt.md"
	}
	if c.Out == "" {
		c.Out = "./data/root_senses_draft.tsv"
	}
	if c.BaseURL == "" {
		c.BaseURL = cmp.Or(getenv("OPENAI_BASE_URL"), defaultBaseURL)
	}
	c.APIKey = cmp.Or(getenv("HF_TOKEN"), getenv("OPENAI_API_KEY"))

	// -dry calls nothing, so it needs no token and runs no workers.
	if c.Dry {
		return c, nil
	}
	var errs []error
	if c.APIKey == "" {
		// The token already on this machine, rather than a second one to
		// manage: `hf auth login` puts it where the CLI can print it.
		c.APIKey = hfToken()
	}
	if c.APIKey == "" {
		errs = append(errs, errors.New("no API key: set HF_TOKEN or OPENAI_API_KEY, "+
			"or run `hf auth login` so `hf auth token` can print one"))
	}
	// 0 blocks every worker on the gate forever, and below 0 is a panic.
	if c.Workers < 1 {
		errs = append(errs, errors.New("-workers must be 1 or more"))
	}
	return c, errors.Join(errs...)
}

// hfToken is the token `hf auth token` prints, or "" when there is none.
func hfToken() string {
	out, err := exec.Command("hf", "auth", "token").Output()
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(out))
}

// fromProcess is the one place rootdraft reads its real command line and
// environment.
func fromProcess() (Config, error) {
	return loadConfig(flag.CommandLine, os.Args[1:], os.Getenv, hfToken)
}
