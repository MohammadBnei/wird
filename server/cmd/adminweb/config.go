package main

import (
	"errors"
	"fmt"
	"net/url"
	"os"
)

// envVars is every variable load reads. TestConfigDocumented holds it, the
// reads load makes, and the table in docs/architecture/adminweb.md to the same
// set.
var envVars = []string{
	"WIRD_DEV",
	"DATABASE_URL",
	"OIDC_ISSUER",
	"OIDC_CLIENT_ID",
	"OIDC_CLIENT_SECRET",
	"OIDC_AUDIENCE",
	"NOCTURNE_CSS",
	"ADMIN_ADDR",
	"OTEL_EXPORTER_OTLP_TRACES_ENDPOINT",
}

// Config is the whole of wird-adminweb's configuration, read once at start.
type Config struct {
	// Dev is WIRD_DEV=1: the local compose Postgres and OIDC stub stand in for
	// whatever is unset. Nothing else changes with it.
	Dev         bool
	DatabaseURL string
	OIDCIssuer  string
	// Audience is OIDC_CLIENT_ID when set, else OIDC_AUDIENCE.
	Audience string
	// ClientSecret set means tokens are HS256 under it (authentik's proxy
	// provider); empty means the issuer's published keys (the local stub).
	ClientSecret string
	CSSPath      string
	Addr         string
	// Traces is the OTLP/HTTP traces URL, /v1/traces included; empty means
	// no tracing at all (docs/adr/0040).
	Traces string
}

// The local defaults WIRD_DEV=1 fills in: docker-compose.yml's Postgres and
// OIDC stub, and the audience the stub signs for.
const (
	devDatabaseURL = "postgres://wird:wird@localhost:5432/wird"
	devIssuer      = "http://localhost:8082/wird"
	devAudience    = "wird-admin"
)

// load builds the Config from getenv, or refuses it with every problem at
// once. A refusal names variables, never their values.
func load(getenv func(string) string) (Config, error) {
	var errs []error
	c := Config{
		CSSPath: getenv("NOCTURNE_CSS"),
		Addr:    getenv("ADMIN_ADDR"),
	}
	switch getenv("WIRD_DEV") {
	case "":
	case "1":
		c.Dev = true
	default:
		errs = append(errs, errors.New("WIRD_DEV must be 1 or unset"))
	}
	if c.CSSPath == "" {
		c.CSSPath = "docs/design/nocturne-styles.css"
	}
	if c.Addr == "" {
		c.Addr = ":8081"
	}

	required := func(name, v, dev string) string {
		switch {
		case v != "":
			return v
		case c.Dev:
			return dev
		}
		errs = append(errs, fmt.Errorf("%s is unset (WIRD_DEV=1 uses the local default)", name))
		return ""
	}
	c.DatabaseURL = required("DATABASE_URL", getenv("DATABASE_URL"), devDatabaseURL)
	// Passed through as written: the verifier compares it byte for byte with
	// the token's iss, trailing slash and all.
	c.OIDCIssuer = required("OIDC_ISSUER", getenv("OIDC_ISSUER"), devIssuer)

	// OIDC_CLIENT_ID is the proxy provider's id as authentik generated it,
	// delivered beside its secret: a proxy provider's id cannot be declared, so
	// it is read from the deployment rather than committed. OIDC_AUDIENCE is
	// the local stub's. The id and the secret are one sign-in, so one without
	// the other is a refusal, WIRD_DEV or not: a secret alone verified against
	// an audience nobody issues for, and an id alone checked keys the proxy
	// never signs with.
	id, secret, audience := getenv("OIDC_CLIENT_ID"), getenv("OIDC_CLIENT_SECRET"), getenv("OIDC_AUDIENCE")
	switch {
	case id != "" && secret == "":
		errs = append(errs, errors.New("OIDC_CLIENT_ID is set but OIDC_CLIENT_SECRET is not"))
	case id == "" && secret != "":
		errs = append(errs, errors.New("OIDC_CLIENT_SECRET is set but OIDC_CLIENT_ID is not"))
	}
	c.ClientSecret = secret
	if id != "" {
		c.Audience = id
	} else {
		c.Audience = required("OIDC_CLIENT_ID or OIDC_AUDIENCE", audience, devAudience)
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
	return err == nil && (u.Scheme == "http" || u.Scheme == "https") && u.Hostname() != ""
}

// fromProcess is the one place wird-adminweb reads its real environment.
func fromProcess() (Config, error) {
	return load(os.Getenv)
}
