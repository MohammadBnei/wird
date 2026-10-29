package server

import (
	"go/ast"
	"go/constant"
	"go/importer"
	"go/parser"
	"go/token"
	"go/types"
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"strconv"
	"strings"
	"sync"
	"testing"

	"golang.org/x/tools/go/packages"
)

// Logs are an interface (standard §7, docs/adr/0039): Loki's
// log-error-rate-spike counts ERROR lines per pod, so where a line is ERROR,
// and in what words, is pinned here. The guards type-check every package of
// server and jidhr (go/packages), so an import alias, a method value or a
// helper that takes the words as a parameter is seen for what it is.

// unit is one type-checked package, or one snippet in a forms table.
type unit struct {
	rel   string // the package's directory from the repository root
	name  string
	fset  *token.FileSet
	files []*ast.File
	info  *types.Info
}

// cliTools are the hand-run tools: never deployed, they log on stderr because
// stdout is their report, and their ERROR lines reach no alert.
var cliTools = []string{"server/cmd/etl", "server/cmd/ingest", "server/cmd/jidhrcorpus",
	"server/cmd/rootcheck", "server/cmd/rootdraft", "server/cmd/senseseed"}

// loadRepo type-checks every non-test package of both modules, once per run,
// and fails on a package with errors or one go list has that it did not load.
var loadRepo = sync.OnceValues(func() ([]unit, error) {
	cfg := &packages.Config{
		Mode: packages.NeedName | packages.NeedFiles | packages.NeedSyntax | packages.NeedTypes | packages.NeedTypesInfo,
		Env:  append(os.Environ(), "GOWORK=off"),
	}
	pkgs, err := packages.Load(cfg, "./...", "github.com/MohammadBnei/wird/jidhr/...")
	if err != nil {
		return nil, err
	}
	var units []unit
	for _, p := range pkgs {
		if len(p.Errors) > 0 {
			return nil, p.Errors[0]
		}
		units = append(units, unit{repoPath(p.Dir), p.Name, p.Fset, p.Syntax, p.TypesInfo})
	}
	return units, nil
})

func repo(t *testing.T) []unit {
	t.Helper()
	units, err := loadRepo()
	if err != nil {
		t.Fatal(err)
	}
	seen := map[string]bool{}
	for _, u := range units {
		seen[u.rel] = true
	}
	for _, mod := range []string{".", "../jidhr"} {
		cmd := exec.Command("go", "list", "-f", "{{.Dir}}", "./...")
		cmd.Dir = mod
		cmd.Env = append(os.Environ(), "GOWORK=off")
		out, err := cmd.Output()
		if err != nil {
			t.Fatalf("go list in %s: %v", mod, err)
		}
		for _, dir := range strings.Fields(string(out)) {
			if !seen[repoPath(dir)] {
				t.Errorf("package %s was not type-checked", repoPath(dir))
			}
		}
	}
	return units
}

// slogObj is the log/slog function or constant id names, or "".
func slogObj(u unit, id *ast.Ident) string {
	obj := u.info.Uses[id]
	if obj == nil || obj.Pkg() == nil || obj.Pkg().Path() != "log/slog" {
		return ""
	}
	switch obj.(type) {
	case *types.Func, *types.Const:
		return obj.Name()
	}
	return ""
}

// calleeID is the identifier a call calls by name, or nil.
func calleeID(c *ast.CallExpr) *ast.Ident {
	switch f := ast.Unparen(c.Fun).(type) {
	case *ast.Ident:
		return f
	case *ast.SelectorExpr:
		return f.Sel
	case *ast.IndexExpr:
		if s, ok := f.X.(*ast.SelectorExpr); ok {
			return s.Sel
		}
		if id, ok := f.X.(*ast.Ident); ok {
			return id
		}
	}
	return nil
}

