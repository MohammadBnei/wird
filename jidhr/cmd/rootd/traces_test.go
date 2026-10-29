package main

import (
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"go.opentelemetry.io/otel/sdk/trace/tracetest"

	"github.com/MohammadBnei/ukubi-go/telemetry"
)

// Each /v1 route is registered twice from one table: on the inner mux, and on
// the top one as the same gate under a span. One handler put on top bare is
// rootd with no key and no limit; one span put inside the gate leaves every
// 401 and 429 untraced. /healthz and a path no route takes have no span.
// Mutations: a route on top with its handler instead of the gate (the 401
// goes); the span inside the gate (the spans go); /healthz wrapped.
func TestEveryV1RouteIsGatedUnderItsOwnSpan(t *testing.T) {
	exp := tracetest.NewInMemoryExporter()
	s := testServer(t, nil)
	s.apiKey = "the-key"
	s.limiter = newLimiter(0.25, 1)
	s.tracing = telemetry.WithExporter(exp, "rootd")
	h := s.routes()

	caller := 0
	serve := func(method, path string, same bool) (int, []string) {
		if !same {
			caller++
		}
		exp.Reset()
		r := httptest.NewRequest(method, path, strings.NewReader(`{"words":[]}`))
		r.RemoteAddr = fmt.Sprintf("10.0.0.%d:1234", caller)
		w := httptest.NewRecorder()
		h.ServeHTTP(w, r)
		if err := s.tracing.Flush(); err != nil {
			t.Fatal(err)
		}
		var names []string
		for _, sp := range exp.GetSpans() {
			names = append(names, sp.Name)
		}
		return w.Code, names
	}

	for _, r := range s.v1() {
		method, path, _ := strings.Cut(r.pattern, " ")
		path = strings.ReplaceAll(path, "{letters}", attestedLetters)
		for _, want := range []int{http.StatusUnauthorized, http.StatusTooManyRequests} {
			code, spans := serve(method, path, want == http.StatusTooManyRequests)
			if code != want {
				t.Errorf("%s with no key answered %d, want %d", r.pattern, code, want)
			}
			if len(spans) != 1 || spans[0] != r.pattern {
				t.Errorf("%s answering %d: spans %v, want one named by its pattern", r.pattern, want, spans)
			}
		}
	}
	for _, path := range []string{"/healthz", "/v1/nope"} {
		if _, spans := serve("GET", path, false); len(spans) != 0 {
			t.Errorf("GET %s: spans %v, want none", path, spans)
		}
	}
}
