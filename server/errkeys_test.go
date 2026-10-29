package server

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// A key made anywhere but internal/keys/keys.go is a key no client was told
// about (docs/adr/0038). ukubi-go's errkeys analyzer type-checks every
// non-test file of the module for it, and fails when keys.go declares no key,
// so a registry that moved or emptied cannot pass by checking nothing. The
// other analyzers are off: env has env_test.go, and package state has
// state_test.go.
//
// Run with the shared GOCACHE: errkeys reads only files the build compiles,
// which vet's cache keys on. A fresh cache is needed only once envban is on.
func TestErrorKeysComeOnlyFromTheRegistry(t *testing.T) {
	root, err := filepath.Abs(".") // the server module, whatever the caller's directory
	if err != nil {
		t.Fatal(err)
	}
	run := func(args ...string) string {
		t.Helper()
		cmd := exec.Command("go", args...)
		cmd.Dir = root
		cmd.Env = append(os.Environ(), "GOWORK=off")
		out, err := cmd.CombinedOutput()
		if err != nil {
			t.Fatalf("go %v: %v\n%s", args, err, out)
		}
		return string(out)
	}
	// go.mod's tool directive: built once into the build cache, not per run.
	tool := strings.TrimSpace(run("tool", "-n", "ukubicheck"))
	run("vet", "-vettool="+tool, "-envban=false", "-pkgstate=false", "-loglevel=false",
		"-errkeys.registry=internal/keys/keys.go", "./...")
}
