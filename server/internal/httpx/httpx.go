// Package httpx writes the two response shapes the API has.
package httpx

import (
	"encoding/json"
	"log/slog"
	"net/http"

	"github.com/MohammadBnei/ukubi-go/errs"
)

func JSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	if err := json.NewEncoder(w).Encode(v); err != nil {
		slog.Error("response not written", "err", err)
	}
}

// Error answers with ukubi-go's error body, {code, key, message, source,
// detail}, and the status Connect's table gives code. key is one of
// internal/keys' (a client branches on it); say is what a person reads, and
// only what the caller is allowed to know. Anything the log knows and the
// caller does not stays in the log.
func Error(w http.ResponseWriter, code errs.Code, key errs.Key, say string) {
	errs.Write(w, &errs.Error{Code: code, Key: key, Say: say})
}
