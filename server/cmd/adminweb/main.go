// Command adminweb is Wird's operations view: the reports readers chose to
// send, and totals. What it cannot show is the point of it — see
// docs/adr/0004-the-operations-view-behind-authentiks-group.md.
package main

import (
	"bytes"
	"context"
	"embed"
	"encoding/json"
	"errors"
	"html/template"
	"io"
	"log/slog"
	"net"
	"net/http"
	"os"
	"os/signal"
	"slices"
	"strings"
	"syscall"

	"github.com/coreos/go-oidc/v3/oidc"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/MohammadBnei/ukubi-go/telemetry"

	"github.com/MohammadBnei/wird/server/internal/httpx"
	"github.com/MohammadBnei/wird/server/internal/store"
)

func main() {
	slog.SetDefault(telemetry.NewLogger(os.Stdout))
	os.Exit(run(slog.Default()))
}

// run is main with an exit code, so the deferred db.Close runs before the
// process exits.
func run(log *slog.Logger) int {
	// SIGTERM cancels ctx and the server drains; a second signal kills at once.
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGTERM, os.Interrupt)
	defer stop()
	go func() { <-ctx.Done(); stop() }()

	// Every problem with the configuration at once, before anything is opened.
	cfg, err := fromProcess()
	if err != nil {
		log.Error("config refused", "err", err)
		return 1
	}

	// Before the database: deferred first, Shutdown runs last, once Serve has
	// drained and db.Close is done. Inert when cfg.Traces is empty
	// (docs/adr/0040).
	tel, err := telemetry.New(cfg.Traces, "wird-adminweb")
	if err != nil {
		log.Error("tracing unavailable", "err", err)
		return 1
	}
	defer func() {
		if err := tel.Shutdown(); err != nil {
			log.Warn("traces", "err", err)
		}
	}()

	// store.New, not store.Open: Open runs the migrations, and goose takes no
	// lock, so two binaries migrating the same database at once is a race. The
	// api is the one that migrates; this reads the schema it left.
	//
	// Startup runs to the end even after a SIGTERM, and Serve then drains at
	// once: a connect or discovery cancelled halfway would log a false ERROR.
	start := context.WithoutCancel(ctx)
	pool, err := pgxpool.New(start, cfg.DatabaseURL)
	if err == nil {
		err = pool.Ping(start)
	}
	if err != nil {
		log.Error("database unavailable", "err", err)
		return 1
	}
	db := store.New(pool)
	defer db.Close()

	// The audience is OIDC_CLIENT_ID, else OIDC_AUDIENCE: config.go says why.
	issuer, audience := cfg.OIDCIssuer, cfg.Audience
	// authentik's proxy provider has no signing key and cannot be given one, so
	// it signs HS256 with its client secret and its keys endpoint verifies
	// nothing it issues. With the secret set, that is the only key; without it
	// (the local stub, which signs RS256) the issuer's published keys are.
	var verifier *oidc.IDTokenVerifier
	if secret := cfg.ClientSecret; secret != "" {
		verifier = clientSecretVerifier(issuer, audience, secret)
	} else {
		provider, err := oidc.NewProvider(start, issuer)
		if err != nil {
			log.Error("issuer unavailable", "issuer", issuer, "err", err)
			return 1
		}
		verifier = provider.Verifier(&oidc.Config{ClientID: audience})
	}

	// Read once, and refuse to start without it. An operations page served
	// unstyled is a wall of rows nobody reads carefully, and a dashboard is
	// believed whether or not it is legible.
	css, err := os.ReadFile(cfg.CSSPath)
	if err != nil {
		log.Error("stylesheet unavailable", "err", err)
		return 1
	}

	// Bind before announcing it: a port in use logs only the listen error.
	ln, err := net.Listen("tcp", cfg.Addr)
	if err != nil {
		log.Error("wird-adminweb stopped", "err", err)
		return 1
	}
	log.Info("wird-adminweb listening", "addr", ln.Addr().String(), "issuer", issuer, "audience", audience, "dev", cfg.Dev)
	if err := httpx.Serve(ctx, ln, routes(db, verifier, css, log, tel), log); err != nil {
		if ctx.Err() != nil {
			log.Error("wird-adminweb shutdown failed", "err", err)
		} else {
			log.Error("wird-adminweb stopped", "err", err)
		}
		return 1
	}
	log.Info("wird-adminweb drained")
	return 0
}

