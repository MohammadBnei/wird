package httpx

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"log/slog"
	"net"
	"net/http"
	"sync"
	"testing"
	"time"
)

// A SIGTERM that cuts the requests in flight, or cancels the context they are
// working under, turns every rollout into 500s and ERROR lines. The request
// held across the cancel must finish with its 200, its context still live,
// and Serve must return nil.
func TestServeDrainsInFlightOnCancel(t *testing.T) {
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	entered, release := make(chan struct{}), make(chan struct{})
	h := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		close(entered)
		select {
		case <-release:
			w.WriteHeader(http.StatusOK)
		case <-r.Context().Done():
			w.WriteHeader(http.StatusInternalServerError) // the drain cancelled the work
		}
	})
	ctx, cancel := context.WithCancel(context.Background())
	served := make(chan error, 1)
	go func() { served <- serve(ctx, ln, h, slog.New(slog.DiscardHandler), 0) }()

	got := make(chan int, 1)
	go func() {
		resp, err := http.Get("http://" + ln.Addr().String())
		if err != nil {
			t.Error(err)
			got <- 0
			return
		}
		resp.Body.Close()
		got <- resp.StatusCode
	}()
	<-entered
	cancel()
	// Shutdown has stopped accepting: a new connection is refused.
	refused := false
	for range 100 {
		c, err := net.Dial("tcp", ln.Addr().String())
		if err != nil {
			refused = true
			break
		}
		c.Close()
		time.Sleep(10 * time.Millisecond)
	}
	if !refused {
		t.Error("still accepting connections 1s into the drain")
	}
	close(release)
	if code := <-got; code != http.StatusOK {
		t.Errorf("the request in flight at the cancel got %d, want 200", code)
	}
	select {
	case err := <-served:
		if err != nil {
			t.Errorf("Serve after a clean drain: %v, want nil", err)
		}
	case <-time.After(5 * time.Second):
		t.Fatal("Serve did not return after the drain")
	}
}

// Kubernetes takes the pod out of its endpoints only as it sends SIGTERM, and
// Traefik routes here until it notices: a listener closed at the signal turns
// those requests into 502s. A request just after the cancel is still answered.
func TestServeAnswersWhileEndpointsSettle(t *testing.T) {
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	served := make(chan error, 1)
	go func() {
		served <- serve(ctx, ln, http.HandlerFunc(func(http.ResponseWriter, *http.Request) {}), slog.New(slog.DiscardHandler), time.Second)
	}()
	cancel()
	resp, err := http.Get("http://" + ln.Addr().String())
	if err != nil {
		t.Fatalf("a request just after SIGTERM: %v, want it answered", err)
	}
	resp.Body.Close()
	if err := <-served; err != nil {
		t.Errorf("Serve: %v, want nil", err)
	}
}

// net/http's own lines (here a handler panic) must reach the log at ERROR:
// unset, they are INFO through the log package and no alert sees them.
func TestServeErrorLogIsError(t *testing.T) {
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	var mu sync.Mutex
	var buf bytes.Buffer
	log := slog.New(slog.NewJSONHandler(lockedWriter{&mu, &buf}, nil))
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go serve(ctx, ln, http.HandlerFunc(func(http.ResponseWriter, *http.Request) { panic("boom") }), log, 0)

	if resp, err := http.Get("http://" + ln.Addr().String()); err == nil {
		io.Copy(io.Discard, resp.Body)
		resp.Body.Close()
	}
	deadline := time.Now().Add(5 * time.Second)
	for {
		mu.Lock()
		line := buf.Bytes()
		mu.Unlock()
		if len(line) > 0 {
			var rec struct{ Level, Msg string }
			if err := json.Unmarshal(bytes.SplitN(line, []byte("\n"), 2)[0], &rec); err != nil {
				t.Fatalf("%v: %s", err, line)
			}
			if rec.Level != "ERROR" || !bytes.Contains([]byte(rec.Msg), []byte("boom")) {
				t.Errorf("panic logged as %s %q, want ERROR naming the panic", rec.Level, rec.Msg)
			}
			return
		}
		if time.Now().After(deadline) {
			t.Fatal("the panic was never logged")
		}
		time.Sleep(10 * time.Millisecond)
	}
}

type lockedWriter struct {
	mu *sync.Mutex
	w  io.Writer
}

func (l lockedWriter) Write(p []byte) (int, error) {
	l.mu.Lock()
	defer l.mu.Unlock()
	return l.w.Write(p)
}

// A phone that hangs up mid-request cancels its context, and the store call
// fails with context.Canceled: that is the client gone, not our failure, so
// it must not count toward log-error-rate-spike. A live request stays ERROR.
func TestFailedIsWarnWhenTheClientWentAway(t *testing.T) {
	for _, c := range []struct {
		gone bool
		want string
	}{{false, "ERROR"}, {true, "WARN"}} {
		var buf bytes.Buffer
		ctx, cancel := context.WithCancel(context.Background())
		if c.gone {
			cancel()
		}
		r, _ := http.NewRequestWithContext(ctx, http.MethodGet, "/", nil)
		Failed(r, slog.New(slog.NewJSONHandler(&buf, nil)), "sync", "err", context.Canceled)
		cancel()
		var rec struct{ Level, Msg string }
		if err := json.Unmarshal(buf.Bytes(), &rec); err != nil {
			t.Fatalf("%v: %s", err, buf.Bytes())
		}
		if rec.Level != c.want || rec.Msg != "sync" {
			t.Errorf("client gone %v: %s %q, want %s \"sync\"", c.gone, rec.Level, rec.Msg, c.want)
		}
	}
}
