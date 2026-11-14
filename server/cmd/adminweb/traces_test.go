package main

import (
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"go.opentelemetry.io/otel/sdk/trace/tracetest"

	"github.com/MohammadBnei/ukubi-go/telemetry"
)

// Every route but /healthz gets one span named by its pattern, and the span is
// outside the gate: a refusal is traced too. A path no route takes has none.
// Mutations: /healthz wrapped; a gated route's span moved inside the gate, and
// its 401 has none.
func TestEveryPageButHealthzIsTracedOutsideTheGate(t *testing.T) {
	exp := tracetest.NewInMemoryExporter()
	tel := telemetry.WithExporter(exp, "wird-adminweb")
	verifier := clientSecretVerifier("https://authentik.example/", audience, "the-wird-admin-client-secret-at-least-32-bytes")
	h := routes(nil, verifier, []byte("body{}"), slog.New(slog.DiscardHandler), tel)

	for _, c := range []struct {
		method, path, span string
		code               int
	}{
		{"GET", "/healthz", "", http.StatusOK},
		{"GET", "/nope", "", http.StatusNotFound},
		{"GET", "/styles.css", "GET /styles.css", http.StatusOK},
		{"GET", "/icons/favicon.svg", "GET /icons/", http.StatusOK},
		{"GET", "/", "GET /{$}", http.StatusUnauthorized},
		{"GET", "/reports.json", "GET /reports.json", http.StatusUnauthorized},
		{"GET", "/verdicts.json", "GET /verdicts.json", http.StatusUnauthorized},
		{"POST", "/reports/1", "POST /reports/{id}", http.StatusUnauthorized},
	} {
		exp.Reset()
		w := httptest.NewRecorder()
		h.ServeHTTP(w, httptest.NewRequest(c.method, c.path, nil))
		if err := tel.Flush(); err != nil {
			t.Fatal(err)
		}
		spans := exp.GetSpans()
		if w.Code != c.code {
			t.Errorf("%s %s answered %d, want %d", c.method, c.path, w.Code, c.code)
		}
		if c.span == "" && len(spans) != 0 || c.span != "" && (len(spans) != 1 || spans[0].Name != c.span) {
			t.Errorf("%s %s: %d spans, want %q", c.method, c.path, len(spans), c.span)
		}
	}
}

// The favicon is asked for by a browser that carries no token on an icon fetch, so it sits outside the gate like
// the stylesheet. The failure: it moves behind the group and every tab shows no icon. Mutation: wrap /icons/ in gated.
func TestTheFaviconNeedsNoSession(t *testing.T) {
	verifier := clientSecretVerifier("https://authentik.example/", audience, "the-wird-admin-client-secret-at-least-32-bytes")
	h := routes(nil, verifier, []byte("body{}"), slog.New(slog.DiscardHandler), nil)
	w := httptest.NewRecorder()
	h.ServeHTTP(w, httptest.NewRequest("GET", "/icons/favicon.svg", nil))
	if w.Code != http.StatusOK || !strings.HasPrefix(w.Header().Get("Content-Type"), "image/svg+xml") || !strings.HasPrefix(w.Body.String(), "<svg") {
		t.Errorf("GET /icons/favicon.svg without a session = %d %q, want 200 image/svg+xml with an <svg body", w.Code, w.Header().Get("Content-Type"))
	}
}
