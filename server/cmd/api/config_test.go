package main

import (
	"bufio"
	"maps"
	"os"
	"reflect"
	"slices"
	"strings"
	"testing"

	"github.com/MohammadBnei/wird/server/internal/api"
)

// prod is every variable set, each to a value no other holds, so a value read
// into the wrong field shows in the Config compared below.
var prod = map[string]string{
	"DATABASE_URL":              "postgres://u:p@db.example:5432/wird",
	"OIDC_ISSUER":               "https://idp.example/application/o/wird/",
	"OIDC_AUDIENCE":             "client-id-audience",
	"API_ADDR":                  ":9999",
	"WIRD_MODELS_S3_BUCKET":     "bucket-value",
	"WIRD_MODELS_S3_ENDPOINT":   "https://s3.example",
	"WIRD_MODELS_S3_ACCESS_KEY": "access-value",
	"WIRD_MODELS_S3_SECRET":     "secret-value",
	"WIRD_MODELS_S3_REGION":     "region-value",
	"WIRD_APK_KEY":              "android/wird-abc.apk",
	"WIRD_APK_VERSION":          "9.9.9",
	"WIRD_ANDROID_SHA256":       " AA:BB , CC:DD ",
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

// The deployment's values come out where main uses them, untouched: the
// issuer keeps its trailing slash (go-oidc compares it byte for byte), the
// fingerprints stay raw for api.Routes to parse.
func TestAProductionValueLandsInTheWrongField(t *testing.T) {
	got, err := load(func(k string) string { return prod[k] })
	if err != nil {
		t.Fatal(err)
	}
	want := Config{
		DatabaseURL:  "postgres://u:p@db.example:5432/wird",
		OIDCIssuer:   "https://idp.example/application/o/wird/",
		OIDCAudience: "client-id-audience",
		Addr:         ":9999",
		API: api.Config{
			Models: &api.Models{Bucket: "bucket-value", Endpoint: "https://s3.example", AccessKey: "access-value",
				Secret: "secret-value", Region: "region-value"},
			APKKey:        "android/wird-abc.apk",
			APKVersion:    "9.9.9",
			AndroidSHA256: " AA:BB , CC:DD ",
		},
	}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("got %+v (models %+v)\nwant %+v (models %+v)", got, got.API.Models, want, want.API.Models)
	}
}

// WIRD_DEV=1 alone is the local compose stack, with no store; the region is
// left for the store to default, and there is none.
func TestALocalRunNeedsMoreThanWirdDev(t *testing.T) {
	got, err := load(func(k string) string { return map[string]string{"WIRD_DEV": "1"}[k] })
	if err != nil {
		t.Fatal(err)
	}
	want := Config{Dev: true, DatabaseURL: devDatabaseURL, OIDCIssuer: devIssuer, OIDCAudience: devAudience, Addr: ":8080"}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("got %+v, want %+v", got, want)
	}
	// What is set still wins over the dev default.
	got, err = load(func(k string) string { return with(prod, "WIRD_DEV", "1")[k] })
	if err != nil || got.DatabaseURL != prod["DATABASE_URL"] || !got.Dev {
		t.Errorf("dev with a URL set: %+v, %v", got, err)
	}
}

// Each refusal, with every problem in one error, and never a value in it.
func TestAHalfConfiguredDeploymentStarts(t *testing.T) {
	core := map[string]string{"DATABASE_URL": prod["DATABASE_URL"], "OIDC_ISSUER": prod["OIDC_ISSUER"], "OIDC_AUDIENCE": prod["OIDC_AUDIENCE"]}
	s3 := func(names ...string) []string {
		var out []string
		for _, n := range names {
			out = append(out, n+" is unset while another WIRD_MODELS_S3_* is set")
		}
		return out
	}
	for _, c := range []struct {
		name string
		env  map[string]string
		want []string
	}{
		{"nothing", nil, []string{
			"DATABASE_URL is unset (WIRD_DEV=1 uses the local default)",
			"OIDC_ISSUER is unset (WIRD_DEV=1 uses the local default)",
			"OIDC_AUDIENCE is unset (WIRD_DEV=1 uses the local default)",
		}},
		{"no database", with(core, "DATABASE_URL", ""), []string{"DATABASE_URL is unset (WIRD_DEV=1 uses the local default)"}},
		{"WIRD_DEV not 1", with(core, "WIRD_DEV", "true"), []string{"WIRD_DEV must be 1 or unset"}},
		{"bucket alone", with(core, "WIRD_MODELS_S3_BUCKET", "bucket-value"),
			s3("WIRD_MODELS_S3_ENDPOINT", "WIRD_MODELS_S3_ACCESS_KEY", "WIRD_MODELS_S3_SECRET")},
		{"region alone", with(core, "WIRD_MODELS_S3_REGION", "region-value"),
			s3("WIRD_MODELS_S3_BUCKET", "WIRD_MODELS_S3_ENDPOINT", "WIRD_MODELS_S3_ACCESS_KEY", "WIRD_MODELS_S3_SECRET")},
		{"no secret", with(prod, "WIRD_MODELS_S3_SECRET", ""), s3("WIRD_MODELS_S3_SECRET")},
		{"apk key, no store", with(core, "WIRD_APK_KEY", "android/wird-abc.apk"),
			[]string{"WIRD_APK_KEY is set but no WIRD_MODELS_S3_* store is"}},
		{"version, no key", with(prod, "WIRD_APK_KEY", ""), []string{"WIRD_APK_VERSION is set but WIRD_APK_KEY is not"}},
		{"dev still refuses half a store", map[string]string{"WIRD_DEV": "1", "WIRD_MODELS_S3_ACCESS_KEY": "access-value"},
			s3("WIRD_MODELS_S3_BUCKET", "WIRD_MODELS_S3_ENDPOINT", "WIRD_MODELS_S3_SECRET")},
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
// docs/architecture/api.md are one set, so a variable cannot be added in one
// place and forgotten in another.
func TestConfigDocumented(t *testing.T) {
	read := map[string]bool{}
	if _, err := load(func(k string) string { read[k] = true; return prod[k] }); err != nil {
		t.Fatal(err)
	}
	if got := slices.Sorted(maps.Keys(read)); !slices.Equal(got, slices.Sorted(slices.Values(envVars))) {
		t.Errorf("load reads %v, envVars lists %v", got, envVars)
	}
	if got := documented(t, "../../../docs/architecture/api.md"); !slices.Equal(got, envVars) {
		t.Errorf("api.md's table lists %v, envVars %v (same order)", got, envVars)
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
