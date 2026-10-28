package main

import (
	"bufio"
	"maps"
	"os"
	"slices"
	"strings"
	"testing"
)

var prod = map[string]string{
	"ROOTD_ADDR":    ":9997",
	"ROOTD_CORPUS":  "/data/corpus.json",
	"ROOTD_API_KEY": "key-value",
	"ROOTD_RATE":    "2.5",
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

func TestAProductionValueLandsInTheWrongField(t *testing.T) {
	got, err := load(func(k string) string { return prod[k] })
	if err != nil {
		t.Fatal(err)
	}
	if want := (Config{Addr: ":9997", Corpus: "/data/corpus.json", APIKey: "key-value", Rate: 2.5}); got != want {
		t.Errorf("got %+v, want %+v", got, want)
	}
	// The defaults, and 0 still turning throttling off.
	for raw, want := range map[string]float64{"": 5, "0": 0, "0.25": 0.25} {
		got, err := load(func(k string) string {
			return with(map[string]string{"ROOTD_API_KEY": "key-value"}, "ROOTD_RATE", raw)[k]
		})
		if err != nil || got.Rate != want || got.Addr != ":8081" || got.Corpus != "jidhr/testdata/quran.json" {
			t.Errorf("ROOTD_RATE=%q: %+v, %v", raw, got, err)
		}
	}
}

// ROOTD_DEV=1 is what serves /v1 without a key.
func TestAKeylessListenerIsServedByAccident(t *testing.T) {
	got, err := load(func(k string) string { return map[string]string{"ROOTD_DEV": "1"}[k] })
	if err != nil {
		t.Fatal(err)
	}
	if want := (Config{Dev: true, Addr: ":8081", Corpus: "jidhr/testdata/quran.json", Rate: 5}); got != want {
		t.Errorf("got %+v, want %+v", got, want)
	}
}

// Each refusal, with every problem in one error, and never a value in it.
func TestAHalfConfiguredDeploymentStarts(t *testing.T) {
	const badRate = "ROOTD_RATE must be 0 (off) or a finite rate of at least 0.25 a second"
	for _, c := range []struct {
		name string
		env  map[string]string
		want []string
	}{
		{"nothing", nil, []string{"ROOTD_API_KEY is unset (ROOTD_DEV=1 serves /v1 without a key)"}},
		{"ROOTD_DEV not 1", with(prod, "ROOTD_DEV", "true"), []string{"ROOTD_DEV must be 1 or unset"}},
		{"rate not a number", with(prod, "ROOTD_RATE", "fast"), []string{"ROOTD_RATE is not a number"}},
		{"negative rate", with(prod, "ROOTD_RATE", "-1"), []string{badRate}},
		{"NaN", with(prod, "ROOTD_RATE", "NaN"), []string{badRate}},
		{"Inf", with(prod, "ROOTD_RATE", "Inf"), []string{badRate}},
		{"-Inf", with(prod, "ROOTD_RATE", "-infinity"), []string{badRate}},
		{"a burst under one", with(prod, "ROOTD_RATE", "0.1"), []string{badRate}},
		{"a burst past MaxFloat64", with(prod, "ROOTD_RATE", "1e308"), []string{badRate}},
		{"both at once", map[string]string{"ROOTD_RATE": "fast"}, []string{
			"ROOTD_API_KEY is unset (ROOTD_DEV=1 serves /v1 without a key)", "ROOTD_RATE is not a number"}},
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

// TestConfigDocumented: what load reads, envVars, and README.md's variable
// table are one set.
func TestConfigDocumented(t *testing.T) {
	read := map[string]bool{}
	if _, err := load(func(k string) string { read[k] = true; return prod[k] }); err != nil {
		t.Fatal(err)
	}
	if got := slices.Sorted(maps.Keys(read)); !slices.Equal(got, slices.Sorted(slices.Values(envVars))) {
		t.Errorf("load reads %v, envVars lists %v", got, envVars)
	}
	if got := documented(t, "README.md"); !slices.Equal(got, envVars) {
		t.Errorf("README.md's table lists %v, envVars %v (same order)", got, envVars)
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
