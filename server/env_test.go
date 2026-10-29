// Package server holds the guards that cover every Go file in the repository:
// server/ and jidhr/, which server requires and replaces with ../jidhr.
package server

import (
	"go/ast"
	"go/parser"
	"go/token"
	"io/fs"
	"os"
	"os/exec"
	"path"
	"path/filepath"
	"slices"
	"strconv"
	"strings"
	"testing"
)

// envReaders are what reads or changes the process's environment: os's,
// syscall's and x/sys/unix's own, and the ones that read a variable on the
// caller's behalf (the home, cache, config and temp directories, PWD, the
// proxy settings). A package listed with no names is refused whole: os/exec
// reads PATH and hands the environment on, os/user reads HOME and USER.
//
// The check is syntactic (go/parser), an interim until ukubi-go's ukubicheck
// analyzer replaces it: every use of a listed name is a selector on its
// import's name, or a dot import, which is refused, so no type checker is
// needed; cgo (import "C") and go:linkname are refused too.
var envReaders = map[string][]string{
	"os": {"Getenv", "LookupEnv", "Environ", "ExpandEnv", "Setenv", "Unsetenv", "Clearenv", "UserHomeDir",
		"UserCacheDir", "UserConfigDir", "TempDir", "MkdirTemp", "CreateTemp", "Getwd", "StartProcess"},
	"syscall":               {"Getenv", "Environ", "Setenv", "Unsetenv", "Clearenv", "ForkExec", "StartProcess", "Exec"},
	"golang.org/x/sys/unix": {"Getenv", "Environ", "Setenv", "Unsetenv", "Clearenv", "Exec"},
	"net/http":              {"ProxyFromEnvironment"},
	"os/exec":               nil,
	"os/user":               nil,
}

// envAllowed is each file allowed to read the environment, and exactly the
// uses it is allowed. A use is "os.Getenv" when the function is passed as a
// value and "os.Getenv()" when it is called.
var envAllowed = map[string][]string{
	// One Config per service binary (docs/adr/0036): each passes os.Getenv to
	// its load and reads nothing itself.
	"server/cmd/api/config.go":      {"os.Getenv"},
	"server/cmd/adminweb/config.go": {"os.Getenv"},
	"jidhr/cmd/rootd/config.go":     {"os.Getenv"},
	// One Config per CLI (docs/adr/0037). etl, ingest and rootcheck read no
	// environment; these three pass os.Getenv to their loadConfig, and
	// rootdraft's also runs `hf auth token` for its token.
	"server/cmd/jidhrcorpus/config.go": {"os.Getenv"},
	"server/cmd/senseseed/config.go":   {"os.Getenv"},
	"server/cmd/rootdraft/config.go":   {"import os/exec", "os.Getenv"},
	// A test helper outside a _test.go file, imported only by tests: the DSN
	// of the Postgres the tests make their throwaway databases in.
	"server/internal/testenv/postgres.go": {"os.Getenv()"},
	// Also test-only: a cmd's main run again as a child process, which
	// inherits the test's environment plus the variables the test sets.
	"server/internal/testenv/main.go": {"import os/exec", "os.Environ()"},
}

// envUses lists the environment readers src uses, called or as a value, under
// whatever name it imports them, sorted; a dot import of their packages counts
// as a use, since it hides them from this check.
func envUses(name string, src []byte) ([]string, error) {
	f, err := parser.ParseFile(token.NewFileSet(), name, src, parser.SkipObjectResolution|parser.ParseComments)
	if err != nil {
		return nil, err
	}
	local := map[string]string{} // the name a file gives each watched import -> its path
	var uses []string
	for _, cg := range f.Comments {
		for _, c := range cg.List {
			if strings.HasPrefix(c.Text, "//go:linkname") {
				uses = append(uses, "go:linkname")
			}
		}
	}
	for _, im := range f.Imports {
		p, _ := strconv.Unquote(im.Path.Value)
		names, ok := envReaders[p]
		if p == "C" || (ok && names == nil) {
			uses = append(uses, "import "+p)
			continue
		}
		if !ok {
			continue
		}
		n := path.Base(p)
		if im.Name != nil {
			n = im.Name.Name
		}
		if n == "." {
			uses = append(uses, "import . "+p)
			continue
		}
		local[n] = p
	}
	called := map[ast.Expr]bool{}
	ast.Inspect(f, func(n ast.Node) bool {
		if c, ok := n.(*ast.CallExpr); ok {
			called[c.Fun] = true
		}
		if s, ok := n.(*ast.SelectorExpr); ok {
			if id, ok := s.X.(*ast.Ident); ok && local[id.Name] != "" && slices.Contains(envReaders[local[id.Name]], s.Sel.Name) {
				use := local[id.Name] + "." + s.Sel.Name
				if called[s] {
					use += "()"
				}
				uses = append(uses, use)
			}
		}
		return true
	})
	slices.Sort(uses)
	return slices.Compact(uses), nil
}

