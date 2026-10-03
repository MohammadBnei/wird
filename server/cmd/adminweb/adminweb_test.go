package main

import (
	"encoding/json"
	"go/ast"
	"go/parser"
	"go/token"
	"log/slog"
	"maps"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"slices"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/coreos/go-oidc/v3/oidc"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/MohammadBnei/wird/server/internal/store"
	"github.com/MohammadBnei/wird/server/internal/testenv"
)

// The admin app's own audience. A reader's app token is minted for "wird" and
// is not a key to this door even before the group is looked at.
const audience = "wird-admin"

const stylesheet = "../../../docs/design/nocturne-styles.css"

type harness struct {
	routes http.Handler
	issuer *testenv.Issuer
	pool   *pgxpool.Pool
}

func newHarness(t *testing.T) *harness {
	t.Helper()
	db, pool := testenv.Postgres(t)
	issuer := testenv.NewIssuer(t)
	provider, err := oidc.NewProvider(t.Context(), issuer.URL)
	if err != nil {
		t.Fatalf("issuer discovery: %v", err)
	}
	css, err := os.ReadFile(stylesheet)
	if err != nil {
		t.Fatalf("stylesheet: %v", err)
	}
	verifier := provider.Verifier(&oidc.Config{ClientID: audience})
	return &harness{
		routes: routes(db, verifier, css, slog.New(slog.DiscardHandler)),
		issuer: issuer,
		pool:   pool,
	}
}

func (h *harness) get(t *testing.T, path, token string) *httptest.ResponseRecorder {
	t.Helper()
	r := httptest.NewRequest(http.MethodGet, path, nil)
	if token != "" {
		r.Header.Set("Authorization", "Bearer "+token)
	}
	w := httptest.NewRecorder()
	h.routes.ServeHTTP(w, r)
	return w
}

func (h *harness) operator(t *testing.T) string {
	t.Helper()
	return h.issuer.Token(t, "operator", audience, time.Hour,
		map[string]any{"groups": []string{"everyone", operatorGroup}})
}

// Being in Authentik's group is the whole of it, so a token that is genuinely
// the issuer's — signed, unexpired, minted for this audience — and simply does
// not carry the group has to come away with nothing. Each row is a way
// somebody who can sign in ends up reading the operations page.
func TestAValidTokenOutsideThePlatformAdminsGroupIsServedNothing(t *testing.T) {
	h := newHarness(t)

	for _, row := range []struct {
		name   string
		groups any
	}{
		{"no groups claim at all", nil},
		{"groups, none of them the operators'", []string{"everyone", "wird-readers"}},
		{"a group whose name only starts the same", []string{"platform-admins-readonly"}},
	} {
		t.Run(row.name, func(t *testing.T) {
			claims := map[string]any{}
			if row.groups != nil {
				claims["groups"] = row.groups
			}
			token := h.issuer.Token(t, "someone", audience, time.Hour, claims)

			w := h.get(t, "/", token)

			if w.Code != http.StatusForbidden {
				t.Fatalf("answered %d, wanted %d", w.Code, http.StatusForbidden)
			}
			if body := w.Body.String(); strings.Contains(body, "Totals") || strings.Contains(body, "Reports") {
				t.Fatalf("the page was served anyway: %q", body)
			}
		})
	}

	// The control: the same request with the group in it is answered, so the
	// refusals above are the group and not the page being broken.
	if w := h.get(t, "/", h.operator(t)); w.Code != http.StatusOK {
		t.Fatalf("an operator was answered %d, wanted 200", w.Code)
	}
}

