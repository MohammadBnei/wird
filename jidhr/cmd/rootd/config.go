package main

import (
	"errors"
	"math"
	"net/url"
	"os"
	"strconv"
)

// envVars is every variable load reads. TestConfigDocumented holds it, the
// reads load makes, and the table in README.md to the same set.
var envVars = []string{
	"ROOTD_DEV",
	"ROOTD_ADDR",
	"ROOTD_CORPUS",
	"ROOTD_API_KEY",
	"ROOTD_RATE",
	"OTEL_EXPORTER_OTLP_TRACES_ENDPOINT",
}

// Config is the whole of rootd's configuration, read once at start.
type Config struct {
	// Dev is ROOTD_DEV=1, which allows /v1 without ROOTD_API_KEY: a listener
	// on a laptop, never a deployed one.
	Dev    bool
	Addr   string
	Corpus string
	// APIKey empty means /v1 asks for no key, which only Dev allows.
	APIKey string
	// Rate is requests a second per caller; 0 turns throttling off.
	Rate float64
	// Traces is the OTLP/HTTP traces URL, /v1/traces included; empty means
	// no tracing at all (docs/adr/0040).
	Traces string
}

// load builds the Config from getenv, or refuses it with every problem at
// once. A refusal names variables, never their values.
func load(getenv func(string) string) (Config, error) {
	var errs []error
	c := Config{
		Addr:   getenv("ROOTD_ADDR"),
		Corpus: getenv("ROOTD_CORPUS"),
		APIKey: getenv("ROOTD_API_KEY"),
		Rate:   5,
	}
	switch getenv("ROOTD_DEV") {
	case "":
	case "1":
		c.Dev = true
	default:
		errs = append(errs, errors.New("ROOTD_DEV must be 1 or unset"))
	}
	if c.Addr == "" {
		c.Addr = ":8081"
	}
	if c.Corpus == "" {
		c.Corpus = "jidhr/testdata/quran.json"
	}
	// An unauthenticated /v1 used to be what an unset key meant, logged only as
	// authenticated=false. It is now asked for by name.
	if c.APIKey == "" && !c.Dev {
		errs = append(errs, errors.New("ROOTD_API_KEY is unset (ROOTD_DEV=1 serves /v1 without a key)"))
	}
	if raw := getenv("ROOTD_RATE"); raw != "" {
		// The parse error is not wrapped: it quotes the value.
		v, err := strconv.ParseFloat(raw, 64)
		switch {
		case err != nil:
			errs = append(errs, errors.New("ROOTD_RATE is not a number"))
		// Negative and NaN used to turn the limiter off, and +Inf let every
		// request through; a burst under one token (which takes in every
		// negative) answered 429 forever. The burst is checked rather than v: a
		// finite rate past MaxFloat64/burstPerRate is an infinite burst.
		case v != 0 && (math.IsNaN(v) || math.IsInf(v*burstPerRate, 0) || v*burstPerRate < 1):
			errs = append(errs, errors.New("ROOTD_RATE must be 0 (off) or a finite rate of at least 0.25 a second"))
		default:
			c.Rate = v
		}
	}

	c.Traces = getenv("OTEL_EXPORTER_OTLP_TRACES_ENDPOINT")
	if c.Traces != "" && !httpURL(c.Traces) {
		errs = append(errs, errors.New("OTEL_EXPORTER_OTLP_TRACES_ENDPOINT is not an http(s) URL with a host"))
	}

	if err := errors.Join(errs...); err != nil {
		return Config{}, err
	}
	return c, nil
}

// httpURL is telemetry.New's own check, made here so a bad value is refused
// with the others and its value (which may carry user:secret@) never printed.
func httpURL(v string) bool {
	u, err := url.Parse(v)
	return err == nil && (u.Scheme == "http" || u.Scheme == "https") && u.Host != ""
}

// fromProcess is the one place rootd reads its real environment.
func fromProcess() (Config, error) {
	return load(os.Getenv)
}
