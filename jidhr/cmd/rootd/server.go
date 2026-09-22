package main

import (
	"crypto/subtle"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"math"
	"net"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/MohammadBnei/wird/jidhr/pkg/root"
)

// maxBatchWords caps one batch call. The endpoint is public by design, so an
// uncapped list of words turns a single request into unbounded work.
const maxBatchWords = 100

// maxBodyBytes is generous for a hundred Arabic words and small enough that a
// caller cannot hold memory open by streaming forever.
const maxBodyBytes = 1 << 20

// defaultLangs are the languages jidhr authors meanings in. A caller that names
// none gets both rather than none, because a root with no meaning is not an
// answer anybody asked for.
var defaultLangs = []string{"en", "ar"}

type server struct {
	resolver *root.Resolver
	store    root.Store
	limiter  *limiter
	apiKey   string
	log      *slog.Logger
}

// routes builds the public handler. Health checks sit outside the rate limiter
// and outside authentication: throttling a kubelet probe takes the process down
// for a reason that has nothing to do with the process.
func (s *server) routes() http.Handler {
	api := http.NewServeMux()
	api.HandleFunc("GET /v1/root", s.resolveWord)
	api.HandleFunc("POST /v1/roots:batch", s.resolveBatch)
	api.HandleFunc("GET /v1/roots/{letters}", s.lookupRoot)

	top := http.NewServeMux()
	top.HandleFunc("GET /healthz", func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
	})
	top.Handle("/", s.rateLimited(s.authenticated(api)))
	return top
}

func (s *server) resolveWord(w http.ResponseWriter, r *http.Request) {
	query := r.URL.Query()
	word := strings.TrimSpace(query.Get("word"))
	if word == "" {
		writeError(w, apiError{Status: http.StatusBadRequest, Code: "missing_word",
			Message: "the word parameter is required"})
		return
	}

	res, err := s.resolver.Resolve(r.Context(), word, langsOf(query))
	if err != nil {
		s.writeResolveError(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, res)
}

type batchRequest struct {
	Words []string `json:"words"`
}

// batchItem answers one word of a batch. Exactly one of Result and Error is set,
// so a single unresolvable word reports its own status instead of sinking the
// ninety-nine words beside it.
type batchItem struct {
	Input  string       `json:"input"`
	Result *root.Result `json:"result,omitempty"`
	Error  *apiError    `json:"error,omitempty"`
}

type batchResponse struct {
	Results []batchItem `json:"results"`
}

func (s *server) resolveBatch(w http.ResponseWriter, r *http.Request) {
	r.Body = http.MaxBytesReader(w, r.Body, maxBodyBytes)

	var req batchRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, apiError{Status: http.StatusBadRequest, Code: "bad_body",
			Message: `the request body must be {"words": ["…"]}`})
		return
	}
	if len(req.Words) > maxBatchWords {
		writeError(w, apiError{Status: http.StatusBadRequest, Code: "batch_too_large",
			Message: fmt.Sprintf("a batch carries at most %d words, this one carried %d", maxBatchWords, len(req.Words))})
		return
	}

	langs := langsOf(r.URL.Query())
	items := make([]batchItem, 0, len(req.Words))
	for _, word := range req.Words {
		res, err := s.resolver.Resolve(r.Context(), word, langs)
		if err == nil {
			items = append(items, batchItem{Input: word, Result: &res})
			continue
		}
		fail := apiErrorFor(err)
		// A corpus that is down is not an answer about ninety-nine words. Reporting
		// it per word would hand the caller partial results that look complete.
		if fail.Status == http.StatusInternalServerError {
			s.writeResolveError(w, r, err)
			return
		}
		items = append(items, batchItem{Input: word, Error: &fail})
	}
	writeJSON(w, http.StatusOK, batchResponse{Results: items})
}

// rootResponse is what GET /v1/roots/{letters} returns. It nests root, quran and
// meanings exactly as GET /v1/root does, so one parser reads both.
type rootResponse struct {
	Root     root.Root               `json:"root"`
	Quran    *root.QuranStats        `json:"quran,omitempty"`
	Meanings map[string]root.Meaning `json:"meanings,omitempty"`
}

func (s *server) lookupRoot(w http.ResponseWriter, r *http.Request) {
	letters := strings.TrimSpace(r.PathValue("letters"))
	if !root.ContainsArabicLetter(letters) {
		writeError(w, apiError{Status: http.StatusBadRequest, Code: "not_arabic",
			Message: "the path must carry the joined Arabic letters of a root, such as وصي"})
		return
	}

	rec, err := s.store.Root(r.Context(), letters)
	if errors.Is(err, root.ErrNotFound) {
		writeError(w, apiError{Status: http.StatusNotFound, Code: "no_root",
			Message: fmt.Sprintf("no root %q is recorded", letters)})
		return
	}
	if err != nil {
		s.writeInternal(w, r, "look up a root", err)
		return
	}

	meanings, err := s.store.Meanings(r.Context(), rec.Letters, langsOf(r.URL.Query()))
	if err != nil {
		s.writeInternal(w, r, "read the meanings of a root", err)
		return
	}
	writeJSON(w, http.StatusOK, rootResponse{Root: rec.Root, Quran: rec.Quran, Meanings: meanings})
}

// apiError is the published error body. Status is repeated inside it so a batch
// item can say what its own answer would have been over HTTP.
type apiError struct {
	Status     int      `json:"status"`
	Code       string   `json:"code"`
	Message    string   `json:"message"`
	Candidates []string `json:"candidates,omitempty"`
}

