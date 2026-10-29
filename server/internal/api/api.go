// Package api is the HTTP surface. Handlers stay thin: they validate what came
// off the wire, call the store, and never let an internal reason out.
package api

import (
	"errors"
	"log/slog"
	"net/http"
	"strconv"
	"unicode"

	"github.com/MohammadBnei/ukubi-go/errs"
	"github.com/MohammadBnei/ukubi-go/telemetry"
	"github.com/MohammadBnei/wird/server/internal/auth"
	"github.com/MohammadBnei/wird/server/internal/httpx"
	"github.com/MohammadBnei/wird/server/internal/keys"
	"github.com/MohammadBnei/wird/server/internal/site"
	"github.com/MohammadBnei/wird/server/internal/store"
)

type Handler struct {
	store *store.Store
	log   *slog.Logger
}

// Config is what the open routes serve from. cmd/api builds it once at start
// from the environment (server/cmd/api/config.go), so nothing in this package
// reads the environment, at start or on a request.
type Config struct {
	// Models is the store /models/ and /download/android presign against.
	// Nil means no store: both answer 503.
	Models *Models
	// APKKey is the object /download/android redirects to; empty answers 503.
	APKKey string
	// APKVersion is the release APKKey is; empty answers 204.
	APKVersion string
	// AndroidSHA256 is the signing-key fingerprints, comma-separated, as the
	// deployment writes them; parsed once in Routes. Empty answers 404.
	AndroidSHA256 string
}

// Models is the S3 store the recogniser and the APK live in. Region empty
// means Garage's.
type Models struct {
	Bucket, Endpoint, AccessKey, Secret, Region string
}

// gated is every route behind the authenticator. Routes registers each one
// twice from this one table: on v1, which is the only place a handler is
// reached, and on the outer mux as the same gate over v1, so that its span is
// named by its pattern and sits outside the gate (docs/adr/0040).
func (h *Handler) gated() []route {
	return []route{
		{"GET /v1/me", h.me},
		{"DELETE /v1/me", h.deleteMe},
		{"GET /v1/corpus/version", h.corpusVersion},
		{"POST /v1/sync", h.sync},
		{"GET /v1/changes", h.changes},
		{"GET /v1/progress", h.progress},
		{"GET /v1/kept", h.kept},
		{"GET /v1/ayahs/{surah}/{ayah}/tafsir", h.tafsir},
		{"GET /v1/ayahs/{surah}/{ayah}/irab", h.irab},
		{"GET /v1/roots/{letters}/lexicon", h.lexicon},
	}
}

type route struct {
	pattern string
	handler http.HandlerFunc
}

// Routes wires every endpoint behind the authenticator, except the few that are
// reached without an account: each open route below says why it is open. Every
// route but /healthz gets a span from t; a nil or inert t adds nothing.
func Routes(s *store.Store, a *auth.Authenticator, log *slog.Logger, c Config, t *telemetry.Tracing) http.Handler {
	h := &Handler{store: s, log: log}

	v1 := http.NewServeMux()
	for _, r := range h.gated() {
		v1.HandleFunc(r.pattern, r.handler)
	}

	mux := http.NewServeMux()
	handle := func(pattern string, h http.Handler) { mux.Handle(pattern, t.Handler(pattern, h)) }
	// Untraced: a probe every few seconds is noise, not a request.
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
	})
	// Beside /healthz and for the same reason: a reader arriving from the
	// identity server holds an authorization code and no bearer token, so
	// behind the middleware this answered 401 and sign-in could never finish.
	handle(callbackPath, http.HandlerFunc(authCallback))
	// Android fetches this before it will treat /auth/callback as this app's
	// link, and it is fetched by the platform rather than by a signed-in reader.
	handle(assetLinksPath, assetLinks(c.AndroidSHA256))
	handle(appSiteAssociationPath, http.HandlerFunc(appSiteAssociation))
	// The recogniser, fetched by a phone that has never signed in and never
	// needs to. It answers 302 to the store and the bytes never come through
	// here; without a store configured it says so rather than pretending the
	// file is missing.
	models := newModelStore(c.Models, log)
	if models != nil {
		handle(modelsPath, http.HandlerFunc(models.serve))
	} else {
		handle(modelsPath, http.HandlerFunc(modelsNotConfigured))
	}
	// The app itself, from the same store, for the public page's Download
	// buttons. apk.go carries why the key is configured rather than fixed.
	handle(apkPath, apk(models, c.APKKey, log))
	handle(apkVersionPath, apkVersion(c.APKVersion))
	// The senses, fetched by a phone that has never signed in. Open for the
	// same reason as the recogniser, and registered here rather than on v1 so
	// ServeMux specificity keeps it out of the middleware. senses.go carries
	// the whole of why.
	handle(sensesPath, http.HandlerFunc(h.senses))
	// The public page, for someone who has not installed anything. Its files
	// are one path segment deep (or under _ds/), and every API route is two or
	// more, so these patterns cannot reach v1; /healthz is matched exactly and
	// wins over {file}.
	page := site.Handler()
	handle("GET /{$}", page)
	handle("GET /{file}", page)
	handle("GET /_ds/", page)
	// One gate, over v1. Each gated pattern is also on this mux, as this same
	// gate under a span; anything else (another method, a path no route
	// takes) falls through to "/" untraced, and v1 answers its 404 or 405
	// after the gate, as it always has.
	gate := a.Middleware(v1)
	for _, r := range h.gated() {
		handle(r.pattern, gate)
	}
	mux.Handle("/", gate)
	return mux
}

