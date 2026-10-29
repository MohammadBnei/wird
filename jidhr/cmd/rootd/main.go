// Command rootd serves the Arabic root engine over HTTP for callers outside Wird.
package main

import (
	"context"
	"errors"
	"log/slog"
	"net"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/MohammadBnei/ukubi-go/telemetry"

	"github.com/MohammadBnei/wird/jidhr/pkg/root"
)

// burstPerRate turns the one rate knob into a burst, so a caller can spend a few
// seconds of its allowance at once — which is what a page of words looks like —
// without being able to spend a minute of it.
const burstPerRate = 4

func main() {
	// JSON on stdout for Alloy to tail (docs/adr/0039), with a request's
	// trace_id and span_id when tracing is on (docs/adr/0040).
	slog.SetDefault(telemetry.NewLogger(os.Stdout))
	log := slog.Default()

	// Every problem with the configuration at once, before anything is opened.
	cfg, err := fromProcess()
	if err != nil {
		log.Error("config refused", "err", err)
		os.Exit(1)
	}
	// Inert when cfg.Traces is empty (docs/adr/0040).
	tel, err := telemetry.New(cfg.Traces, "rootd")
	if err != nil {
		log.Error("tracing unavailable", "err", err)
		os.Exit(1)
	}

	corpusPath := cfg.Corpus
	// ponytail: the whole corpus in memory, read from one JSON file — 1,642 roots,
	// 17,934 attested forms and 523 meanings is about a megabyte. Give the resolver
	// a Store backed by a database when a corpus arrives that does not fit, or when
	// a meaning has to change without a restart. Nothing above here changes when it
	// does, because the resolver only ever knew a Store.
	f, err := os.Open(corpusPath)
	if err != nil {
		log.Error("open the corpus", "path", corpusPath, "err", err)
		os.Exit(1)
	}
	store, err := root.LoadMemoryStore(f)
	f.Close()
	if err != nil {
		log.Error("load the corpus", "path", corpusPath, "err", err)
		os.Exit(1)
	}

	rate := cfg.Rate
	srv := &server{
		resolver: root.New(store),
		store:    store,
		langs:    store.Languages(),
		apiKey:   cfg.APIKey,
		log:      log,
		tracing:  tel,
	}
	if rate > 0 {
		srv.limiter = newLimiter(rate, rate*burstPerRate)
	}

	addr := cfg.Addr
	httpd := &http.Server{
		Addr:    addr,
		Handler: srv.routes(),
		// A public listener with no read deadline is held open for free by anyone
		// willing to send one header byte a minute.
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       15 * time.Second,
		WriteTimeout:      30 * time.Second,
		IdleTimeout:       60 * time.Second,
		// net/http's own lines (a handler panic, an Accept error) are ERROR.
		ErrorLog: slog.NewLogLogger(log.Handler(), slog.LevelError),
	}

	// Bind before announcing it. Logging the line first means a port already in
	// use prints a confident "listening" and then the error that it never did.
	ln, err := net.Listen("tcp", addr)
	if err != nil {
		log.Error("listen", "addr", addr, "err", err)
		os.Exit(1)
	}

	// SIGTERM drains the requests in flight; a second signal kills at once.
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGTERM, os.Interrupt)
	defer stop()
	go func() { <-ctx.Done(); stop() }()

	log.Info("rootd listening",
		"addr", ln.Addr().String(), "corpus", corpusPath, "languages", srv.langs,
		"authenticated", srv.apiKey != "", "rate_per_second", rate, "dev", cfg.Dev)
	err = serve(ctx, httpd, ln)
	// After the drain, so the spans of the requests it waited for are sent;
	// before the exit either way, since os.Exit runs no deferred call.
	if err := tel.Shutdown(); err != nil {
		log.Warn("traces", "err", err)
	}
	if err != nil {
		if ctx.Err() != nil {
			log.Error("rootd shutdown failed", "err", err)
		} else {
			log.Error("rootd stopped", "err", err)
		}
		os.Exit(1)
	}
	log.Info("rootd drained")
}

// drain is how long serve gives requests in flight after ctx is cancelled:
// under Kubernetes' default 30s grace.
const drain = 20 * time.Second

// serve is server/internal/httpx.Serve over rootd's own http.Server (jidhr
// cannot import server's internal packages): it answers on ln until ctx is
// cancelled, then lets the requests in flight finish, for up to drain, and
// returns nil after a clean drain. A request's context is never tied to ctx.
func serve(ctx context.Context, httpd *http.Server, ln net.Listener) error {
	done := make(chan error, 1)
	go func() {
		<-ctx.Done()
		shut, cancel := context.WithTimeout(context.WithoutCancel(ctx), drain)
		defer cancel()
		done <- httpd.Shutdown(shut)
	}()
	if err := httpd.Serve(ln); !errors.Is(err, http.ErrServerClosed) {
		return err
	}
	return <-done
}
