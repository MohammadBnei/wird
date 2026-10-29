package httpx

import (
	"context"
	"errors"
	"log/slog"
	"net"
	"net/http"
	"time"
)

// Drain is how long Serve gives requests in flight once it stops accepting.
// Settle plus Drain stays under Kubernetes' default 30s grace, so a drain ends
// before the kill does.
const Drain = 20 * time.Second

// Settle is how long Serve keeps accepting after ctx is cancelled. Kubernetes
// sends SIGTERM and takes the pod out of its endpoints at the same moment, and
// Traefik routes to it until it sees that: a listener closed at once refuses
// those requests, and the reader gets a 502.
//
// ponytail: a fixed wait, not a readiness probe that fails first. A test calls
// serve with its own rather than wait this one out.
const Settle = 5 * time.Second

// Serve answers on ln until ctx is cancelled (SIGTERM), keeps answering for
// Settle, then stops accepting and lets the requests in flight finish, for up
// to Drain. It returns nil after a clean drain.
//
// A request's context is never tied to ctx: a SIGTERM must not cancel the work
// it is waiting for, or the drain turns into 500s.
//
// IdleTimeout is above Traefik's 90s, so the proxy closes an idle connection
// before the server does. net/http's own lines (a handler panic, an Accept
// error) are ERROR: something on our side failed.
func Serve(ctx context.Context, ln net.Listener, h http.Handler, log *slog.Logger) error {
	return serve(ctx, ln, h, log, Settle)
}

// serve is Serve with the settle wait given.
func serve(ctx context.Context, ln net.Listener, h http.Handler, log *slog.Logger, settle time.Duration) error {
	srv := &http.Server{
		Handler:           h,
		ReadHeaderTimeout: 10 * time.Second,
		ReadTimeout:       30 * time.Second,
		WriteTimeout:      60 * time.Second,
		IdleTimeout:       120 * time.Second,
		ErrorLog:          slog.NewLogLogger(log.Handler(), slog.LevelError),
	}
	done := make(chan error, 1)
	go func() {
		<-ctx.Done()
		time.Sleep(settle)
		shut, cancel := context.WithTimeout(context.WithoutCancel(ctx), Drain)
		defer cancel()
		done <- srv.Shutdown(shut)
	}()
	if err := srv.Serve(ln); !errors.Is(err, http.ErrServerClosed) {
		return err
	}
	return <-done
}

// Failed logs a failure on our side at ERROR, unless the request's caller has
// already gone away: a phone that drops mid-request cancels r's context, the
// store call then fails with context.Canceled, and a closed connection is not
// our failure (standard §7), so that line is WARN with the same words.
func Failed(r *http.Request, log *slog.Logger, msg string, args ...any) {
	level := slog.LevelError
	if r.Context().Err() != nil {
		level = slog.LevelWarn
	}
	log.Log(r.Context(), level, msg, args...)
}
