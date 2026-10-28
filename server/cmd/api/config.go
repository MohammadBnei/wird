package main

import (
	"errors"
	"fmt"
	"os"

	"github.com/MohammadBnei/wird/server/internal/api"
)

// envVars is every variable load reads. TestConfigDocumented holds it, the
// reads load makes, and the table in docs/architecture/api.md to the same set.
var envVars = []string{
	"WIRD_DEV",
	"DATABASE_URL",
	"OIDC_ISSUER",
	"OIDC_AUDIENCE",
	"API_ADDR",
	"WIRD_MODELS_S3_BUCKET",
	"WIRD_MODELS_S3_ENDPOINT",
	"WIRD_MODELS_S3_ACCESS_KEY",
	"WIRD_MODELS_S3_SECRET",
	"WIRD_MODELS_S3_REGION",
	"WIRD_APK_KEY",
	"WIRD_APK_VERSION",
	"WIRD_ANDROID_SHA256",
}

// Config is the whole of wird-api's configuration, read once at start.
type Config struct {
	// Dev is WIRD_DEV=1: the local compose Postgres and OIDC stub stand in for
	// whatever is unset. Nothing else changes with it.
	Dev          bool
	DatabaseURL  string
	OIDCIssuer   string
	OIDCAudience string
	Addr         string
	API          api.Config
}

// The local defaults WIRD_DEV=1 fills in: docker-compose.yml's Postgres and
// OIDC stub, and the audience the stub signs for.
const (
	devDatabaseURL = "postgres://wird:wird@localhost:5432/wird"
	devIssuer      = "http://localhost:8082/wird"
	devAudience    = "wird"
)

// load builds the Config from getenv, or refuses it with every problem at
// once. A refusal names variables, never their values.
func load(getenv func(string) string) (Config, error) {
	var errs []error
	c := Config{Addr: getenv("API_ADDR")}
	switch getenv("WIRD_DEV") {
	case "":
	case "1":
		c.Dev = true
	default:
		errs = append(errs, errors.New("WIRD_DEV must be 1 or unset"))
	}
	if c.Addr == "" {
		c.Addr = ":8080"
	}

	// Without WIRD_DEV a missing one is a refusal: the silent localhost default
	// this replaced let a deployment whose Secret had not landed start against
	// nothing, and say so only later and less plainly.
	required := func(name, dev string) string {
		v := getenv(name)
		switch {
		case v != "":
			return v
		case c.Dev:
			return dev
		}
		errs = append(errs, fmt.Errorf("%s is unset (WIRD_DEV=1 uses the local default)", name))
		return ""
	}
	c.DatabaseURL = required("DATABASE_URL", devDatabaseURL)
	// Passed through as written: go-oidc compares it byte for byte with the
	// issuer the discovery document names, trailing slash and all.
	c.OIDCIssuer = required("OIDC_ISSUER", devIssuer)
	c.OIDCAudience = required("OIDC_AUDIENCE", devAudience)

	// The store is optional and its four parts come together. Any of them set
	// means a store was meant, so a missing one is a refusal rather than a
	// store silently switched off and a Download button that answers 503.
	models := api.Models{
		Bucket:    getenv("WIRD_MODELS_S3_BUCKET"),
		Endpoint:  getenv("WIRD_MODELS_S3_ENDPOINT"),
		AccessKey: getenv("WIRD_MODELS_S3_ACCESS_KEY"),
		Secret:    getenv("WIRD_MODELS_S3_SECRET"),
		Region:    getenv("WIRD_MODELS_S3_REGION"),
	}
	if models != (api.Models{}) {
		for _, part := range [][2]string{
			{"WIRD_MODELS_S3_BUCKET", models.Bucket},
			{"WIRD_MODELS_S3_ENDPOINT", models.Endpoint},
			{"WIRD_MODELS_S3_ACCESS_KEY", models.AccessKey},
			{"WIRD_MODELS_S3_SECRET", models.Secret},
		} {
			if part[1] == "" {
				errs = append(errs, fmt.Errorf("%s is unset while another WIRD_MODELS_S3_* is set", part[0]))
			}
		}
		c.API.Models = &models
	}

	c.API.APKKey = getenv("WIRD_APK_KEY")
	c.API.APKVersion = getenv("WIRD_APK_VERSION")
	if c.API.APKKey != "" && models == (api.Models{}) {
		errs = append(errs, errors.New("WIRD_APK_KEY is set but no WIRD_MODELS_S3_* store is"))
	}
	// apk.yml writes the two together. A version alone is the page printing a
	// release beside a button that answers 503.
	if c.API.APKVersion != "" && c.API.APKKey == "" {
		errs = append(errs, errors.New("WIRD_APK_VERSION is set but WIRD_APK_KEY is not"))
	}
	c.API.AndroidSHA256 = getenv("WIRD_ANDROID_SHA256")

	if err := errors.Join(errs...); err != nil {
		return Config{}, err
	}
	return c, nil
}

// fromProcess is the one place wird-api reads its real environment.
func fromProcess() (Config, error) {
	return load(os.Getenv)
}
