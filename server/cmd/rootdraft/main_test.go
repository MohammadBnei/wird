package main

import (
	"bytes"
	"flag"
	"strings"
	"testing"
)

// Every variable reads as a sentinel, so a flag default taken from ANY env
// var — the token, the base URL with credentials in it, a flag added later —
// shows up in -h.
func sentinelEnv(name string) string { return "SENTINEL_" + name }

func envMap(m map[string]string) func(string) string {
	return func(k string) string { return m[k] }
}

// noHF is a machine with no `hf auth login`.
func noHF() string { return "" }

func help(t *testing.T, getenv func(string) string) string {
	t.Helper()
	fs := flag.NewFlagSet("rootdraft", flag.ContinueOnError)
	var buf bytes.Buffer
	fs.SetOutput(&buf)
	if _, err := loadConfig(fs, []string{"-h"}, getenv, noHF); err != flag.ErrHelp {
		t.Fatalf("-h: got %v, want flag.ErrHelp", err)
	}
	return buf.String()
}

// The failure: -h (and every flag error, which prints the same text) shows the
// live HF token or a DSN in a terminal, a screenshot, a pasted log.
func TestHelpNeverPrintsAValueFromTheEnvironment(t *testing.T) {
	out := help(t, sentinelEnv)
	if strings.Contains(out, "SENTINEL") {
		t.Fatalf("-h printed an environment value:\n%s", out)
	}
	// Positive control: this is the real help, and it names the variables.
	for _, want := range []string{"-model", "-base-url", "HF_TOKEN", "OPENAI_API_KEY", "OPENAI_BASE_URL"} {
		if !strings.Contains(out, want) {
			t.Errorf("-h does not mention %s:\n%s", want, out)
		}
	}
}

func TestTheTokenComesFromTheEnvironmentOnly(t *testing.T) {
	fs := flag.NewFlagSet("rootdraft", flag.ContinueOnError)
	c, err := loadConfig(fs, nil, envMap(map[string]string{"HF_TOKEN": "hf_K1", "OPENAI_API_KEY": "oa_K2"}), noHF)
	if err != nil {
		t.Fatal(err)
	}
	if fs.Lookup("api-key") != nil {
		t.Error("-api-key is a flag again; a token on the command line is in the shell history")
	}
	if c.APIKey != "hf_K1" {
		t.Errorf("both set: key %q, want HF_TOKEN's hf_K1", c.APIKey)
	}
	c, _ = loadConfig(flag.NewFlagSet("", flag.ContinueOnError), nil, envMap(map[string]string{"OPENAI_API_KEY": "oa_K2"}), noHF)
	if c.APIKey != "oa_K2" {
		t.Errorf("only OPENAI_API_KEY: key %q, want oa_K2", c.APIKey)
	}
}

func TestTheBaseURLIsTheFlagThenTheEnvironmentThenTheRouter(t *testing.T) {
	env := envMap(map[string]string{"OPENAI_BASE_URL": "http://env/v1"})
	for _, tc := range []struct {
		args   []string
		getenv func(string) string
		want   string
	}{
		{[]string{"-dry", "-base-url", "http://flag/v1"}, env, "http://flag/v1"},
		{[]string{"-dry"}, env, "http://env/v1"},
		{[]string{"-dry"}, envMap(nil), defaultBaseURL},
	} {
		c, err := loadConfig(flag.NewFlagSet("", flag.ContinueOnError), tc.args, tc.getenv, noHF)
		if err != nil || c.BaseURL != tc.want {
			t.Errorf("%v: base URL %q, %v; want %q", tc.args, c.BaseURL, err, tc.want)
		}
	}
}