// routes is every page. Each route but /healthz gets a span from t, outside
// its gate, so a refusal is traced too; a nil or inert t adds nothing.
func routes(db *store.Store, verifier *oidc.IDTokenVerifier, css []byte, log *slog.Logger, t *telemetry.Tracing) http.Handler {
	s := &server{db: db, log: log}
	mux := http.NewServeMux()
	handle := func(pattern string, h http.Handler) { mux.Handle(pattern, t.Handler(pattern, h)) }
	// Untraced: a probe every few seconds is noise, not a request.
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
	})
	handle("GET /styles.css", http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/css; charset=utf-8")
		if _, err := w.Write(css); err != nil {
			log.WarnContext(r.Context(), "stylesheet not written", "err", err) // the client went away
		}
	}))
	// Everything past here is behind the group, and none of it is cached: an
	// operator's page or export kept by a proxy or a shared browser is reports
	// read by whoever opens that cache next.
	gated := func(h http.HandlerFunc) http.Handler { return noStore(operators(verifier, log, h)) }
	handle("GET /{$}", gated(s.dashboard))
	handle("GET /reports.json", gated(s.reportsJSON))
	handle("GET /verdicts.json", gated(s.verdictsJSON))
	// The one write. A signed-in operator's browser carries the token the
	// proxy forwards, so a page elsewhere that posts here would be filing
	// reports in their name; Go's own check refuses a cross-origin POST before
	// the token is even looked at.
	handle("POST /reports/{id}", http.NewCrossOriginProtection().Handler(gated(s.triage)))
	return mux
}

func noStore(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Cache-Control", "no-store")
		next.ServeHTTP(w, r)
	})
}

type server struct {
	db  *store.Store
	log *slog.Logger
}

// dashboard is what an operator sees. Each section is read on its own and says
// so when it could not be read: a section nobody could compute, printed as a
// zero or as an empty list, is worse than a blank, because a dashboard is
// believed.
type dashboard struct {
	Corpus    store.CorpusVersion
	CorpusOK  bool
	Health    store.Health
	HealthOK  bool
	Reports   []store.Report
	ReportsOK bool
	// More reports than one page holds; the export has the rest.
	ReportsCut bool
	Verdicts   []store.SenseVerdict
	VerdictsOK bool
}