func TestNoUnprovenTokenReachesTheOperationsPage(t *testing.T) {
	h := newHarness(t)
	elsewhere := testenv.NewIssuer(t)
	operators := map[string]any{"groups": []string{operatorGroup}}

	for _, row := range []struct {
		name  string
		token string
	}{
		{"no token", ""},
		{"a token this issuer never signed", elsewhere.Token(t, "operator", audience, time.Hour, operators)},
		{"a token that expired an hour ago", h.issuer.Token(t, "operator", audience, -time.Hour, operators)},
		{"a token minted for the readers' app", h.issuer.Token(t, "operator", "wird", time.Hour, operators)},
		{"a token nobody signed", "not.a.token"},
	} {
		t.Run(row.name, func(t *testing.T) {
			w := h.get(t, "/", row.token)
			if w.Code != http.StatusUnauthorized {
				t.Fatalf("answered %d, wanted %d", w.Code, http.StatusUnauthorized)
			}
		})
	}
}

// The failure: authentik's outpost forwards the operator's token as
// X-authentik-jwt, and a page that reads only Authorization answers every
// signed-in operator 401. Or the page takes the outpost's unsigned
// X-authentik-groups at its word, or a token another provider on the same
// signing key minted, and anything that can reach the port is an operator.
func TestTheOutpostsTokenHeaderLetsAnOperatorInAndNothingElseDoes(t *testing.T) {
	h := newHarness(t)
	ask := func(header, value string) int {
		r := httptest.NewRequest(http.MethodGet, "/", nil)
		r.Header.Set(header, value)
		w := httptest.NewRecorder()
		h.routes.ServeHTTP(w, r)
		return w.Code
	}
	operators := map[string]any{"groups": []string{operatorGroup}}

	if code := ask("X-authentik-jwt", h.operator(t)); code != http.StatusOK {
		t.Fatalf("an operator's token forwarded as X-authentik-jwt was answered %d, wanted 200", code)
	}
	if code := ask("X-authentik-groups", operatorGroup); code != http.StatusUnauthorized {
		t.Fatalf("the unsigned group header alone was answered %d, wanted 401", code)
	}
	grafana := h.issuer.Token(t, "operator", "grafana", time.Hour, operators)
	if code := ask("X-authentik-jwt", grafana); code != http.StatusUnauthorized {
		t.Fatalf("a token minted for another provider was answered %d, wanted 401", code)
	}
}

// The rule the design is accountable to, made structural. An operator cannot
// watch one person's practice because nothing this binary can call has a
// reader in it: the store's own aggregates, and no SQL of its own to reach
// around them with. This reads the package's source, so it holds for a handler
// written next year by somebody who never read the ADR.
func TestNothingHereCanAskTheStoreAboutOneReader(t *testing.T) {
	// store.Health, store.Reports, store.SenseVerdicts and store.CorpusVersion
	// take no reader, and store.TriageReport takes a report's id, which no
	// column joins to a reader. Every other method on the store either takes
	// one or can be narrowed to one, and none of them belongs on an operations
	// page.
	allowed := map[string]bool{
		"Health": true, "Reports": true, "CorpusVersion": true, "Close": true,
		"SenseVerdicts": true, "TriageReport": true,
	}
	reader := storeMethods(t)
	if len(reader) == 0 {
		t.Fatal("no store methods found, so this test proves nothing about the ones that exist")
	}

	fset := token.NewFileSet()
	for _, name := range packageSources(t) {
		file, err := parser.ParseFile(fset, name, nil, 0)
		if err != nil {
			t.Fatalf("parse %s: %v", name, err)
		}
		ast.Inspect(file, func(n ast.Node) bool {
			switch node := n.(type) {
			case *ast.SelectorExpr:
				if called := node.Sel.Name; reader[called] && !allowed[called] {
					t.Errorf("%s: %s can be asked about one reader",
						fset.Position(node.Pos()), called)
				}
			case *ast.BasicLit:
				if node.Kind == token.STRING && strings.Contains(strings.ToLower(node.Value), " from ") {
					t.Errorf("%s: a query of its own reaches around the store's aggregates:\n%s",
						fset.Position(node.Pos()), node.Value)
				}
			}
			return true
		})
	}
}

func packageSources(t *testing.T) []string {
	t.Helper()
	entries, err := os.ReadDir(".")
	if err != nil {
		t.Fatalf("read package: %v", err)
	}
	var names []string
	for _, entry := range entries {
		name := entry.Name()
		if strings.HasSuffix(name, ".go") && !strings.HasSuffix(name, "_test.go") {
			names = append(names, name)
		}
	}
	return names
}