// errorSites lists every place in units that logs at ERROR, as
// "dir/file: func: words", sorted. A site is a call of slog's Error or
// ErrorContext (package function or method, called or taken as a value), a
// Log or LogAttrs whose level is not a constant below ERROR, a use of
// slog.LevelError (a library logger at ERROR), or a call of a helper: a
// function that passes one of its parameters as the words of such a site
// (fail(w, r, "sync", err)), with the words its caller gave.
func errorSites(units []unit) []string {
	helpers := map[string]int{} // func's full name -> index of its words parameter
	var sites []string
	for pass := 0; ; pass++ {
		before := len(helpers)
		sites = sites[:0]
		for _, u := range units {
			for _, f := range u.files {
				file := filepath.Base(u.fset.Position(f.Pos()).Filename)
				for _, d := range f.Decls {
					fd, ok := d.(*ast.FuncDecl)
					if !ok || fd.Body == nil {
						continue
					}
					fn, _ := u.info.Defs[fd.Name].(*types.Func)
					params := fn.Signature().Params()
					// words names the site's message: its text, the parameter it
					// comes from (marking fd a helper), or "?".
					words := func(arg ast.Expr) string {
						if tv, ok := u.info.Types[arg]; ok && tv.Value != nil && tv.Value.Kind() == constant.String {
							return strconv.Quote(constant.StringVal(tv.Value))
						}
						if id, ok := ast.Unparen(arg).(*ast.Ident); ok {
							for i := range params.Len() {
								if params.At(i) == u.info.Uses[id] {
									helpers[fn.FullName()] = i
									return id.Name
								}
							}
						}
						return "?"
					}
					add := func(w string) { sites = append(sites, u.rel+"/"+file+": "+fd.Name.Name+": "+w) }
					handled := map[*ast.Ident]bool{}
					ast.Inspect(fd.Body, func(n ast.Node) bool {
						switch n := n.(type) {
						case *ast.CallExpr:
							id := calleeID(n)
							if id == nil {
								return true
							}
							if callee, ok := u.info.Uses[id].(*types.Func); ok {
								if i, ok := helpers[callee.Origin().FullName()]; ok && i < len(n.Args) {
									add(id.Name + "(" + words(n.Args[i]) + ")")
									return true
								}
							}
							switch name := slogObj(u, id); name {
							case "Error":
								handled[id] = true
								if len(n.Args) > 0 {
									add(words(n.Args[0]))
								}
							case "ErrorContext":
								handled[id] = true
								if len(n.Args) > 1 {
									add(words(n.Args[1]))
								}
							case "Log", "LogAttrs":
								if len(n.Args) < 3 {
									return true
								}
								ast.Inspect(n.Args[1], func(m ast.Node) bool {
									if id, ok := m.(*ast.Ident); ok {
										handled[id] = true
									}
									return true
								})
								tv := u.info.Types[n.Args[1]]
								if v, ok := constant.Int64Val(constant.ToInt(tv.Value)); tv.Value != nil && ok && v < 8 {
									return true // a constant level below slog.LevelError
								}
								add(words(n.Args[2]))
							}
						case *ast.Ident:
							if handled[n] {
								return true
							}
							switch slogObj(u, n) {
							case "Error", "ErrorContext":
								add("?") // taken as a value: every call of it is a site
							case "LevelError":
								add("LevelError")
							}
						}
						return true
					})
				}
			}
		}
		if len(helpers) == before && pass > 0 {
			break
		}
	}
	slices.Sort(sites)
	return sites
}

