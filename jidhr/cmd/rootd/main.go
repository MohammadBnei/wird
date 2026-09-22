// Command rootd serves the Arabic root engine over HTTP for callers outside Wird.
package main

import (
	"log/slog"
	"net/http"
	"os"
)

func main() {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
	})

	addr := os.Getenv("ROOTD_ADDR")
	if addr == "" {
		addr = ":8081"
	}
	slog.Info("rootd listening", "addr", addr)
	if err := http.ListenAndServe(addr, mux); err != nil {
		slog.Error("rootd stopped", "err", err)
		os.Exit(1)
	}
}
