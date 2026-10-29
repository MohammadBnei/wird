package main

import (
	"bufio"
	"maps"
	"os"
	"slices"
	"strings"
	"testing"
)

// prod is every variable set, each to a value no other holds, so a value read
// into the wrong field shows in the Config compared below.
var prod = map[string]string{
	"DATABASE_URL":       "postgres://u:p@db.example:5432/wird",
	"OIDC_ISSUER":        "https://idp.example/application/o/wird-admin/",
	"OIDC_CLIENT_ID":     "proxy-client-id",
	"OIDC_CLIENT_SECRET": "proxy-client-secret",
	"OIDC_AUDIENCE":      "stub-audience",
	"NOCTURNE_CSS":       "/app/nocturne.css",
	"ADMIN_ADDR":         ":9998",
}

func with(base map[string]string, kv ...string) map[string]string {
	m := map[string]string{}
	for k, v := range base {
		m[k] = v
	}
	for i := 0; i < len(kv); i += 2 {
		if kv[i+1] == "" {
			delete(m, kv[i])
		} else {
			m[kv[i]] = kv[i+1]
		}
	}
	return m
}

// The deployment's values come out where main uses them: OIDC_CLIENT_ID wins
// over OIDC_AUDIENCE, and the issuer keeps its trailing slash.
func TestAProductionValueLandsInTheWrongField(t *testing.T) {
	got, err := load(func(k string) string { return prod[k] })
	if err != nil {
		t.Fatal(err)
	}
	want := Config{
		DatabaseURL:  "postgres://u:p@db.example:5432/wird",
		OIDCIssuer:   "https://idp.example/application/o/wird-admin/",
		Audience:     "proxy-client-id",
		ClientSecret: "proxy-client-secret",
		CSSPath:      "/app/nocturne.css",
		Addr:         ":9998",
	}
	if got != want {
		t.Errorf("got %+v\nwant %+v", got, want)
	}
	// The local stub: no id, no secret, its own audience, the issuer's keys.
	got, err = load(func(k string) string { return with(prod, "OIDC_CLIENT_ID", "", "OIDC_CLIENT_SECRET", "")[k] })
	if err != nil || got.Audience != "stub-audience" || got.ClientSecret != "" {
		t.Errorf("stub: %+v, %v", got, err)
	}
}

// WIRD_DEV=1 alone is the local compose stack.
func TestALocalRunNeedsMoreThanWirdDev(t *testing.T) {
	got, err := load(func(k string) string { return map[string]string{"WIRD_DEV": "1"}[k] })
	if err != nil {
		t.Fatal(err)
	}
	want := Config{Dev: true, DatabaseURL: devDatabaseURL, OIDCIssuer: devIssuer, Audience: devAudience,
		CSSPath: "docs/design/nocturne-styles.css", Addr: ":8081"}
	if got != want {
		t.Errorf("got %+v, want %+v", got, want)
	}
}

// Each refusal, with every problem in one error, and never a value in it.
func TestAHalfConfiguredDeploymentStarts(t *testing.T) {
	for _, c := range []struct {
		name string
		env  map[string]string
		want []string
	}{
		{"nothing", nil, []string{
			"DATABASE_URL is unset (WIRD_DEV=1 uses the local default)",
			"OIDC_ISSUER is unset (WIRD_DEV=1 uses the local default)",
			"OIDC_CLIENT_ID or OIDC_AUDIENCE is unset (WIRD_DEV=1 uses the local default)",
		}},
		{"no issuer", with(prod, "OIDC_ISSUER", ""), []string{"OIDC_ISSUER is unset (WIRD_DEV=1 uses the local default)"}},
		{"WIRD_DEV not 1", with(prod, "WIRD_DEV", "yes"), []string{"WIRD_DEV must be 1 or unset"}},
		{"id, no secret", with(prod, "OIDC_CLIENT_SECRET", ""), []string{"OIDC_CLIENT_ID is set but OIDC_CLIENT_SECRET is not"}},
		{"secret, no id", with(prod, "OIDC_CLIENT_ID", ""), []string{"OIDC_CLIENT_SECRET is set but OIDC_CLIENT_ID is not"}},
		{"secret, no id, no audience", with(prod, "OIDC_CLIENT_ID", "", "OIDC_AUDIENCE", ""), []string{
			"OIDC_CLIENT_SECRET is set but OIDC_CLIENT_ID is not",
			"OIDC_CLIENT_ID or OIDC_AUDIENCE is unset (WIRD_DEV=1 uses the local default)",
		}},
		{"dev still pairs id and secret", map[string]string{"WIRD_DEV": "1", "OIDC_CLIENT_SECRET": "proxy-client-secret"},
			[]string{"OIDC_CLIENT_SECRET is set but OIDC_CLIENT_ID is not"}},
	} {
		_, err := load(func(k string) string { return c.env[k] })
		if err == nil {
			t.Errorf("%s: started", c.name)
			continue
		}
		if got := strings.Split(err.Error(), "\n"); !slices.Equal(got, c.want) {
			t.Errorf("%s: refused with\n%q\nwant\n%q", c.name, got, c.want)
		}
		for k, v := range c.env {
			if len(v) >= 4 && strings.Contains(err.Error(), v) {
				t.Errorf("%s: the refusal shows %s's value", c.name, k)
			}
		}
	}
}

