// Package httpx writes the two response shapes the API has.
package httpx

import (
	"encoding/json"
	"log/slog"
	"net/http"
)

func JSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	if err := json.NewEncoder(w).Encode(v); err != nil {
		slog.Error("response not written", "err", err)
	}
}

// Error answers with a reason the caller is allowed to know. Anything the log
// knows and the caller does not stays in the log.
func Error(w http.ResponseWriter, status int, reason string) {
	JSON(w, status, map[string]string{"error": reason})
}