func (h *Handler) me(w http.ResponseWriter, r *http.Request) {
	httpx.JSON(w, http.StatusOK, auth.User(r.Context()))
}

// deleteMe is the store requirement that a reader can delete their account from
// inside the app. Everything they own goes with the users row; the identity
// itself is the bnei.dev sign-in, which is not ours to delete.
func (h *Handler) deleteMe(w http.ResponseWriter, r *http.Request) {
	if err := h.store.DeleteReader(r.Context(), auth.User(r.Context()).OIDCSubject); err != nil {
		h.fail(w, r, "delete reader", err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (h *Handler) corpusVersion(w http.ResponseWriter, r *http.Request) {
	version, err := h.store.CorpusVersion(r.Context())
	if err != nil {
		h.fail(w, r, "corpus version", err)
		return
	}
	httpx.JSON(w, http.StatusOK, version)
}

func (h *Handler) progress(w http.ResponseWriter, r *http.Request) {
	p, err := h.store.Progress(r.Context(), auth.User(r.Context()).ID)
	if err != nil {
		h.fail(w, r, "progress", err)
		return
	}
	httpx.JSON(w, http.StatusOK, p)
}

var keptKinds = map[string]bool{"": true, "aya": true, "root": true, "note": true}

func (h *Handler) kept(w http.ResponseWriter, r *http.Request) {
	kind := r.URL.Query().Get("kind")
	if !keptKinds[kind] {
		httpx.Error(w, errs.InvalidArgument, keys.BadKind, "kind must be aya, root or note")
		return
	}
	items, err := h.store.Kept(r.Context(), auth.User(r.Context()).ID, kind)
	if err != nil {
		h.fail(w, r, "kept", err)
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
		h.fail(w, r, "tafsir", err)
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
		h.fail(w, r, "irab", err)
		return
	}
	httpx.JSON(w, http.StatusOK, map[string]any{"ayah_id": ayahID, "entries": entries})
}

func (h *Handler) lexicon(w http.ResponseWriter, r *http.Request) {
	letters := r.PathValue("letters")
	if !arabicRoot(letters) {
		httpx.Error(w, errs.InvalidArgument, keys.BadRoot, "letters must be the joined Arabic form of a root")
		return
	}
	entries, err := h.store.Lexicon(r.Context(), letters)
	if err != nil {
		h.fail(w, r, "lexicon", err)
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
		httpx.Error(w, errs.InvalidArgument, keys.BadAyah, "no such aya")
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
func (h *Handler) fail(w http.ResponseWriter, r *http.Request, what string, err error) {
	if errors.Is(err, store.ErrNotFound) {
		httpx.Error(w, errs.NotFound, keys.NotFound, "nothing here yet")
		return
	}
	httpx.Failed(r, h.log, what, "err", err)
	httpx.Error(w, errs.Internal, errs.KeyInternal, "unavailable")
}