// Every method the store has, read from its source, so a per-reader one added
// after this was written is covered without anybody remembering to list it.
func storeMethods(t *testing.T) map[string]bool {
	t.Helper()
	dir := "../../internal/store"
	entries, err := os.ReadDir(dir)
	if err != nil {
		t.Fatalf("read store: %v", err)
	}
	fset := token.NewFileSet()
	methods := map[string]bool{}
	for _, entry := range entries {
		name := entry.Name()
		if !strings.HasSuffix(name, ".go") || strings.HasSuffix(name, "_test.go") {
			continue
		}
		file, err := parser.ParseFile(fset, filepath.Join(dir, name), nil, 0)
		if err != nil {
			t.Fatalf("parse %s: %v", name, err)
		}
		for _, decl := range file.Decls {
			fn, ok := decl.(*ast.FuncDecl)
			if !ok || fn.Recv == nil || !fn.Name.IsExported() {
				continue
			}
			methods[fn.Name.Name] = true
		}
	}
	return methods
}

// The page is rendered from a real database with two readers in it, and the
// only thing it is allowed to say about them is that there are two.
func TestTheTotalsCountReadersWithoutNamingOne(t *testing.T) {
	h := newHarness(t)
	first := h.newReader(t, "sub-one-a1b2")
	second := h.newReader(t, "sub-two-c3d4")
	h.newPrayer(t, first)
	h.newPrayer(t, second)
	h.newPrayer(t, second)

	w := h.get(t, "/", h.operator(t))
	if w.Code != http.StatusOK {
		t.Fatalf("answered %d, wanted 200", w.Code)
	}
	body := w.Body.String()

	for label, want := range map[string]int{"readers": 2, "sets prayed": 3} {
		if !strings.Contains(body, ">"+strconv.Itoa(want)+"<") {
			t.Errorf("%s does not read %d:\n%s", label, want, body)
		}
	}
	for _, naming := range []string{first, second, "sub-one-a1b2", "sub-two-c3d4"} {
		if strings.Contains(body, naming) {
			t.Errorf("the page names a reader: %s", naming)
		}
	}

	preview(t, body)
}

func (h *harness) newReader(t *testing.T, subject string) string {
	t.Helper()
	var id string
	err := h.pool.QueryRow(t.Context(),
		`INSERT INTO users (id, oidc_subject) VALUES (gen_random_uuid(), $1) RETURNING id`,
		subject).Scan(&id)
	if err != nil {
		t.Fatalf("insert reader: %v", err)
	}
	return id
}

func (h *harness) newPrayer(t *testing.T, userID string) {
	t.Helper()
	var setID string
	err := h.pool.QueryRow(t.Context(), `
		INSERT INTO sets (id, user_id, ordinal, start_ayah_id, end_ayah_id, reading_order)
		VALUES (gen_random_uuid(), $1, (SELECT count(*) + 1 FROM sets WHERE user_id = $1), 1001, 1007, 'nuzul')
		RETURNING id`, userID).Scan(&setID)
	if err != nil {
		t.Fatalf("insert set: %v", err)
	}
	_, err = h.pool.Exec(t.Context(), `
		INSERT INTO set_prayers (id, set_id, user_id, prayer_name)
		VALUES (gen_random_uuid(), $1, $2, 'fajr')`, setID, userID)
	if err != nil {
		t.Fatalf("insert prayer: %v", err)
	}
}

// docs/guides/gate-visual.md: the gate looks at the screens. This leaves the rendered
// page and its stylesheet somewhere a person can open them.
func preview(t *testing.T, body string) {
	t.Helper()
	dir := filepath.Join(os.TempDir(), "wird-adminweb")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatalf("preview directory: %v", err)
	}
	css, err := os.ReadFile(stylesheet)
	if err != nil {
		t.Fatalf("stylesheet: %v", err)
	}
	if err := os.WriteFile(filepath.Join(dir, "styles.css"), css, 0o644); err != nil {
		t.Fatalf("write stylesheet: %v", err)
	}
	if err := os.WriteFile(filepath.Join(dir, "index.html"), []byte(body), 0o644); err != nil {
		t.Fatalf("write page: %v", err)
	}
	t.Logf("rendered page: %s", filepath.Join(dir, "index.html"))
}

