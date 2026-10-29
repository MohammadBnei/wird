package testenv

import (
	"bufio"
	"encoding/json"
	"io"
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

// Collector is an OTLP/HTTP traces endpoint inside the test process. URL is
// what OTEL_EXPORTER_OTLP_TRACES_ENDPOINT points at.
type Collector struct {
	URL string
	mu  sync.Mutex
	got []byte
}

// NewCollector starts one for the length of the test.
func NewCollector(t *testing.T) *Collector {
	t.Helper()
	c := &Collector{}
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		body, _ := io.ReadAll(r.Body)
		c.mu.Lock()
		c.got = append(c.got, body...)
		c.mu.Unlock()
		w.Header().Set("Content-Type", "application/x-protobuf")
	}))
	t.Cleanup(srv.Close)
	c.URL = srv.URL + "/v1/traces"
	return c
}

// Received is every export body so far, end to end: the protobuf carries span
// and service names as raw bytes, so a test looks for them with bytes.Contains.
func (c *Collector) Received() []byte {
	c.mu.Lock()
	defer c.mu.Unlock()
	return append([]byte(nil), c.got...)
}

// SIGTERM is a cmd main as Kubernetes stops it. It runs the test binary again
// as the test named run, which calls main when child is set in its
// environment, with env added. Once main logs listening, it sends SIGTERM,
// waits a moment so main has seen it, and calls settling with the address
// main listens on: that is a request made while the server settles. It
// returns main's stdout, one line each, and its exit error.
func SIGTERM(t *testing.T, run, child, listening string, env []string, settling func(addr string)) ([]string, error) {
	t.Helper()
	cmd := exec.Command(os.Args[0], "-test.run=^"+run+"$")
	cmd.Env = append(append(os.Environ(), child+"=1"), env...)
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		t.Fatal(err)
	}
	if err := cmd.Start(); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = cmd.Process.Kill() })

	lines := make(chan string)
	go func() {
		defer close(lines)
		scan := bufio.NewScanner(stdout)
		for scan.Scan() {
			lines <- scan.Text()
		}
	}()

	var out []string
	timeout := time.After(30 * time.Second)
	signalled := false
	for line, ok := "", true; ok; {
		select {
		case line, ok = <-lines:
			if !ok {
				break
			}
			out = append(out, line)
			if !signalled && strings.Contains(line, `"msg":"`+listening+`"`) {
				signalled = true
				var l struct{ Addr string }
				_ = json.Unmarshal([]byte(line), &l)
				if err := cmd.Process.Signal(syscall.SIGTERM); err != nil {
					t.Fatal(err)
				}
				time.Sleep(300 * time.Millisecond)
				settling(l.Addr)
			}
		case <-timeout:
			t.Fatalf("no exit within 30s:\n%s", strings.Join(out, "\n"))
		}
	}
	if !signalled {
		t.Fatalf("never listened:\n%s", strings.Join(out, "\n"))
	}
	return out, cmd.Wait()
}
