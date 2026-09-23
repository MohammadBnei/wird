// Command adminweb is Wird's operations view: the reports readers chose to
// send, and totals. What it cannot show is the point of it — see
// docs/adr/0004-the-operations-view-behind-authentiks-group.md.
package main

import (
	"context"
	"embed"
	"html/template"
	"io"
	"log/slog"
	"net/http"
	"os"

	"github.com/coreos/go-oidc/v3/oidc"

	"github.com/MohammadBnei/wird/server/internal/store"
)

func main() {
	log := slog.Default()
	ctx := context.Background()

	db, err := store.Open(ctx, env("DATABASE_URL", "postgres://wird:wird@localhost:5432/wird"))
	if err != nil {
		log.Error("database unavailable", "err", err)
		os.Exit(1)
	}
	defer db.Close()

	issuer := env("OIDC_ISSUER", "http://localhost:8082/wird")
	provider, err := oidc.NewProvider(ctx, issuer)
	if err != nil {
		log.Error("issuer unavailable", "issuer", issuer, "err", err)
		os.Exit(1)
	}
	audience := env("OIDC_AUDIENCE", "wird-admin")

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
	handler := routes(db, provider.Verifier(&oidc.Config{ClientID: audience}), css, log)
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
	mux.Handle("GET /{$}", operators(verifier, log, http.HandlerFunc(s.dashboard)))
	return mux
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
	if page.Reports, err = s.db.Reports(r.Context(), store.ReportPage); err == nil {
		page.ReportsOK = true
	} else {
		s.log.Error("reports", "err", err)
	}

	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	if err := render(w, page); err != nil {
		s.log.Error("page not written", "err", err)
	}
}

//go:embed dashboard.html
var templates embed.FS

var tmpl = template.Must(template.ParseFS(templates, "dashboard.html"))

func render(w io.Writer, d dashboard) error {
	return tmpl.Execute(w, d)
}

func env(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