// TestErrorSites: a line moving to ERROR or away from it changes what pages,
// so it changes this list in the same PR. The CLIs are left out (cliTools).
func TestErrorSites(t *testing.T) {
	var services []unit
	for _, u := range repo(t) {
		if !slices.Contains(cliTools, u.rel) {
			services = append(services, u)
		}
	}
	got := errorSites(services)
	want := []string{
		`jidhr/cmd/rootd/main.go: main: "config refused"`,
		`jidhr/cmd/rootd/main.go: main: "listen"`,
		`jidhr/cmd/rootd/main.go: main: "load the corpus"`,
		`jidhr/cmd/rootd/main.go: main: "open the corpus"`,
		`jidhr/cmd/rootd/main.go: main: "rootd shutdown failed"`,
		`jidhr/cmd/rootd/main.go: main: "rootd stopped"`,
		`jidhr/cmd/rootd/main.go: main: "tracing unavailable"`,
		`jidhr/cmd/rootd/main.go: main: LevelError`, // http.Server.ErrorLog
		`jidhr/cmd/rootd/server.go: lookupRoot: writeInternal("look up a root")`,
		`jidhr/cmd/rootd/server.go: lookupRoot: writeInternal("read the meanings of a root")`,
		`jidhr/cmd/rootd/server.go: writeInternal: LevelError`,
		`jidhr/cmd/rootd/server.go: writeInternal: what`,
		`jidhr/cmd/rootd/server.go: writeResolveError: writeInternal("resolve a word")`,
		`server/cmd/adminweb/main.go: dashboard: "page not written"`,
		`server/cmd/adminweb/main.go: dashboard: Failed("corpus version")`,
		`server/cmd/adminweb/main.go: dashboard: Failed("health")`,
		`server/cmd/adminweb/main.go: dashboard: Failed("reports")`,
		`server/cmd/adminweb/main.go: dashboard: Failed("verdicts")`,
		`server/cmd/adminweb/main.go: reportsJSON: Failed("reports")`,
		`server/cmd/adminweb/main.go: run: "config refused"`,
		`server/cmd/adminweb/main.go: run: "database unavailable"`,
		`server/cmd/adminweb/main.go: run: "issuer unavailable"`,
		`server/cmd/adminweb/main.go: run: "stylesheet unavailable"`,
		`server/cmd/adminweb/main.go: run: "tracing unavailable"`,
		`server/cmd/adminweb/main.go: run: "wird-adminweb shutdown failed"`,
		`server/cmd/adminweb/main.go: run: "wird-adminweb stopped"`,
		`server/cmd/adminweb/main.go: run: "wird-adminweb stopped"`,
		`server/cmd/adminweb/main.go: triage: Failed("triage")`,
		`server/cmd/adminweb/main.go: verdictsJSON: Failed("verdicts")`,
		`server/cmd/api/main.go: maintain: "op log prune"`,
		`server/cmd/api/main.go: run: "config refused"`,
		`server/cmd/api/main.go: run: "database unavailable"`,
		`server/cmd/api/main.go: run: "issuer unavailable"`,
		`server/cmd/api/main.go: run: "tracing unavailable"`,
		`server/cmd/api/main.go: run: "wird-api shutdown failed"`,
		`server/cmd/api/main.go: run: "wird-api stopped"`,
		`server/cmd/api/main.go: run: "wird-api stopped"`,
		`server/cmd/api/main.go: sweep: "report sweep"`,
		`server/internal/api/api.go: corpusVersion: fail("corpus version")`,
		`server/internal/api/api.go: deleteMe: fail("delete reader")`,
		`server/internal/api/api.go: fail: Failed(what)`,
		`server/internal/api/api.go: irab: fail("irab")`,
		`server/internal/api/api.go: kept: fail("kept")`,
		`server/internal/api/api.go: lexicon: fail("lexicon")`,
		`server/internal/api/api.go: progress: fail("progress")`,
		`server/internal/api/api.go: tafsir: fail("tafsir")`,
		`server/internal/api/apk.go: apk: "presign the apk"`,
		`server/internal/api/models.go: serve: "presign a model"`,
		`server/internal/api/senses.go: senses: unavailable("senses version")`,
		`server/internal/api/senses.go: senses: unavailable("senses")`,
		`server/internal/api/senses.go: unavailable: Failed(what)`,
		`server/internal/api/sync.go: changes: fail("changes")`,
		`server/internal/api/sync.go: sync: fail("sync")`,
		`server/internal/auth/auth.go: Middleware: Failed("reader lookup")`,
		`server/internal/httpx/serve.go: Failed: LevelError`,
		`server/internal/httpx/serve.go: Failed: msg`,
		`server/internal/httpx/serve.go: Serve: LevelError`, // http.Server.ErrorLog
		`server/internal/store/sync.go: classify: "op not applied"`,
		`server/internal/store/sync.go: failedLevel: LevelError`,
	}
	if strings.Join(got, "\n") != strings.Join(want, "\n") {
		t.Errorf("ERROR sites:\n%s\n\nwant:\n%s", strings.Join(got, "\n"), strings.Join(want, "\n"))
	}
	if len(services) < 15 {
		t.Errorf("%d service packages: the check no longer sees them", len(services))
	}
}

