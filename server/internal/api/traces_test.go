package api

import (
	"log/slog"
	"net/http"
	"net/http/httptest"
	"regexp"
	"strings"
	"testing"

	"go.opentelemetry.io/otel/sdk/trace/tracetest"
	"go.opentelemetry.io/otel/trace"

	"github.com/MohammadBnei/ukubi-go/telemetry"

	"github.com/MohammadBnei/wird/server/internal/auth"
	"github.com/MohammadBnei/wird/server/internal/testenv"
)

// traced serves one request through Routes with tracing on and returns the
// answer and the spans it made.
func traced(t *testing.T) func(r *http.Request) (int, tracetest.SpanStubs) {
	t.Helper()
	db, _ := testenv.Postgres(t)
	issuer := testenv.NewIssuer(t)
	a, err := auth.New(t.Context(), issuer.URL, "wird", db, slog.New(slog.DiscardHandler))
	if err != nil {
		t.Fatal(err)
	}
	exp := tracetest.NewInMemoryExporter()
	tel := telemetry.WithExporter(exp, "wird-api")
	routes := Routes(db, a, slog.New(slog.DiscardHandler), Config{}, tel)
	return func(r *http.Request) (code int, spans tracetest.SpanStubs) {
		exp.Reset()
		// A gated handler reached with no reader panics: answered 0.
		defer func() {
			if recover() != nil {
				code = 0
			}
		}()
		w := httptest.NewRecorder()
		routes.ServeHTTP(w, r)
		if err := tel.Flush(); err != nil {
			t.Fatal(err)
		}
		return w.Code, exp.GetSpans()
	}
}

var wildcard = regexp.MustCompile(`\{[^}]*\}`)

// Each gated route is registered twice, on v1 and as the gate on the outer
// mux. One handler put on the outer mux bare is a reader's state on the open
// internet; one span put inside the gate leaves every refusal untraced.
// Mutations: one pattern registered with its handler instead of the gate (the
// 401 goes), or the span inside the gate (the span goes).
func TestEveryGatedRouteRefusesNoTokenUnderItsOwnSpan(t *testing.T) {
	serve := traced(t)
	var h Handler
	for _, r := range h.gated() {
		method, path, _ := strings.Cut(r.pattern, " ")
		code, spans := serve(httptest.NewRequest(method, wildcard.ReplaceAllString(path, "1"), nil))
		if code != http.StatusUnauthorized {
			t.Errorf("%s with no token answered %d, want 401", r.pattern, code)
		}
		if len(spans) != 1 || spans[0].Name != r.pattern {
			t.Errorf("%s: spans %v, want one named by its pattern", r.pattern, names(spans))
		}
	}
}

// A probe every few seconds is not a request worth a span, and a path no
// route takes has no pattern to name one by. Every open route is traced like a
// gated one. Mutations: /healthz wrapped, and it gets a span; an open route
// left bare, and it has none.
func TestEveryRouteButHealthzIsTraced(t *testing.T) {
	serve := traced(t)
	for path, want := range map[string]string{
		"/healthz":                  "",
		"/v1/nope":                  "",
		"/nope/deep":                "",
		callbackPath[4:]:            callbackPath,
		assetLinksPath[4:]:          assetLinksPath,
		appSiteAssociationPath[4:]:  appSiteAssociationPath,
		"/models/recogniser.tflite": modelsPath,
		apkPath[4:]:                 apkPath,
		apkVersionPath[4:]:          apkVersionPath,
		sensesPath[4:]:              sensesPath,
		"/":                         "GET /{$}",
		"/privacy.html":             "GET /{file}",
		"/_ds/x.css":                "GET /_ds/",
	} {
		_, spans := serve(httptest.NewRequest(http.MethodGet, path, nil))
		if want == "" && len(spans) != 0 || want != "" && (len(spans) != 1 || spans[0].Name != want) {
			t.Errorf("GET %s: spans %v, want %q", path, names(spans), want)
		}
	}
}

// Every caller is outside: a traceparent it sends is something it could
// forge, so it starts a new trace linked to the caller's, never a child of it.
func TestAnIncomingTraceparentIsLinkedNotParented(t *testing.T) {
	serve := traced(t)
	const caller = "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01"
	r := httptest.NewRequest(http.MethodGet, "/download/android/version", nil)
	r.Header.Set("Traceparent", caller)
	_, spans := serve(r)
	if len(spans) != 1 {
		t.Fatalf("spans %v, want one", names(spans))
	}
	s := spans[0]
	callerTrace, _ := trace.TraceIDFromHex("0af7651916cd43dd8448eb211c80319c")
	if s.Parent.IsValid() || s.SpanContext.TraceID() == callerTrace {
		t.Errorf("the span is a child of the caller's (parent %v, trace %v)", s.Parent.SpanID(), s.SpanContext.TraceID())
	}
	if len(s.Links) != 1 || s.Links[0].SpanContext.TraceID() != callerTrace {
		t.Errorf("links %v, want one to the caller's trace", s.Links)
	}
}

func names(spans tracetest.SpanStubs) []string {
	var n []string
	for _, s := range spans {
		n = append(n, s.Name)
	}
	return n
}
