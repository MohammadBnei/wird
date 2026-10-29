package main

import (
	"bufio"
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"os/exec"
	"strings"
	"sync"
	"syscall"
	"testing"
	"time"
)

// The whole main, as Kubernetes stops it, with traces on: a request in flight
// when SIGTERM lands finishes, and its span reaches the collector before the
// exit. The batcher waits a minute, so only Shutdown can send it. Mutations: no
// Shutdown, or Shutdown on the signal before the drain, and the span never
// arrives.
func TestMainSendsTheSpansOfTheDrainBeforeItExits(t *testing.T) {
	if os.Getenv("ROOTD_TEST_CHILD") == "1" {
		main()
		return
	}
	var mu sync.Mutex
	var got []byte
	collector := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		body, _ := io.ReadAll(r.Body)
		mu.Lock()
		got = append(got, body...)
		mu.Unlock()
		w.Header().Set("Content-Type", "application/x-protobuf")
	}))
	defer collector.Close()

	cmd := exec.Command(os.Args[0], "-test.run=^TestMainSendsTheSpansOfTheDrainBeforeItExits$")
	cmd.Env = append(os.Environ(),
		"ROOTD_TEST_CHILD=1",
		"ROOTD_DEV=1",
		"ROOTD_API_KEY=",
		"ROOTD_ADDR=127.0.0.1:0",
		"ROOTD_CORPUS="+corpusPath,
		"OTEL_EXPORTER_OTLP_TRACES_ENDPOINT="+collector.URL+"/v1/traces",
		"OTEL_BSP_SCHEDULE_DELAY=60000",
	)
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		t.Fatal(err)
	}
	if err := cmd.Start(); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = cmd.Process.Kill() })
	scan := bufio.NewScanner(stdout)
	var out []string
	var addr string
	for addr == "" && scan.Scan() {
		out = append(out, scan.Text())
		if strings.Contains(scan.Text(), `"msg":"rootd listening"`) {
			var l struct{ Addr string }
			_ = json.Unmarshal(scan.Bytes(), &l)
			addr = l.Addr
		}
	}
	if addr == "" {
		t.Fatalf("never listened:\n%s", strings.Join(out, "\n"))
	}

	// Headers and half a body: the handler is running, waiting on the rest.
	body := `{"words":["` + attestedWord + `"]}`
	conn, err := net.Dial("tcp", addr)
	if err != nil {
		t.Fatal(err)
	}
	defer conn.Close()
	fmt.Fprintf(conn, "POST /v1/roots:batch HTTP/1.1\r\nHost: rootd\r\nContent-Type: application/json\r\nContent-Length: %d\r\n\r\n%s", len(body), body[:5])
	time.Sleep(300 * time.Millisecond)
	if err := cmd.Process.Signal(syscall.SIGTERM); err != nil {
		t.Fatal(err)
	}
	time.Sleep(300 * time.Millisecond)
	fmt.Fprint(conn, body[5:])
	resp, err := http.ReadResponse(bufio.NewReader(conn), nil)
	if err != nil {
		t.Fatalf("the request in flight: %v", err)
	}
	resp.Body.Close()
	// Positive control: the request in flight finished.
	if resp.StatusCode != http.StatusOK {
		t.Errorf("POST /v1/roots:batch in flight answered %d, want 200", resp.StatusCode)
	}

	for scan.Scan() {
		out = append(out, scan.Text())
	}
	all := strings.Join(out, "\n")
	if err := cmd.Wait(); err != nil {
		t.Errorf("exit: %v, want 0:\n%s", err, all)
	}
	if !strings.Contains(all, `"msg":"rootd drained"`) || strings.Contains(all, `"level":"ERROR"`) {
		t.Errorf("want a drained line and no ERROR:\n%s", all)
	}
	mu.Lock()
	defer mu.Unlock()
	if !bytes.Contains(got, []byte("POST /v1/roots:batch")) || !bytes.Contains(got, []byte("rootd")) {
		t.Errorf("the span of the request in flight never reached the collector (%d bytes)", len(got))
	}
}