// TestLogLevels: no package writes through the log package, whose lines are
// INFO under the JSON logger whatever they say. Its Logger type, handed to
// net/http as ErrorLog, is the one name allowed. CLIs included.
func TestLogLevels(t *testing.T) {
	units := repo(t)
	if bad := logUses(units); len(bad) > 0 {
		t.Errorf("give these lines their level with slog:\n%s", strings.Join(bad, "\n"))
	}
	if n := slogUses(units); n < 60 {
		t.Errorf("%d uses of slog: the check no longer sees them", n) // the positive control
	}
}

func logUses(units []unit) []string {
	var bad []string
	for _, u := range units {
		for id, obj := range u.info.Uses {
			if obj.Pkg() == nil || obj.Pkg().Path() != "log" {
				continue
			}
			if _, isType := obj.(*types.TypeName); isType {
				continue
			}
			bad = append(bad, u.fset.Position(id.Pos()).String()+": log."+obj.Name())
		}
	}
	slices.Sort(bad)
	return bad
}

func slogUses(units []unit) int {
	n := 0
	for _, u := range units {
		for _, obj := range u.info.Uses {
			if _, ok := obj.(*types.Func); ok && obj.Pkg() != nil && obj.Pkg().Path() == "log/slog" {
				n++
			}
		}
	}
	return n
}

// TestLibraryLoggers: every http.Server logs net/http's own lines (a handler
// panic, an Accept error) at ERROR. Unset, they are INFO through the log
// package; http.ListenAndServe and friends build a server nobody can set it on.
func TestLibraryLoggers(t *testing.T) {
	servers, bad := serverLoggers(repo(t))
	for _, b := range bad {
		t.Error(b)
	}
	if servers < 2 {
		t.Errorf("%d http.Servers: the check no longer sees them", servers) // httpx.Serve and rootd
	}
}

func serverLoggers(units []unit) (servers int, bad []string) {
	for _, u := range units {
		for _, f := range u.files {
			ast.Inspect(f, func(n ast.Node) bool {
				switch n := n.(type) {
				case *ast.Ident:
					if obj, ok := u.info.Uses[n].(*types.Func); ok && obj.Pkg() != nil && obj.Pkg().Path() == "net/http" &&
						obj.Signature().Recv() == nil && slices.Contains([]string{"ListenAndServe", "ListenAndServeTLS", "Serve", "ServeTLS"}, obj.Name()) {
						bad = append(bad, u.fset.Position(n.Pos()).String()+": http."+obj.Name()+" has no ErrorLog: build an http.Server")
					}
				case *ast.CompositeLit:
					if tv, ok := u.info.Types[n]; !ok || tv.Type.String() != "net/http.Server" {
						return true
					}
					servers++
					for _, e := range n.Elts {
						kv, ok := e.(*ast.KeyValueExpr)
						if !ok || kv.Key.(*ast.Ident).Name != "ErrorLog" {
							continue
						}
						if c, ok := kv.Value.(*ast.CallExpr); ok && slogObj(u, calleeID(c)) == "NewLogLogger" && len(c.Args) == 2 {
							if tv := u.info.Types[c.Args[1]]; tv.Value != nil && tv.Value.String() == "8" {
								return true
							}
						}
						bad = append(bad, u.fset.Position(kv.Pos()).String()+": ErrorLog is not slog.NewLogLogger(…, slog.LevelError)")
						return true
					}
					bad = append(bad, u.fset.Position(n.Pos()).String()+": an http.Server without ErrorLog")
				}
				return true
			})
		}
	}
	return servers, bad
}

