package main

import (
	"bytes"
	"context"
	"log/slog"
	"net"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

// rootd's copy of httpx.Serve: a SIGTERM must let the request in flight finish
// with its 200, under a context the signal did not cancel, and serve must
// return nil after the drain rather than exit 1.
func TestServeDrainsInFlightOnCancel(t *testing.T) {
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	entered, release := make(chan struct{}), make(chan struct{})
	httpd := &http.Server{Handler: http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		close(entered)
		select {
		case <-release:
			w.WriteHeader(http.StatusOK)
		case <-r.Context().Done():
			w.WriteHeader(http.StatusInternalServerError)
		}
	})}
	ctx, cancel := context.WithCancel(context.Background())
	served := make(chan error, 1)
	go func() { served <- serve(ctx, httpd, ln) }()

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
	time.Sleep(50 * time.Millisecond) // Shutdown under way, the request still held
	close(release)
	if code := <-got; code != http.StatusOK {
		t.Errorf("the request in flight at the cancel got %d, want 200", code)
	}
	select {
	case err := <-served:
		if err != nil {
			t.Errorf("serve after a clean drain: %v, want nil", err)
		}
	case <-time.After(5 * time.Second):
		t.Fatal("serve did not return after the drain")
	}
}

// A caller that hangs up cancels its request, and the store call fails with
// context.Canceled: that is not our failure, so it is WARN, not ERROR.
func TestWriteInternalIsWarnWhenTheCallerWentAway(t *testing.T) {
	for _, c := range []struct {
		gone bool
		want string
	}{{false, `"level":"ERROR"`}, {true, `"level":"WARN"`}} {
		var buf bytes.Buffer
		s := &server{log: slog.New(slog.NewJSONHandler(&buf, nil))}
		ctx, cancel := context.WithCancel(context.Background())
		if c.gone {
			cancel()
		}
		r := httptest.NewRequestWithContext(ctx, http.MethodGet, "/v1/roots/x", nil)
		s.writeInternal(httptest.NewRecorder(), r, "look up a root", context.Canceled)
		cancel()
		if !strings.Contains(buf.String(), c.want) {
			t.Errorf("caller gone %v: %s, want %s", c.gone, buf.String(), c.want)
		}
	}
}
