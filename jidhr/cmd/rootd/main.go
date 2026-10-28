// Command rootd serves the Arabic root engine over HTTP for callers outside Wird.
package main

import (
	"log/slog"
	"net"
	"net/http"
	"os"
	"time"

	"github.com/MohammadBnei/wird/jidhr/pkg/root"
)

// burstPerRate turns the one rate knob into a burst, so a caller can spend a few
// seconds of its allowance at once — which is what a page of words looks like —
// without being able to spend a minute of it.
const burstPerRate = 4

func main() {
	log := slog.New(slog.NewJSONHandler(os.Stderr, nil))

	// Every problem with the configuration at once, before anything is opened.
	cfg, err := fromProcess()
	if err != nil {
		log.Error("config refused", "err", err)
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
	}

	// Bind before announcing it. Logging the line first means a port already in
	// use prints a confident "listening" and then the error that it never did.
	ln, err := net.Listen("tcp", addr)
	if err != nil {
		log.Error("listen", "addr", addr, "err", err)
		os.Exit(1)
	}

	log.Info("rootd listening",
		"addr", ln.Addr().String(), "corpus", corpusPath, "languages", srv.langs,
		"authenticated", srv.apiKey != "", "rate_per_second", rate, "dev", cfg.Dev)
	if err := httpd.Serve(ln); err != nil {
		log.Error("rootd stopped", "err", err)
		os.Exit(1)
	}
}