// TestMainsLog: each binary's first statement installs the JSON logger, on
// stdout for a service (Alloy tails it) and on stderr for a CLI, whose stdout
// is its report. A new binary is a new row here.
func TestMainsLog(t *testing.T) {
	want := map[string]string{
		"server/cmd/api":      "telemetry.NewLogger(os.Stdout)",
		"server/cmd/adminweb": "telemetry.NewLogger(os.Stdout)",
		"jidhr/cmd/rootd":     "telemetry.NewLogger(os.Stdout)",
	}
	for _, c := range cliTools {
		want[c] = "telemetry.NewLogger(os.Stderr)"
	}
	got := mainLoggers(repo(t))
	for rel, w := range want {
		if got[rel] != w {
			t.Errorf("%s: main's first statement installs %q, want slog.SetDefault(%s)", rel, got[rel], w)
		}
	}
	for rel := range got {
		if _, ok := want[rel]; !ok {
			t.Errorf("%s: a binary this test does not know: add it to want", rel)
		}
	}
}

// mainLoggers is, for each package main, what the first statement of main
// passes to slog.SetDefault, or a note saying it does not.
func mainLoggers(units []unit) map[string]string {
	got := map[string]string{}
	for _, u := range units {
		if u.name != "main" {
			continue
		}
		got[u.rel] = "no func main"
		for _, f := range u.files {
			for _, d := range f.Decls {
				fd, ok := d.(*ast.FuncDecl)
				if !ok || fd.Name.Name != "main" || fd.Recv != nil {
					continue
				}
				got[u.rel] = "something other than slog.SetDefault"
				if len(fd.Body.List) == 0 {
					continue
				}
				if s, ok := fd.Body.List[0].(*ast.ExprStmt); ok {
					if c, ok := s.X.(*ast.CallExpr); ok && slogObj(u, calleeID(c)) == "SetDefault" && len(c.Args) == 1 {
						got[u.rel] = types.ExprString(c.Args[0])
					}
				}
			}
		}
	}
	return got
}

// check type-checks one snippet of package x for the forms tables.
func check(t *testing.T, src string) unit {
	t.Helper()
	fset := token.NewFileSet()
	f, err := parser.ParseFile(fset, "x.go", "package x\n"+src, 0)
	if err != nil {
		t.Fatalf("%s: %v", src, err)
	}
	info := &types.Info{Types: map[ast.Expr]types.TypeAndValue{}, Defs: map[*ast.Ident]types.Object{}, Uses: map[*ast.Ident]types.Object{}}
	if _, err := (&types.Config{Importer: importer.Default()}).Check("x", fset, []*ast.File{f}, info); err != nil {
		t.Fatalf("%s: %v", src, err)
	}
	return unit{"x", "x", fset, []*ast.File{f}, info}
}