// A device that did not say which corpus it had sends a zero. Printed as
// "corpus v0" it reads as a build that exists, and the bug gets tied to it.
func TestADeviceThatDidNotSayItsCorpusIsNotShownAsVersionZero(t *testing.T) {
	var out strings.Builder
	err := render(&out, dashboard{ReportsOK: true, Reports: []store.Report{{
		Kind: "bug", Body: "the audio stops", CorpusVersion: 0, WrittenOn: time.Now(),
	}}})
	if err != nil {
		t.Fatalf("render: %v", err)
	}
	body := out.String()

	if strings.Contains(body, "corpus v0") {
		t.Errorf("a build nobody has reads as a build:\n%s", body)
	}
	if !strings.Contains(body, "corpus not said") {
		t.Errorf("the missing version is not named as missing:\n%s", body)
	}
}

func TestReportsThatCouldNotBeReadSaySoRatherThanReadAsNone(t *testing.T) {
	var out strings.Builder
	if err := render(&out, dashboard{ReportsOK: false}); err != nil {
		t.Fatalf("render: %v", err)
	}
	body := out.String()

	if strings.Contains(body, "No reports yet") {
		t.Errorf("a table that could not be read is shown as nobody having written:\n%s", body)
	}
	if !strings.Contains(body, "could not be read") {
		t.Errorf("the failure is not named:\n%s", body)
	}
}

// A report is text a stranger wrote, and it is rendered into the operator's
// page. Nothing in it may become part of that page.
func TestAReportCannotWriteMarkupIntoTheOperatorsPage(t *testing.T) {
	var out strings.Builder
	err := render(&out, dashboard{ReportsOK: true, Reports: []store.Report{{
		Kind:      "bug",
		Body:      `<script>alert(1)</script>`,
		Platform:  "android",
		Screen:    "study",
		WrittenOn: time.Now(),
	}}})
	if err != nil {
		t.Fatalf("render: %v", err)
	}
	if strings.Contains(out.String(), "<script>") {
		t.Errorf("a report wrote a script tag into the page:\n%s", out.String())
	}
}

func (h *harness) post(t *testing.T, path, contentType, body string, header map[string]string) *httptest.ResponseRecorder {
	t.Helper()
	r := httptest.NewRequest(http.MethodPost, path, strings.NewReader(body))
	r.Header.Set("Content-Type", contentType)
	r.Header.Set("Authorization", "Bearer "+h.operator(t))
	for k, v := range header {
		r.Header.Set(k, v)
	}
	w := httptest.NewRecorder()
	h.routes.ServeHTTP(w, r)
	return w
}

// newReport writes a report the way a sweep leaves one, and answers its id.
func (h *harness) newReport(t *testing.T, kind, body string) string {
	t.Helper()
	var id string
	// verdict_root as the sweep would settle it: a thumb on a root we serve.
	err := h.pool.QueryRow(t.Context(), `
		INSERT INTO reports (id, kind, body, app_version, platform, screen, locale, sense_hash, verdict_root)
		VALUES (gen_random_uuid(), $1, $2, '1.4.0', 'android', 'root', 'en', 'a1b2c3d4e5f6',
		        (SELECT root_letters FROM root_senses
		          WHERE $1 = 'improvement' AND $2 IN ('sense good: ' || root_letters, 'sense bad: ' || root_letters)))
		RETURNING id`, kind, body).Scan(&id)
	if err != nil {
		t.Fatalf("insert report: %v", err)
	}
	return id
}

func (h *harness) statusOf(t *testing.T, id string) string {
	t.Helper()
	var status string
	if err := h.pool.QueryRow(t.Context(), `SELECT status FROM reports WHERE id = $1`, id).Scan(&status); err != nil {
		t.Fatalf("read status: %v", err)
	}
	return status
}

