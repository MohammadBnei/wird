// Command adminweb is Wird's operations view: the reports readers chose to
// send, and totals. What it cannot show is the point of it — see
// docs/adr/0004-the-operations-view-behind-authentiks-group.md.
package main

import (
	"context"
	"embed"
	"encoding/json"
	"errors"
	"html/template"
	"io"
	"log/slog"
	"net/http"
	"os"
	"slices"
	"strings"

	"github.com/coreos/go-oidc/v3/oidc"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/MohammadBnei/wird/server/internal/store"
)

func main() {
	log := slog.Default()
	ctx := context.Background()

	// store.New, not store.Open: Open runs the migrations, and goose takes no
	// lock, so two binaries migrating the same database at once is a race. The
	// api is the one that migrates; this reads the schema it left.
	pool, err := pgxpool.New(ctx, env("DATABASE_URL", "postgres://wird:wird@localhost:5432/wird"))
	if err == nil {
		err = pool.Ping(ctx)
	}
	if err != nil {
		log.Error("database unavailable", "err", err)
		os.Exit(1)
	}
	db := store.New(pool)
	defer db.Close()

	issuer := env("OIDC_ISSUER", "http://localhost:8082/wird")
	// OIDC_CLIENT_ID is the proxy provider's id as authentik generated it,
	// delivered beside its secret: a proxy provider's id cannot be declared, so
	// it is read from the deployment rather than committed. OIDC_AUDIENCE is
	// the local stub's.
	audience := env("OIDC_CLIENT_ID", env("OIDC_AUDIENCE", "wird-admin"))
	// authentik's proxy provider has no signing key and cannot be given one, so
	// it signs HS256 with its client secret and its keys endpoint verifies
	// nothing it issues. With the secret set, that is the only key; without it
	// (the local stub, which signs RS256) the issuer's published keys are.
	var verifier *oidc.IDTokenVerifier
	if secret := os.Getenv("OIDC_CLIENT_SECRET"); secret != "" {
		verifier = clientSecretVerifier(issuer, audience, secret)
	} else {
		provider, err := oidc.NewProvider(ctx, issuer)
		if err != nil {
			log.Error("issuer unavailable", "issuer", issuer, "err", err)
			os.Exit(1)
		}
		verifier = provider.Verifier(&oidc.Config{ClientID: audience})
	}

	// Read once, and refuse to start without it. An operations page served
	// unstyled is a wall of rows nobody reads carefully, and a dashboard is
	// believed whether or not it is legible.
	css, err := os.ReadFile(env("NOCTURNE_CSS", "docs/design/nocturne-styles.css"))
	if err != nil {
		log.Error("stylesheet unavailable", "err", err)
		os.Exit(1)
	}

	addr := env("ADMIN_ADDR", ":8081")
	log.Info("wird-adminweb listening", "addr", addr, "issuer", issuer, "audience", audience)
	handler := routes(db, verifier, css, log)
	if err := http.ListenAndServe(addr, handler); err != nil {
		log.Error("wird-adminweb stopped", "err", err)
		os.Exit(1)
	}
}

func routes(db *store.Store, verifier *oidc.IDTokenVerifier, css []byte, log *slog.Logger) http.Handler {
	s := &server{db: db, log: log}
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
	})
	mux.HandleFunc("GET /styles.css", func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "text/css; charset=utf-8")
		if _, err := w.Write(css); err != nil {
			log.Error("stylesheet not written", "err", err)
		}
	})
	// Everything past here is behind the group, and none of it is cached: an
	// operator's page or export kept by a proxy or a shared browser is reports
	// read by whoever opens that cache next.
	gated := func(h http.HandlerFunc) http.Handler { return noStore(operators(verifier, log, h)) }
	mux.Handle("GET /{$}", gated(s.dashboard))
	mux.Handle("GET /reports.json", gated(s.reportsJSON))
	mux.Handle("GET /verdicts.json", gated(s.verdictsJSON))
	// The one write. A signed-in operator's browser carries the token the
	// proxy forwards, so a page elsewhere that posts here would be filing
	// reports in their name; Go's own check refuses a cross-origin POST before
	// the token is even looked at.
	mux.Handle("POST /reports/{id}", http.NewCrossOriginProtection().Handler(gated(s.triage)))
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
		s.log.Error("corpus version", "err", err)
	}
	if page.Health, err = s.db.Health(r.Context()); err == nil {
		page.HealthOK = true
	} else {
		s.log.Error("health", "err", err)
	}
	// Verdicts are tallied below rather than listed here, where hundreds of
	// one-word thumbs would bury the reports somebody wrote out.
	page.Reports, page.ReportsCut, err = s.db.Reports(r.Context(),
		store.ReportFilter{ExcludeVerdicts: true, Limit: store.ReportPage})
	if err == nil {
		page.ReportsOK = true
	} else {
		s.log.Error("reports", "err", err)
	}
	if page.Verdicts, err = s.db.SenseVerdicts(r.Context()); err == nil {
		page.VerdictsOK = true
	} else {
		s.log.Error("verdicts", "err", err)
	}

	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	if err := render(w, page); err != nil {
		s.log.Error("page not written", "err", err)
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
		s.log.Error("reports", "err", err)
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
		s.log.Error("verdicts", "err", err)
		http.Error(w, "the verdicts could not be read", http.StatusInternalServerError)
		return
	}
	s.writeJSON(w, verdicts)
}

func (s *server) writeJSON(w http.ResponseWriter, v any) {
	w.Header().Set("Content-Type", "application/json")
	if err := json.NewEncoder(w).Encode(v); err != nil {
		s.log.Error("export not written", "err", err)
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
			http.Error(w, "the body is not a triage: "+err.Error(), http.StatusBadRequest)
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
		s.log.Error("triage", "err", err)
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

func env(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