// TestErrorSiteForms: each form errorSites sees, and what it leaves alone.
func TestErrorSiteForms(t *testing.T) {
	const imp = `import ("context"; "log/slog"); var ctx = context.Background(); `
	for _, c := range []struct{ src, want string }{
		{imp + `func f() { slog.Error("a") }`, `x/x.go: f: "a"`},
		{`import s "log/slog"; func f() { s.Error("a") }`, `x/x.go: f: "a"`},
		{`import . "log/slog"; func f() { Error("a") }`, `x/x.go: f: "a"`},
		{imp + `func f(l *slog.Logger) { l.ErrorContext(ctx, "a") }`, `x/x.go: f: "a"`},
		{imp + `func f() { slog.ErrorContext(ctx, "a") }`, `x/x.go: f: "a"`},
		{imp + `func f(l *slog.Logger) { e := l.Error; e("a") }`, `x/x.go: f: ?`},
		{imp + `func f() { slog.Log(ctx, slog.LevelError, "a") }`, `x/x.go: f: "a"`},
		{imp + `func f(l *slog.Logger) { l.LogAttrs(ctx, slog.LevelError+4, "a") }`, `x/x.go: f: "a"`},
		{imp + `func f(l *slog.Logger) { l.Log(ctx, slog.Level(8), "a") }`, `x/x.go: f: "a"`},
		{imp + `func f(l *slog.Logger, v slog.Level) { l.Log(ctx, v, "a") }`, `x/x.go: f: "a"`},
		{imp + `func f() { _ = slog.NewLogLogger(slog.Default().Handler(), slog.LevelError) }`, `x/x.go: f: LevelError`},
		{imp + `func fail(what string) { slog.Error(what) }; func g() { fail("a") }`,
			"x/x.go: fail: what\nx/x.go: g: fail(\"a\")"},
		{imp + `func fail(what string) { slog.Error(what) }; func mid(w string) { fail(w) }; func g() { mid("a") }`,
			"x/x.go: fail: what\nx/x.go: g: mid(\"a\")\nx/x.go: mid: fail(w)"},
		{imp + `type h struct{}; func (h) fail(what string) { slog.Error(what) }; func g(x h) { x.fail("a") }`,
			"x/x.go: fail: what\nx/x.go: g: fail(\"a\")"},
		{imp + `func f(l *slog.Logger) { slog.Warn("a"); l.Info("b"); l.Log(ctx, slog.LevelWarn, "c") }`, ""},
		{imp + `func f() { slog.Log(ctx, slog.LevelInfo+3, "a") }`, ""},
	} {
		got := strings.Join(errorSites([]unit{check(t, c.src)}), "\n")
		if got != c.want {
			t.Errorf("%s:\n%s\nwant:\n%s", c.src, got, c.want)
		}
	}
}

// TestLogUseForms: each use of the log package the ban sees, and the type it allows.
func TestLogUseForms(t *testing.T) {
	for _, c := range []struct {
		src  string
		want int
	}{
		{`import "log"; func f() { log.Fatal("x") }`, 1},
		{`import l "log"; func f() { l.Printf("x") }`, 1},
		{`import "log"; var p = log.Println`, 1},
		{`import . "log"; func f() { Print("x") }`, 1},
		{`import "log"; var _ = log.Default()`, 1},
		{`import "log"; var _ *log.Logger`, 0},
	} {
		if got := logUses([]unit{check(t, c.src)}); len(got) != c.want {
			t.Errorf("%s: %v, want %d", c.src, got, c.want)
		}
	}
}

// TestServerLoggerForms: each http.Server form the check sees.
func TestServerLoggerForms(t *testing.T) {
	const imp = `import ("log/slog"; "net/http"); var _ = slog.Info; `
	for _, c := range []struct {
		src     string
		servers int
		bad     int
	}{
		{imp + `var _ = &http.Server{ErrorLog: slog.NewLogLogger(slog.Default().Handler(), slog.LevelError)}`, 1, 0},
		{imp + `var _ = http.Server{}`, 1, 1},
		{imp + `var _ = &http.Server{ErrorLog: slog.NewLogLogger(slog.Default().Handler(), slog.LevelInfo)}`, 1, 1},
		{`import ("log"; "net/http"); var _ = &http.Server{ErrorLog: log.Default()}`, 1, 1},
		{imp + `func f() { _ = http.ListenAndServe(":0", nil) }`, 0, 1},
		{imp + `var f = http.Serve`, 0, 1},
		{`import h "net/http"; func f() { _ = h.ListenAndServeTLS(":0", "", "", nil) }`, 0, 1},
	} {
		servers, bad := serverLoggers([]unit{check(t, c.src)})
		if servers != c.servers || len(bad) != c.bad {
			t.Errorf("%s: %d servers, %v; want %d servers, %d problems", c.src, servers, bad, c.servers, c.bad)
		}
	}
}
