// Package api is the HTTP surface. Handlers stay thin: they validate what came
// off the wire, call the store, and never let an internal reason out.
package api

import (
	"errors"
	"log/slog"
	"net/http"
	"strconv"
	"unicode"

	"github.com/MohammadBnei/wird/server/internal/auth"
	"github.com/MohammadBnei/wird/server/internal/httpx"
	"github.com/MohammadBnei/wird/server/internal/store"
)

type Handler struct {
	store *store.Store
	log   *slog.Logger
}

// Routes wires every endpoint behind the authenticator. /healthz is the one
// thing outside it, because a liveness probe carries no token.
func Routes(s *store.Store, a *auth.Authenticator, log *slog.Logger) http.Handler {
	h := &Handler{store: s, log: log}

	v1 := http.NewServeMux()
	v1.HandleFunc("GET /v1/me", h.me)
	v1.HandleFunc("GET /v1/corpus/version", h.corpusVersion)
	v1.HandleFunc("POST /v1/sync", h.sync)
	v1.HandleFunc("GET /v1/changes", h.changes)
	v1.HandleFunc("GET /v1/progress", h.progress)
	v1.HandleFunc("GET /v1/kept", h.kept)
	v1.HandleFunc("GET /v1/ayahs/{surah}/{ayah}/tafsir", h.tafsir)
	v1.HandleFunc("GET /v1/ayahs/{surah}/{ayah}/irab", h.irab)
	v1.HandleFunc("GET /v1/roots/{letters}/lexicon", h.lexicon)

	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
	})
	mux.Handle("/", a.Middleware(v1))
	return mux
}

func (h *Handler) me(w http.ResponseWriter, r *http.Request) {
	httpx.JSON(w, http.StatusOK, auth.User(r.Context()))
}

func (h *Handler) corpusVersion(w http.ResponseWriter, r *http.Request) {
	version, err := h.store.CorpusVersion(r.Context())
	if err != nil {
		h.fail(w, "corpus version", err)
		return
	}
	httpx.JSON(w, http.StatusOK, version)
}

func (h *Handler) progress(w http.ResponseWriter, r *http.Request) {
	p, err := h.store.Progress(r.Context(), auth.User(r.Context()).ID)
	if err != nil {
		h.fail(w, "progress", err)
		return
	}
	httpx.JSON(w, http.StatusOK, p)
}

var keptKinds = map[string]bool{"": true, "aya": true, "root": true, "note": true}

func (h *Handler) kept(w http.ResponseWriter, r *http.Request) {
	kind := r.URL.Query().Get("kind")
	if !keptKinds[kind] {
		httpx.Error(w, http.StatusBadRequest, "kind must be aya, root or note")
		return
	}
	items, err := h.store.Kept(r.Context(), auth.User(r.Context()).ID, kind)
	if err != nil {
		h.fail(w, "kept", err)
		return
	}
	httpx.JSON(w, http.StatusOK, map[string]any{"items": items})
}

func (h *Handler) tafsir(w http.ResponseWriter, r *http.Request) {
	ayahID, ok := ayahID(w, r)
	if !ok {
		return
	}
	entries, err := h.store.Tafsir(r.Context(), ayahID)
	if err != nil {
		h.fail(w, "tafsir", err)
		return
	}
	httpx.JSON(w, http.StatusOK, map[string]any{"ayah_id": ayahID, "entries": entries})
}

func (h *Handler) irab(w http.ResponseWriter, r *http.Request) {
	ayahID, ok := ayahID(w, r)
	if !ok {
		return
	}
	entries, err := h.store.Irab(r.Context(), ayahID)
	if err != nil {
		h.fail(w, "irab", err)
		return
	}
	httpx.JSON(w, http.StatusOK, map[string]any{"ayah_id": ayahID, "entries": entries})
}

func (h *Handler) lexicon(w http.ResponseWriter, r *http.Request) {
	letters := r.PathValue("letters")
	if !arabicRoot(letters) {
		httpx.Error(w, http.StatusBadRequest, "letters must be the joined Arabic form of a root")
		return
	}
	entries, err := h.store.Lexicon(r.Context(), letters)
	if err != nil {
		h.fail(w, "lexicon", err)
		return
	}
	httpx.JSON(w, http.StatusOK, map[string]any{"root_letters": letters, "entries": entries})
}

// surahs is the count in the muṣḥaf, and an ayah number is 1-based. The pair is
// folded into the corpus's natural key, so a request for 115:1 is refused here
// rather than looked up and answered as an empty aya.
const surahs = 114

func ayahID(w http.ResponseWriter, r *http.Request) (int, bool) {
	surah, errS := strconv.Atoi(r.PathValue("surah"))
	ayah, errA := strconv.Atoi(r.PathValue("ayah"))
	if errS != nil || errA != nil || surah < 1 || surah > surahs || ayah < 1 || ayah > 999 {
		httpx.Error(w, http.StatusBadRequest, "no such aya")
		return 0, false
	}
	return surah*1000 + ayah, true
}

// A root reaches us percent-encoded and comes back decoded. Anything that is
// not Arabic letters is a caller bug, not a missing row, so it is a 400.
func arabicRoot(letters string) bool {
	if letters == "" || len(letters) > 32 {
		return false
	}
	for _, r := range letters {
		if !unicode.Is(unicode.Arabic, r) {
			return false
		}
	}
	return true
}

// fail keeps the reason in the log. The caller learns that the row is not
// there, or that something broke — never which statement or which table.
func (h *Handler) fail(w http.ResponseWriter, what string, err error) {
	if errors.Is(err, store.ErrNotFound) {
		httpx.Error(w, http.StatusNotFound, "nothing here yet")
		return
	}
	h.log.Error(what, "err", err)
	httpx.Error(w, http.StatusInternalServerError, "unavailable")
}