// apiErrorFor maps a resolution failure to its status. Bad input and an
// unresolvable word are different answers: one tells the caller to fix what it
// sent, the other tells it the input was fine and the corpus does not know the
// word. Anything else is our failure and never a statement about the word.
func apiErrorFor(err error) apiError {
	var miss *root.NoRootError
	switch {
	case errors.Is(err, root.ErrNotArabic):
		return apiError{Status: http.StatusBadRequest, Code: "not_arabic",
			Message: "the word is not Arabic"}
	case errors.As(err, &miss):
		return apiError{Status: http.StatusNotFound, Code: "no_root",
			Message:    fmt.Sprintf("no root could be derived for %q", miss.Word),
			Candidates: miss.Candidates}
	case errors.Is(err, root.ErrNoRoot):
		return apiError{Status: http.StatusNotFound, Code: "no_root",
			Message: "no root could be derived"}
	default:
		return apiError{Status: http.StatusInternalServerError, Code: "internal",
			Message: "the root engine could not answer"}
	}
}

func (s *server) writeResolveError(w http.ResponseWriter, r *http.Request, err error) {
	fail := apiErrorFor(err)
	if fail.Status == http.StatusInternalServerError {
		s.writeInternal(w, r, "resolve a word", err)
		return
	}
	writeError(w, fail)
}

// writeInternal keeps the detail in the log and hands the caller an opaque
// status, so a corpus outage never leaks its shape to the outside.
func (s *server) writeInternal(w http.ResponseWriter, r *http.Request, what string, err error) {
	s.log.Error(what, "path", r.URL.Path, "err", err)
	writeError(w, apiError{Status: http.StatusInternalServerError, Code: "internal",
		Message: "the root engine could not answer"})
}

func writeError(w http.ResponseWriter, e apiError) {
	writeJSON(w, e.Status, struct {
		Error apiError `json:"error"`
	}{e})
}

func writeJSON(w http.ResponseWriter, status int, body any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	if err := json.NewEncoder(w).Encode(body); err != nil {
		slog.Error("write a response", "err", err)
	}
}

// langsOf reads lang=en,ar, repeated or comma-separated.
func langsOf(query map[string][]string) []string {
	var langs []string
	for _, value := range query["lang"] {
		for lang := range strings.SplitSeq(value, ",") {
			if lang = strings.TrimSpace(lang); lang != "" {
				langs = append(langs, lang)
			}
		}
	}
	if len(langs) == 0 {
		return defaultLangs
	}
	return langs
}

func (s *server) authenticated(next http.Handler) http.Handler {
	if s.apiKey == "" {
		return next
	}
	want := []byte("Bearer " + s.apiKey)
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		got := []byte(r.Header.Get("Authorization"))
		if subtle.ConstantTimeCompare(got, want) != 1 {
			w.Header().Set("WWW-Authenticate", "Bearer")
			writeError(w, apiError{Status: http.StatusUnauthorized, Code: "unauthorized",
				Message: "a bearer token is required"})
			return
		}
		next.ServeHTTP(w, r)
	})
}

func (s *server) rateLimited(next http.Handler) http.Handler {
	if s.limiter == nil {
		return next
	}
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if !s.limiter.allow(callerOf(r), time.Now()) {
			w.Header().Set("Retry-After", "1")
			writeError(w, apiError{Status: http.StatusTooManyRequests, Code: "rate_limited",
				Message: "too many requests"})
			return
		}
		next.ServeHTTP(w, r)
	})
}

// ponytail: callers are told apart by their address. Behind a proxy every caller
// looks like the proxy, so read a forwarded header here once rootd runs behind
// one we control — trusting that header from the open internet lets anybody
// choose their own bucket.
func callerOf(r *http.Request) string {
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}
	return host
}

// maxTrackedCallers bounds the limiter's memory. Reaching it sweeps the callers
// whose buckets have refilled, which are the ones a fresh bucket would serve
// identically.
const maxTrackedCallers = 10000

// limiter is a token bucket per caller: burst tokens to spend at once, refilled
// at rate tokens a second.
type limiter struct {
	mu      sync.Mutex
	rate    float64
	burst   float64
	buckets map[string]*bucket
}

type bucket struct {
	tokens float64
	seen   time.Time
}

func newLimiter(rate, burst float64) *limiter {
	return &limiter{rate: rate, burst: burst, buckets: map[string]*bucket{}}
}

// ponytail: one mutex over one map. Shard it if rootd ever fronts more requests
// than a single lock can pass through.
func (l *limiter) allow(caller string, now time.Time) bool {
	l.mu.Lock()
	defer l.mu.Unlock()

	b, known := l.buckets[caller]
	if !known {
		if len(l.buckets) >= maxTrackedCallers {
			l.sweep(now)
		}
		b = &bucket{tokens: l.burst, seen: now}
		l.buckets[caller] = b
	}

	b.tokens = math.Min(l.burst, b.tokens+now.Sub(b.seen).Seconds()*l.rate)
	b.seen = now
	if b.tokens < 1 {
		return false
	}
	b.tokens--
	return true
}

func (l *limiter) sweep(now time.Time) {
	for caller, b := range l.buckets {
		if b.tokens+now.Sub(b.seen).Seconds()*l.rate >= l.burst {
			delete(l.buckets, caller)
		}
	}
}