// TestConfigDocumented: what load reads, envVars, and the variable table in
// docs/architecture/adminweb.md are one set.
func TestConfigDocumented(t *testing.T) {
	read := map[string]bool{}
	if _, err := load(func(k string) string { read[k] = true; return prod[k] }); err != nil {
		t.Fatal(err)
	}
	if got := slices.Sorted(maps.Keys(read)); !slices.Equal(got, slices.Sorted(slices.Values(envVars))) {
		t.Errorf("load reads %v, envVars lists %v", got, envVars)
	}
	if got := documented(t, "../../../docs/architecture/adminweb.md"); !slices.Equal(got, envVars) {
		t.Errorf("adminweb.md's table lists %v, envVars %v (same order)", got, envVars)
	}
}

// documented is the first cell of each row of the first table in path whose
// header starts "| Variable |", backticks dropped.
func documented(t *testing.T, path string) []string {
	t.Helper()
	f, err := os.Open(path)
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	var names []string
	in := false
	for sc := bufio.NewScanner(f); sc.Scan(); {
		line := sc.Text()
		switch {
		case strings.HasPrefix(line, "| Variable |"):
			in = true
		case in && strings.HasPrefix(line, "|---"), in && strings.HasPrefix(line, "| ---"):
		case in && strings.HasPrefix(line, "|"):
			names = append(names, strings.Trim(strings.TrimSpace(strings.Split(line, "|")[1]), "`"))
		case in:
			return names
		}
	}
	return names
}

// Tracing is off unless OTEL_EXPORTER_OTLP_TRACES_ENDPOINT says where to send
// it: the SDK's catch-all OTEL_EXPORTER_OTLP_ENDPOINT is never read. A value
// that is not an http(s) URL with a host is refused with the other problems,
// by name: it may carry user:secret@. Mutation: the check dropped, and the bad
// values start.
func TestATracesEndpointThatIsNotAURLStarts(t *testing.T) {
	const name = "OTEL_EXPORTER_OTLP_TRACES_ENDPOINT"
	for _, v := range []string{"collector:4318", "grpc://user:secret@collector:4317", "http:///v1/traces", "http://:4318/v1/traces", "user:secret@collector"} {
		_, err := load(func(k string) string { return with(prod, name, v, "WIRD_DEV", "2")[k] })
		if err == nil {
			t.Errorf("%q: started", v)
			continue
		}
		if !strings.Contains(err.Error(), name+" is not an http(s) URL with a host") || !strings.Contains(err.Error(), "WIRD_DEV") {
			t.Errorf("%q: refused with %q, want both problems", v, err)
		}
		if strings.Contains(err.Error(), "secret") || strings.Contains(err.Error(), "collector") {
			t.Errorf("%q: the refusal shows the value: %q", v, err)
		}
	}
	for env, want := range map[string]string{
		"":                            "",
		"OTEL_EXPORTER_OTLP_ENDPOINT": "",
		name:                          "https://u:p@otlp.example/v1/traces",
	} {
		got, err := load(func(k string) string { return with(prod, env, "https://u:p@otlp.example/v1/traces")[k] })
		if err != nil || got.Traces != want {
			t.Errorf("with %q set: traces %q, %v; want %q", env, got.Traces, err, want)
		}
	}
}