func (s *server) dashboard(w http.ResponseWriter, r *http.Request) {
	var page dashboard
	var err error

	if page.Corpus, err = s.db.CorpusVersion(r.Context()); err == nil {
		page.CorpusOK = true
	} else {
		httpx.Failed(r, s.log, "corpus version", "err", err)
	}
	if page.Health, err = s.db.Health(r.Context()); err == nil {
		page.HealthOK = true
	} else {
		httpx.Failed(r, s.log, "health", "err", err)
	}
	// Verdicts are tallied below rather than listed here, where hundreds of
	// one-word thumbs would bury the reports somebody wrote out.
	page.Reports, page.ReportsCut, err = s.db.Reports(r.Context(),
		store.ReportFilter{ExcludeVerdicts: true, Limit: store.ReportPage})
	if err == nil {
		page.ReportsOK = true
	} else {
		httpx.Failed(r, s.log, "reports", "err", err)
	}
	if page.Verdicts, err = s.db.SenseVerdicts(r.Context()); err == nil {
		page.VerdictsOK = true
	} else {
		httpx.Failed(r, s.log, "verdicts", "err", err)
	}

	// Rendered whole before a byte is sent: a template fault is ours (ERROR),
	// a write that fails after it is a client gone away (WARN).
	var buf bytes.Buffer
	if err := render(&buf, page); err != nil {
		s.log.ErrorContext(r.Context(), "page not written", "err", err)
		http.Error(w, "the page could not be rendered", http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	if _, err := buf.WriteTo(w); err != nil {
		s.log.WarnContext(r.Context(), "page not written", "err", err)
	}
}

// reportsJSON is the reports for an agent or a script to work through, newest
// first, verdicts left out because /verdicts.json tallies them. truncated says
// the cap cut the list short, so a reader of the export knows it is not all.
func (s *server) reportsJSON(w http.ResponseWriter, r *http.Request) {
	status := r.URL.Query().Get("status")
	if status != "" && !slices.Contains(store.ReportStatuses, status) {
		http.Error(w, "status is one of "+strings.Join(store.ReportStatuses, ", "), http.StatusBadRequest)
		return
	}
	reports, truncated, err := s.db.Reports(r.Context(),
		store.ReportFilter{Status: status, ExcludeVerdicts: true, Limit: store.ReportExport})
	if err != nil {
		httpx.Failed(r, s.log, "reports", "err", err)
		http.Error(w, "the reports could not be read", http.StatusInternalServerError)
		return
	}
	s.writeJSON(w, struct {
		Reports   []store.Report `json:"reports"`
		Truncated bool           `json:"truncated"`
	}{reports, truncated})
}

func (s *server) verdictsJSON(w http.ResponseWriter, r *http.Request) {
	verdicts, err := s.db.SenseVerdicts(r.Context())
	if err != nil {
		httpx.Failed(r, s.log, "verdicts", "err", err)
		http.Error(w, "the verdicts could not be read", http.StatusInternalServerError)
		return
	}
	s.writeJSON(w, verdicts)
}

func (s *server) writeJSON(w http.ResponseWriter, v any) {
	w.Header().Set("Content-Type", "application/json")
	if err := json.NewEncoder(w).Encode(v); err != nil {
		s.log.Warn("export not written", "err", err) // the client went away
	}
}

// triageForm is what an operator says about one report. All three are written
// together, so a field left out is cleared; status alone may not be empty.
type triageForm struct {
	Category string `json:"category"`
	Status   string `json:"status"`
	IssueURL string `json:"issue_url"`
}

// check is the column CHECKs said again before SQL, so a bad value is a 400
// with its reason rather than a constraint error read as the server failing.
// One rule is stricter than the columns: a report marked issued names the
// issue, or "issued" is a claim nobody can follow to anything.
func (f triageForm) check() string {
	if f.Category != "" && !slices.Contains(store.ReportCategories, f.Category) {
		return "category is empty or one of " + strings.Join(store.ReportCategories, ", ")
	}
	if !slices.Contains(store.ReportStatuses, f.Status) {
		return "status is one of " + strings.Join(store.ReportStatuses, ", ")
	}
	if f.IssueURL != "" && !strings.HasPrefix(f.IssueURL, "https://github.com/") {
		return "issue_url is empty or a https://github.com/ link"
	}
	if f.Status == "issued" && f.IssueURL == "" {
		return "an issued report needs its issue_url"
	}
	return ""
}

// triage takes the dashboard's form or a JSON body. The form is answered with
// the dashboard again; JSON with 204, since the caller already has the row.
func (s *server) triage(w http.ResponseWriter, r *http.Request) {
	r.Body = http.MaxBytesReader(w, r.Body, 4<<10)
	var f triageForm
	isJSON := strings.HasPrefix(r.Header.Get("Content-Type"), "application/json")
	if isJSON {
		decoder := json.NewDecoder(r.Body)
		decoder.DisallowUnknownFields()
		if err := decoder.Decode(&f); err != nil {
			s.log.InfoContext(r.Context(), "triage body refused", "err", err) // client input
			http.Error(w, "the body is not a triage", http.StatusBadRequest)
			return
		}
	} else {
		if err := r.ParseForm(); err != nil {
			http.Error(w, "the form could not be read", http.StatusBadRequest)
			return
		}
		f = triageForm{r.PostForm.Get("category"), r.PostForm.Get("status"), r.PostForm.Get("issue_url")}
	}

	// uuid.Parse also takes urn:uuid:, braces and no hyphens, which Postgres
	// refuses; the canonical form it hands back is what goes to SQL.
	id, err := uuid.Parse(r.PathValue("id"))
	if err != nil {
		http.Error(w, "no report has that id", http.StatusBadRequest)
		return
	}
	if reason := f.check(); reason != "" {
		http.Error(w, reason, http.StatusBadRequest)
		return
	}
	switch err := s.db.TriageReport(r.Context(), id.String(), f.Category, f.Status, f.IssueURL); {
	case errors.Is(err, store.ErrReportNotFound):
		http.Error(w, "no report has that id", http.StatusNotFound)
	case err != nil:
		httpx.Failed(r, s.log, "triage", "err", err)
		http.Error(w, "the triage could not be written", http.StatusInternalServerError)
	case isJSON:
		w.WriteHeader(http.StatusNoContent)
	default:
		http.Redirect(w, r, "/", http.StatusSeeOther)
	}
}

//go:embed dashboard.html
var templates embed.FS

var tmpl = template.Must(template.New("dashboard.html").Funcs(template.FuncMap{
	"categories": func() []string { return store.ReportCategories },
	"statuses":   func() []string { return store.ReportStatuses },
}).ParseFS(templates, "dashboard.html"))

func render(w io.Writer, d dashboard) error {
	return tmpl.Execute(w, d)
}
