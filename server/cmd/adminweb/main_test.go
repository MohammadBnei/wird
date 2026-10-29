package main

import (
	"bytes"
	"net/http"
	"os"
	"strings"
	"testing"

	"github.com/MohammadBnei/wird/server/internal/testenv"
)

// The whole main, as Kubernetes stops it: SIGTERM once it is listening, then
// exit 0 with "wird-adminweb drained" and no ERROR line. Traces are on, and the
// batcher waits a minute, so only Shutdown can send them: the span of a request
// made while the server settles reaching the collector is main's own tracing
// wired into routes, and Shutdown running after the drain. Mutations: no
// Shutdown, Shutdown on the signal, or nil in place of tel in routes, and the
// span never arrives.
func TestMainDrainsOnSIGTERM(t *testing.T) {
	if os.Getenv("WIRD_ADMINWEB_TEST_CHILD") == "1" {
		main()
		return
	}
	_, pool := testenv.Postgres(t)
	collector := testenv.NewCollector(t)

	status := 0
	out, err := testenv.SIGTERM(t, "TestMainDrainsOnSIGTERM", "WIRD_ADMINWEB_TEST_CHILD", "wird-adminweb listening", []string{
		"WIRD_DEV=",
		"DATABASE_URL=" + pool.Config().ConnString(),
		// The client secret means no discovery: nothing listens here.
		"OIDC_ISSUER=https://authentik.example/application/o/wird-admin/",
		"OIDC_CLIENT_ID=wird-admin",
		"OIDC_CLIENT_SECRET=the-wird-admin-client-secret-at-least-32-bytes",
		"NOCTURNE_CSS=" + stylesheet,
		"ADMIN_ADDR=127.0.0.1:0",
		"OTEL_EXPORTER_OTLP_TRACES_ENDPOINT=" + collector.URL,
		"OTEL_BSP_SCHEDULE_DELAY=60000",
	}, func(addr string) {
		resp, err := http.Get("http://" + addr + "/styles.css")
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
	if !strings.Contains(all, `"msg":"wird-adminweb drained"`) {
		t.Errorf("no drained line:\n%s", all)
	}
	if strings.Contains(all, `"level":"ERROR"`) {
		t.Errorf("an ERROR on a clean SIGTERM:\n%s", all)
	}
	// Positive control: the request was served.
	if status != http.StatusOK {
		t.Errorf("GET /styles.css while settling answered %d, want 200", status)
	}
	got := collector.Received()
	if !bytes.Contains(got, []byte("GET /styles.css")) || !bytes.Contains(got, []byte("wird-adminweb")) {
		t.Errorf("the span of a request served while settling never reached the collector (%d bytes)", len(got))
	}
}
