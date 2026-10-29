package main

import (
	"bytes"
	"context"
	"net/http"
	"os"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/MohammadBnei/wird/server/internal/testenv"
)

// A sweep in flight when SIGTERM lands has to commit: work gets a context the
// signal does not cancel, and the loop itself stops at the signal.
// Mutation: every passing ctx to work instead of WithoutCancel(ctx) fails the
// "cancelled under it" check.
func TestEveryStopsAtTheSignalButNotTheWorkInFlight(t *testing.T) {
	ctx, cancel := context.WithCancel(t.Context())
	got := make(chan context.Context)
	release := make(chan struct{})
	done := make(chan struct{})
	go func() {
		defer close(done)
		every(ctx, time.Hour, func(work context.Context) {
			got <- work
			<-release
		})
	}()

	// Positive control: work runs at once, on a live context.
	var work context.Context
	select {
	case work = <-got:
	case <-time.After(5 * time.Second):
		t.Fatal("work did not run at start")
	}
	if work.Err() != nil {
		t.Fatalf("work started on a cancelled context: %v", work.Err())
	}

	cancel()
	if work.Err() != nil {
		t.Errorf("the signal cancelled the work in flight under it: %v", work.Err())
	}
	close(release)
	select {
	case <-done:
	case <-time.After(5 * time.Second):
		t.Fatal("every did not return after cancel")
	}
}

// A SIGTERM that lands before the loops start must not set off a full prune or
// sweep, which would spend the grace period while the exit waits on it.
func TestEveryDoesNoWorkAfterTheSignal(t *testing.T) {
	ctx, cancel := context.WithCancel(t.Context())
	cancel()
	every(ctx, time.Hour, func(context.Context) { t.Error("work ran after the signal") })
}

// The whole main, as Kubernetes stops it: SIGTERM once it is listening, then
// exit 0 with "wird-api drained" and no ERROR line. Traces are on, and the
// batcher waits a minute, so only Shutdown can send them: the span of a request
// made while the server settles reaching the collector is Shutdown running
// after the drain. Mutations: no Shutdown, or Shutdown on the signal before
// the drain, and the span never arrives.
func TestMainDrainsOnSIGTERM(t *testing.T) {
	if os.Getenv("WIRD_API_TEST_CHILD") == "1" {
		main()
		return
	}
	_, pool := testenv.Postgres(t)
	issuer := testenv.NewIssuer(t)
	collector := testenv.NewCollector(t)

	status := 0
	out, err := testenv.SIGTERM(t, "TestMainDrainsOnSIGTERM", "WIRD_API_TEST_CHILD", "wird-api listening", []string{
		"WIRD_DEV=",
		"DATABASE_URL=" + pool.Config().ConnString(),
		"OIDC_ISSUER=" + issuer.URL,
		"OIDC_AUDIENCE=wird",
		"API_ADDR=127.0.0.1:0",
		"OTEL_EXPORTER_OTLP_TRACES_ENDPOINT=" + collector.URL,
		"OTEL_BSP_SCHEDULE_DELAY=60000",
	}, func(addr string) {
		resp, err := http.Get("http://" + addr + "/v1/me")
		if err != nil {
			t.Errorf("a request while settling: %v", err)
			return
		}
		resp.Body.Close()
		status = resp.StatusCode
	})
	all := strings.Join(out, "\n")
	if err != nil {
		t.Errorf("exit: %v, want 0:\n%s", err, all)
	}
	if !strings.Contains(all, `"msg":"wird-api drained"`) {
		t.Errorf("no drained line:\n%s", all)
	}
	if strings.Contains(all, `"level":"ERROR"`) {
		t.Errorf("an ERROR on a clean SIGTERM:\n%s", all)
	}
	// The start line names the release (buildinfo); a test build is "dev".
	// Mutation: the attribute dropped from the line, and this fails.
	if !slices.ContainsFunc(out, func(l string) bool {
		return strings.Contains(l, `"msg":"wird-api listening"`) && strings.Contains(l, `"version":"dev"`)
	}) {
		t.Errorf("the start line does not name the release:\n%s", all)
	}
	// Positive control: the request was served, and refused at the gate.
	if status != http.StatusUnauthorized {
		t.Errorf("GET /v1/me while settling answered %d, want 401", status)
	}
	got := collector.Received()
	if !bytes.Contains(got, []byte("GET /v1/me")) || !bytes.Contains(got, []byte("wird-api")) {
		t.Errorf("the span of a request served while settling never reached the collector (%d bytes)", len(got))
	}
}
