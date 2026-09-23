package api

import (
	"encoding/json"
	"errors"
	"net/http"

	"github.com/MohammadBnei/wird/server/internal/auth"
	"github.com/MohammadBnei/wird/server/internal/httpx"
	"github.com/MohammadBnei/wird/server/internal/store"
)

// A batch bigger than this is refused whole: the device queues its own writes
// and has no reason to send more than a reconnect's worth at a time.
const maxOpsPerBatch = 500

// One megabyte of ops, so a device that has gone wrong cannot make the server
// read an unbounded body into memory.
const maxSyncBody = 1 << 20

// sync is the one write path. Everything a reader does reaches the server
// here, online or not, so a write that timed out after it landed is replayed
// onto its own op id instead of counted twice.
//
// The answer is per-op. The batch itself only fails when it is unreadable:
// one op the server will never accept must not hold the other nineteen behind
// it on every reconnect until the reader loses them.
func (h *Handler) sync(w http.ResponseWriter, r *http.Request) {
	var batch struct {
		Ops []store.Op `json:"ops"`
	}
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, maxSyncBody)).Decode(&batch); err != nil {
		httpx.Error(w, http.StatusBadRequest, "the batch is not readable")
		return
	}
	if len(batch.Ops) > maxOpsPerBatch {
		httpx.Error(w, http.StatusBadRequest, "too many ops in one batch")
		return
	}
	results, err := h.store.Apply(r.Context(), auth.User(r.Context()).ID, batch.Ops)
	if err != nil {
		h.fail(w, "sync", err)
		return
	}
	httpx.JSON(w, http.StatusOK, map[string]any{"results": results})
}

// changes is the pull half: rows and tombstones since the cursor the device
// last held, plus the cursor to ask with next time.
func (h *Handler) changes(w http.ResponseWriter, r *http.Request) {
	changes, err := h.store.Changes(r.Context(), auth.User(r.Context()).ID, r.URL.Query().Get("since"))
	if errors.Is(err, store.ErrBadCursor) {
		httpx.Error(w, http.StatusBadRequest, "that is not a cursor this server issued")
		return
	}
	if err != nil {
		h.fail(w, "changes", err)
		return
	}
	httpx.JSON(w, http.StatusOK, changes)
}