// TestEnvBan: no non-test Go file in server/ or jidhr/ reads the environment
// through the readers above, except the files envAllowed names and only as it
// says. Tests are exempt: they set what they load. The libraries' own reads
// (pgx's PG*, net/http's proxy variables, crypto/x509's SSL_CERT_*) are theirs,
// and the architecture docs name them.
func TestEnvBan(t *testing.T) {
	seen := map[string]bool{} // every directory walked, as a path from the repository root
	allowedSeen := map[string]bool{}
	for _, root := range []string{".", "../jidhr"} {
		err := filepath.WalkDir(root, func(p string, d fs.DirEntry, err error) error {
			if err != nil {
				return err
			}
			rel := repoPath(p)
			if d.IsDir() {
				if p != root && (strings.HasPrefix(d.Name(), ".") || d.Name() == "testdata" || d.Name() == "node_modules") {
					return filepath.SkipDir
				}
				seen[rel] = true
				return nil
			}
			if !strings.HasSuffix(p, ".go") || strings.HasSuffix(p, "_test.go") {
				return nil
			}
			src, err := os.ReadFile(p)
			if err != nil {
				return err
			}
			uses, err := envUses(p, src)
			if err != nil {
				return err
			}
			want, allowed := envAllowed[rel]
			if allowed {
				allowedSeen[rel] = true
			}
			if !slices.Equal(uses, want) {
				t.Errorf("%s reads the environment through %v; allowed: %v", rel, uses, want)
			}
			return nil
		})
		if err != nil {
			t.Fatal(err)
		}
	}
	// The positive control: an allowed file that no longer exists, or no longer
	// reads what it is allowed to, means the check stopped seeing it.
	for rel := range envAllowed {
		if !allowedSeen[rel] {
			t.Errorf("%s is allowed to read the environment and was not walked", rel)
		}
	}
	// Every package either module builds was walked.
	for _, mod := range []string{".", "../jidhr"} {
		cmd := exec.Command("go", "list", "-f", "{{.Dir}}", "./...")
		cmd.Dir = mod
		out, err := cmd.Output()
		if err != nil {
			t.Fatalf("go list in %s: %v", mod, err)
		}
		for _, dir := range strings.Fields(string(out)) {
			if !seen[repoPath(dir)] {
				t.Errorf("package %s was not walked", repoPath(dir))
			}
		}
	}
}

// repoPath is p (relative to server/, or absolute) as a slash path from the
// repository root.
func repoPath(p string) string {
	abs, err := filepath.Abs(p)
	if err != nil {
		return p
	}
	root, _ := filepath.Abs("..")
	rel, err := filepath.Rel(root, abs)
	if err != nil {
		return p
	}
	return filepath.ToSlash(rel)
}

