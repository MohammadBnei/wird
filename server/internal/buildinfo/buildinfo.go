// Package buildinfo is the release this binary was built as.
//
// The version is an embedded file, not a `-ldflags -X` var: pkgstate
// (state_test.go) refuses a settable package var, and an embed is the one
// package-level string it allows. The Dockerfile overwrites version.txt with
// the VERSION build-arg before `go build`; the committed file says "dev", so a
// local build never claims a release it is not (ADR 0041).
package buildinfo

import (
	_ "embed"
	"strings"
)

//go:embed version.txt
var version string

// Version is the release, X.Y.Z (or X.Y.Z+<sha> between releases), or "dev".
func Version() string { return strings.TrimSpace(version) }
