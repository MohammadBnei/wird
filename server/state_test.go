package server

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// No mutable package-level state (standard §4, §11; the game's
// TestPackageState is the model): main builds every dependency and passes it
// in, and a test never swaps a global. ukubi-go's pkgstate analyzer
// type-checks every non-test file of server and of jidhr for a package var
// that is not _, an embed, a regexp or an error, or a //ukubicheck:table; for
// func init(); for a write into a package var; and for a table used as more
// than a read. The control first: the same tool on a fixture holding one
// package var must fail, so a vet that checked nothing cannot pass.
//
// Run with -count=1 (CI does): this package's test binary does not depend on
// the packages it vets, so a cached pass survives an edit to them.
func TestPackageState(t *testing.T) {
	root, err := filepath.Abs(".") // the server module, whatever the caller's directory
	if err != nil {
		t.Fatal(err)
	}
	vet := func(dir string, args ...string) (string, error) {
		cmd := exec.Command("go", args...)
		cmd.Dir = dir
		cmd.Env = append(os.Environ(), "GOWORK=off")
		out, err := cmd.CombinedOutput()
		return string(out), err
	}
	// go.mod's tool directive: built once into the build cache, not per run.
	out, err := vet(root, "tool", "-n", "ukubicheck")
	if err != nil {
		t.Fatalf("go tool -n ukubicheck: %v\n%s", err, out)
	}
	tool := "-vettool=" + strings.TrimSpace(out)

	if out, err := vet(filepath.Join(root, "testdata", "pkgstate"), "vet", tool, "-pkgstate", "./..."); err == nil ||
		!strings.Contains(out, "hits is package-level state") {
		t.Fatalf("pkgstate passed a package var, so it checks nothing (err %v):\n%s", err, out)
	}
	// The server's ukubicheck is jidhr's too: TestJidhrShipsTheUkubiGoItWasTestedWith holds the two pins equal.
	for _, dir := range []string{root, filepath.Join(root, "..", "jidhr")} {
		if out, err := vet(dir, "vet", tool, "-pkgstate", "./..."); err != nil {
			t.Errorf("%s: %v\n%s", dir, err, out)
		}
	}
}
