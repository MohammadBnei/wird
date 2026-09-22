// Command api serves Wird user state to the Flutter client.
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

	addr := os.Getenv("API_ADDR")
	if addr == "" {
		addr = ":8080"
	}
	slog.Info("wird-api listening", "addr", addr)
	if err := http.ListenAndServe(addr, mux); err != nil {
		slog.Error("wird-api stopped", "err", err)
		os.Exit(1)
	}
}