// The failure: a page on another site, opened by a signed-in operator whose
// browser carries the token the proxy forwards, posts here and dismisses
// reports in the operator's name.
func TestATriagePostedFromAnotherSiteIsRefused(t *testing.T) {
	h := newHarness(t)
	id := h.newReport(t, "bug", "the audio stops")
	form := "status=dismissed"

	for name, header := range map[string]map[string]string{
		"a browser that says the request is cross-site": {"Sec-Fetch-Site": "cross-site"},
		"an origin that is not this host":               {"Origin": "https://elsewhere.example"},
	} {
		t.Run(name, func(t *testing.T) {
			w := h.post(t, "/reports/"+id, "application/x-www-form-urlencoded", form, header)
			if w.Code != http.StatusForbidden {
				t.Fatalf("answered %d, wanted %d", w.Code, http.StatusForbidden)
			}
			if got := h.statusOf(t, id); got != "new" {
				t.Fatalf("the report was triaged anyway: %s", got)
			}
		})
	}

	// The control: the dashboard's own form, same-origin, lands and goes back
	// to the dashboard.
	w := h.post(t, "/reports/"+id, "application/x-www-form-urlencoded", form,
		map[string]string{"Sec-Fetch-Site": "same-origin"})
	if w.Code != http.StatusSeeOther || h.statusOf(t, id) != "dismissed" {
		t.Fatalf("the operator's own form answered %d and left the report %s", w.Code, h.statusOf(t, id))
	}
}

// The failure: a value the columns would refuse reaches SQL, the constraint
// error is answered 500, and the operator — or the agent working the list —
// reads the server as broken rather than the request as wrong, and retries.
func TestATriageTheColumnsWouldRefuseIsAnsweredAsTheCallersMistake(t *testing.T) {
	h := newHarness(t)
	id := h.newReport(t, "bug", "the audio stops")

	for _, row := range []struct {
		name, path, body string
		want             int
	}{
		{"an id that is not one", "/reports/not-a-uuid", `{"status":"dismissed"}`, http.StatusBadRequest},
		{"an id no report has", "/reports/6ba7b810-9dad-11d1-80b4-00c04fd430c8", `{"status":"dismissed"}`, http.StatusNotFound},
		{"an id spelled as a urn no report has", "/reports/urn:uuid:6ba7b810-9dad-11d1-80b4-00c04fd430c8", `{"status":"dismissed"}`, http.StatusNotFound},
		{"issued with no issue to follow", "/reports/" + id, `{"category":"bug","status":"issued"}`, http.StatusBadRequest},
		{"a category nobody files under", "/reports/" + id, `{"category":"vibes","status":"issued"}`, http.StatusBadRequest},
		{"no status", "/reports/" + id, `{"category":"bug"}`, http.StatusBadRequest},
		{"an issue link that is not GitHub's", "/reports/" + id, `{"status":"issued","issue_url":"javascript:alert(1)"}`, http.StatusBadRequest},
		{"a key the triage does not have", "/reports/" + id, `{"status":"issued","reader":"x"}`, http.StatusBadRequest},
	} {
		t.Run(row.name, func(t *testing.T) {
			w := h.post(t, row.path, "application/json", row.body, nil)
			if w.Code != row.want {
				t.Fatalf("answered %d (%s), wanted %d", w.Code, strings.TrimSpace(w.Body.String()), row.want)
			}
		})
	}
	if got := h.statusOf(t, id); got != "new" {
		t.Fatalf("a refused triage changed the report to %s", got)
	}

	// An id in a spelling Postgres refuses is still that report, not a 500.
	if w := h.post(t, "/reports/urn:uuid:"+id, "application/json", `{"status":"dismissed"}`, nil); w.Code != http.StatusNoContent {
		t.Fatalf("a triage addressed by urn:uuid answered %d (%s)", w.Code, strings.TrimSpace(w.Body.String()))
	}

	// The control: a good one lands.
	w := h.post(t, "/reports/"+id, "application/json",
		`{"category":"bug","status":"issued","issue_url":"https://github.com/MohammadBnei/wird/issues/1"}`, nil)
	if w.Code != http.StatusNoContent || h.statusOf(t, id) != "issued" {
		t.Fatalf("a good triage answered %d and left the report %s", w.Code, h.statusOf(t, id))
	}
}

