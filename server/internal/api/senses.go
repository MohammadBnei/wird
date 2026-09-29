package api

import (
	"net/http"
	"strconv"
	"strings"

	"github.com/MohammadBnei/wird/server/internal/httpx"
	"github.com/MohammadBnei/wird/server/internal/store"
)

// Where a phone fetches the root senses, and the fifth route — beside
// /healthz, /auth/callback, /.well-known/assetlinks.json and /models/ — that
// answers without a bearer token.
//
// It has to be open for the same reason those do: the app works with no
// account, and requiring sign-in to learn what a root means would make the
// verdict loop unreachable for the readers likeliest to need it
// (docs/adr/0010). It escapes the authenticator by ServeMux specificity —
// registered on the outer mux, above the catch-all that wraps v1 in the
// middleware — and not by any check inside the middleware.
//
// There is no rate limiter in this Go server at all, and this route does not
// add one. The ceiling is the ingress chain — host-wide, bucketed on
// CF-Connecting-IP — which helm/values.yaml:39-45 says is left at the chart's
// defaults on purpose. That chart is infra-bootstrap's common-app-chart and not
// in this repo, so the ceiling is asserted here and verifiable there: grep this
// tree for a limiter and you will find nothing.
//
// Worth saying plainly because ADR 0010 leaned on it to justify leaving the
// route open, and leaned on the wrong precedent: /models/ answers 302 and the
// bytes never come through this server, so whatever protects it transfers
// nothing to an 805 KB body served from here. An unauthenticated request of
// about a hundred bytes gets all of it.
const sensesPath = "GET /v1/senses"

// provenanceRevision is bumped BY HAND when any of the three prose strings
// below changes, and it leads the version a phone compares.
//
// That prefix is not decoration. The prose is served, so a device that already
// holds the pack must learn a corrected basis — and the content hash under it
// moves only when a sense moves. Without the prefix, rewriting the sentence
// that says no person has checked these drafts would reach no installed device,
// which is ADR 0010's one named risk surviving its own fix.
const provenanceRevision = 1

// The three strings a screen puts around a sense: the byline, the long
// attribution, and the line drawn one tap under every sense.
//
// They are constants here rather than a row in Postgres. A single-row table
// nobody remembers to update is the corpus_meta defect this ADR exists to stop
// repeating, and these change when the code that serves them changes.
//
// basis is the one thing in this package that reaches a reader as a false claim
// if it is wrong. 1,642 machine-written drafts are being served, no person has
// read them, and the sentence the app draws under them has to say both of those
// plainly — the prose it replaces claimed the senses were "kept only because
// their glosses bear it out" and "not quoted from any lexicon", of which the
// first was never true of a draft and the second was true and sounded like a
// credential. It also has to say what the thumb is for, because the reader's
// verdict is the review: that is the design, not a shortcut.
const (
	sensesSource = "Wird"

	sensesAttribution = "Wird's own wording, and Wird's alone. These senses are drafts written " +
		"by a language model from each root's own words in the Qur'an, and no person has " +
		"checked them. They are not quoted from, attributed to, or derived from any lexicon or " +
		"scholar, and a sense is a claim about the word, never about a verse. The roots and the " +
		"morphology they are written against are the Quranic Arabic Corpus, which Wird bundles " +
		"rather than serves."

	sensesBasis = "A draft, written by a machine and read by no person. Wird wrote this reading " +
		"from the root's own words in the Qur'an; it is not quoted from any lexicon and carries " +
		"nobody's authority. If it reads wrong to you, say so with the thumb under it — a " +
		"reader's verdict is how a sense gets corrected, and a correction reaches every phone " +
		"without waiting for a release."
)

type sensesBody struct {
	Version     string        `json:"version"`
	Source      string        `json:"source"`
	Attribution string        `json:"attribution"`
	Basis       string        `json:"basis"`
	Senses      []store.Sense `json:"senses"`
}

// senses answers the whole pack, or says it has not changed.
//
// HEAD checks and GET fetches, and the split is the contract rather than an
// optimisation: the reader picks when bytes move, so the check must not move
// 805 KB. HEAD reads no rows and marshals nothing.
//
// It never answers 404. An empty table is a 200 carrying an empty array,
// because "no senses are seeded here" is a true and actionable answer where
// "this route does not exist" is not. store.Senses carries the same note
// against the ErrNotFound convention it is breaking.
//
// Which is why the failures here do not go through h.fail: that helper answers
// 404 on store.ErrNotFound, so the one rule this route has would be broken by a
// store function some later change wraps an ErrNotFound in — silently, and one
// layer away from the comment explaining why it must not.
func (h *Handler) senses(w http.ResponseWriter, r *http.Request) {
	if r.Method == http.MethodHead {
		digest, err := h.store.SensesVersion(r.Context())
		if err != nil {
			h.unavailable(w, "senses version", err)
			return
		}
		if unchanged(w, r, packVersion(digest)) {
			return
		}
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		return
	}

	pack, err := h.store.Senses(r.Context())
	if err != nil {
		h.unavailable(w, "senses", err)
		return
	}
	if unchanged(w, r, packVersion(pack.Version)) {
		return
	}
	// The French travels with the English. Nothing in app/lib reads note_fr
	// today (docs/walkthrough.md:391 records it as a shipped column no screen
	// draws), so this is ~330 KB per fetch into a column no reader can yet
	// reach — said out loud here rather than shipped silently. It stays because
	// both halves of this wave are built against one contract and a locale read
	// is a smaller change than a second pack version.
	httpx.JSON(w, http.StatusOK, sensesBody{
		Version:     packVersion(pack.Version),
		Source:      sensesSource,
		Attribution: sensesAttribution,
		Basis:       sensesBasis,
		Senses:      pack.Senses,
	})
}

// packVersion is the prose revision and the content hash, in that order. A
// phone compares this one string and nothing else.
func packVersion(digest string) string {
	return strconv.Itoa(provenanceRevision) + "-" + digest
}

// unchanged sets the ETag and answers 304 when the caller already holds this
// version. An ETag is a quoted string on the wire; a client echoing it back
// unquoted, weak, or in a list is still asking about the same version, so the
// comparison is lenient about the packaging and exact about the value.
func unchanged(w http.ResponseWriter, r *http.Request, version string) bool {
	w.Header().Set("ETag", `"`+version+`"`)
	for _, tag := range strings.Split(r.Header.Get("If-None-Match"), ",") {
		if strings.Trim(strings.TrimPrefix(strings.TrimSpace(tag), "W/"), `"`) == version {
			w.WriteHeader(http.StatusNotModified)
			return true
		}
	}
	return false
}

// unavailable is h.fail without the 404 branch. The senses route promises it
// never answers 404, and a promise that depends on no store function ever
// wrapping ErrNotFound is not a promise.
func (h *Handler) unavailable(w http.ResponseWriter, what string, err error) {
	h.log.Error(what, "err", err)
	httpx.Error(w, http.StatusInternalServerError, "unavailable")
}