// TestEnvUses: each form the ban sees, and what it leaves alone.
func TestEnvUses(t *testing.T) {
	for _, c := range []struct {
		src  string
		want []string
	}{
		{`import "os"; var _ = os.Getenv("X")`, []string{"os.Getenv()"}},
		{`import "os"; var f = os.Getenv`, []string{"os.Getenv"}},
		{`import "os"; var f = os.LookupEnv`, []string{"os.LookupEnv"}},
		{`import o "os"; func g() { o.Environ() }`, []string{"os.Environ()"}},
		{`import "os"; var _ = os.ExpandEnv("$X")`, []string{"os.ExpandEnv()"}},
		{`import "os"; var _ = os.Setenv("X", "")`, []string{"os.Setenv()"}},
		{`import "os"; var _ = os.Unsetenv("X")`, []string{"os.Unsetenv()"}},
		{`import "os"; func g() { os.Clearenv() }`, []string{"os.Clearenv()"}},
		{`import . "os"; var _ = Getenv("X")`, []string{"import . os"}},
		{`import "os"; var _, _ = os.UserHomeDir()`, []string{"os.UserHomeDir()"}},
		{`import "os"; var _, _ = os.UserCacheDir()`, []string{"os.UserCacheDir()"}},
		{`import "os"; var _, _ = os.UserConfigDir()`, []string{"os.UserConfigDir()"}},
		{`import "os"; var _ = os.TempDir()`, []string{"os.TempDir()"}},
		{`import "os"; var _, _ = os.MkdirTemp("", "x")`, []string{"os.MkdirTemp()"}},
		{`import "os"; var _, _ = os.CreateTemp("", "x")`, []string{"os.CreateTemp()"}},
		{`import "os"; var _, _ = os.Getwd()`, []string{"os.Getwd()"}},
		{`import "os"; var _ = os.StartProcess`, []string{"os.StartProcess"}},
		{`import "syscall"; var _, _ = syscall.Getenv("X")`, []string{"syscall.Getenv()"}},
		{`import "syscall"; var _ = syscall.Environ`, []string{"syscall.Environ"}},
		{`import "syscall"; var _ = syscall.Setenv`, []string{"syscall.Setenv"}},
		{`import "syscall"; var _ = syscall.Unsetenv`, []string{"syscall.Unsetenv"}},
		{`import "syscall"; var _ = syscall.Clearenv`, []string{"syscall.Clearenv"}},
		{`import "syscall"; var _ = syscall.ForkExec`, []string{"syscall.ForkExec"}},
		{`import "syscall"; var _ = syscall.Exec`, []string{"syscall.Exec"}},
		{`import "syscall"; var _ = syscall.StartProcess`, []string{"syscall.StartProcess"}},
		{`import "golang.org/x/sys/unix"; var _, _ = unix.Getenv("X")`, []string{"golang.org/x/sys/unix.Getenv()"}},
		{`import u "golang.org/x/sys/unix"; var _ = u.Environ`, []string{"golang.org/x/sys/unix.Environ"}},
		{`import "golang.org/x/sys/unix"; var _ = unix.Setenv`, []string{"golang.org/x/sys/unix.Setenv"}},
		{`import "golang.org/x/sys/unix"; var _ = unix.Unsetenv`, []string{"golang.org/x/sys/unix.Unsetenv"}},
		{`import "golang.org/x/sys/unix"; func g() { unix.Clearenv() }`, []string{"golang.org/x/sys/unix.Clearenv()"}},
		{`import "golang.org/x/sys/unix"; var _ = unix.Exec`, []string{"golang.org/x/sys/unix.Exec"}},
		{`import "net/http"; var _ = http.ProxyFromEnvironment`, []string{"net/http.ProxyFromEnvironment"}},
		{`import h "net/http"; var _ = h.ProxyFromEnvironment`, []string{"net/http.ProxyFromEnvironment"}},
		{`import "os/exec"; var _ = exec.Command`, []string{"import os/exec"}},
		{`import x "os/exec"`, []string{"import os/exec"}},
		{`import u "os/user"; var _, _ = u.Current()`, []string{"import os/user"}},
		{`import "C"`, []string{"import C"}},
		{"import _ \"unsafe\"\n//go:linkname getenv syscall.Getenv\nfunc getenv(string) (string, bool)", []string{"go:linkname"}},
		{`import "os"; var _ = os.Args; var _ = os.Stderr; var _ = os.Getpid()`, nil},
		{`import "net/http"; var _ = http.StatusOK`, nil},
		{`type t struct{ Getenv func(string) string }; var os t; var _ = os.Getenv`, nil}, // no import: not os
	} {
		got, err := envUses("x.go", []byte("package x\n"+c.src))
		if err != nil {
			t.Fatalf("%s: %v", c.src, err)
		}
		if !slices.Equal(got, c.want) {
			t.Errorf("%s: %v, want %v", c.src, got, c.want)
		}
	}
}

// jidhr's CI tests rootd against jidhr's own ukubi-go pin (GOWORK=off), while
// the image builds rootd through go.work, where the higher of the two pins
// wins: two pins that differ ship a rootd nobody tested (docs/adr/0040).
func TestJidhrShipsTheUkubiGoItWasTestedWith(t *testing.T) {
	pin := func(gomod string) string {
		b, err := os.ReadFile(gomod)
		if err != nil {
			t.Fatal(err)
		}
		for line := range strings.Lines(string(b)) {
			if f := strings.Fields(line); len(f) == 2 && f[0] == "github.com/MohammadBnei/ukubi-go" {
				return f[1]
			}
		}
		t.Fatalf("%s requires no ukubi-go", gomod)
		return ""
	}
	if s, j := pin("go.mod"), pin("../jidhr/go.mod"); s != j {
		t.Errorf("ukubi-go: server pins %s, jidhr %s; bump both together", s, j)
	}
}
