// Command rootd serves the Arabic root engine over HTTP for callers outside Wird.
package main

import (
	"log/slog"
	"net"
	"net/http"
	"os"
	"strconv"
	"time"

	"github.com/MohammadBnei/wird/jidhr/pkg/root"
)

// burstPerRate turns the one rate knob into a burst, so a caller can spend a few
// seconds of its allowance at once — which is what a page of words looks like —
// without being able to spend a minute of it.
const burstPerRate = 4

func main() {
	log := slog.New(slog.NewJSONHandler(os.Stderr, nil))

	corpusPath := env("ROOTD_CORPUS", "jidhr/testdata/quran.json")
	// ponytail: the whole corpus in memory, read from one JSON file — 1,642 roots,
	// 19,805 attested forms and 523 meanings is about a megabyte. Give the resolver
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

	rate := envFloat(log, "ROOTD_RATE", 5)
	srv := &server{
		resolver: root.New(store),
		store:    store,
		langs:    store.Languages(),
		apiKey:   os.Getenv("ROOTD_API_KEY"),
		log:      log,
	}
	if rate > 0 {
		srv.limiter = newLimiter(rate, rate*burstPerRate)
	}

	addr := env("ROOTD_ADDR", ":8081")
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
		"authenticated", srv.apiKey != "", "rate_per_second", rate)
	if err := httpd.Serve(ln); err != nil {
		log.Error("rootd stopped", "err", err)
		os.Exit(1)
	}
}

func env(name, fallback string) string {
	if v := os.Getenv(name); v != "" {
		return v
	}
	return fallback
}

func envFloat(log *slog.Logger, name string, fallback float64) float64 {
	raw := os.Getenv(name)
	if raw == "" {
		return fallback
	}
	v, err := strconv.ParseFloat(raw, 64)
	if err != nil {
		log.Warn("ignoring an unreadable setting", "name", name, "value", raw, "using", fallback)
		return fallback
	}
	return v
}