// The failure: the export carries something that reaches the reader who sent
// a report, or verdicts flood the list an operator reads, or a proxy keeps a
// copy of reports for whoever asks it next.
func TestTheExportsCarryReportsAndTalliesButNoReaderAndAreNeverCached(t *testing.T) {
	h := newHarness(t)
	reader := h.newReader(t, "sub-export-a1b2")
	h.newPrayer(t, reader)
	// The sense is served before anybody can judge it, as on a real server: a
	// verdict is recognised when the sweep lays it down.
	if _, err := h.pool.Exec(t.Context(),
		`INSERT INTO root_senses (root_letters, sense_en, sense_fr) VALUES ('كتب', 'writing', 'écriture')`); err != nil {
		t.Fatalf("insert sense: %v", err)
	}
	h.newReport(t, "bug", "the audio stops")
	h.newReport(t, "improvement", "sense bad: كتب")
	h.newReport(t, "improvement", "sense bad: the French for كتب reads backwards")

	w := h.get(t, "/reports.json", h.operator(t))
	if w.Code != http.StatusOK {
		t.Fatalf("reports.json answered %d", w.Code)
	}
	var export struct {
		Reports   []map[string]any `json:"reports"`
		Truncated bool             `json:"truncated"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &export); err != nil {
		t.Fatalf("reports.json is not the export: %v", err)
	}
	var bodies []string
	for _, r := range export.Reports {
		bodies = append(bodies, r["body"].(string))
	}
	slices.Sort(bodies)
	if want := []string{"sense bad: the French for كتب reads backwards", "the audio stops"}; !slices.Equal(bodies, want) {
		t.Fatalf("reports.json carried %q where the reports written out are %q: a verdict is listed, or a typed report "+
			"that only starts like one is hidden", bodies, want)
	}
	keys := slices.Sorted(maps.Keys(export.Reports[0]))
	want := []string{"app_version", "body", "category", "corpus_version", "id", "issue_url", "kind", "locale",
		"platform", "screen", "sense_hash", "sense_version", "status", "written_on"}
	if !slices.Equal(keys, want) {
		t.Errorf("a report in the export carries %v where it is only %v", keys, want)
	}

	for path, header := range map[string]*httptest.ResponseRecorder{
		"/reports.json":  w,
		"/verdicts.json": h.get(t, "/verdicts.json", h.operator(t)),
		"/":              h.get(t, "/", h.operator(t)),
	} {
		if got := header.Header().Get("Cache-Control"); got != "no-store" {
			t.Errorf("%s answered Cache-Control %q, so a cache can keep it", path, got)
		}
		for _, naming := range []string{reader, "sub-export-a1b2"} {
			if strings.Contains(header.Body.String(), naming) {
				t.Errorf("%s names a reader: %s", path, naming)
			}
		}
	}

	page := h.get(t, "/", h.operator(t)).Body.String()
	if strings.Contains(page, "sense bad: كتب") {
		t.Errorf("a verdict is listed among the reports on the dashboard")
	}
	if !strings.Contains(page, "sense bad: the French for كتب reads backwards") {
		t.Errorf("a typed report that starts like a verdict is missing from the dashboard")
	}
	verdicts := h.get(t, "/verdicts.json", h.operator(t)).Body.String()
	if !strings.Contains(verdicts, `"root":"كتب"`) || !strings.Contains(verdicts, `"bad":1`) {
		t.Errorf("the verdict is not tallied: %s", verdicts)
	}

	if w := h.get(t, "/reports.json?status=whatever", h.operator(t)); w.Code != http.StatusBadRequest {
		t.Errorf("an unknown status filter answered %d, wanted 400", w.Code)
	}
}
