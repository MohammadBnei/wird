package api_test

import (
	"encoding/json"
	"net/http"
	"strings"
	"testing"

	"github.com/MohammadBnei/wird/server/internal/store"
)

const sensesPath = "/v1/senses"

func withSenses(t *testing.T) *harness {
	t.Helper()
	h := newHarness(t)
	if err := h.db.ReplaceSenses(t.Context(), []store.Sense{
		{Root: "رحم", En: "to show mercy; the womb", Fr: "faire miséricorde ; la matrice",
			PoeticEn: "the womb and the mercy are one word"},
		{Root: "صبر", En: "to bind oneself; to endure", Fr: "se lier ; endurer"},
	}); err != nil {
		t.Fatalf("seed the senses: %v", err)
	}
	return h
}

func packOf(t *testing.T, body string) map[string]any {
	t.Helper()
	var pack map[string]any
	if err := json.Unmarshal([]byte(body), &pack); err != nil {
		t.Fatalf("the pack is not readable as JSON: %v\n%s", err, body)
	}
	return pack
}

// The bug this route is one mistake away from: every sense answering
// `a bearer token is required`. The app works with no account and voice-follow
// is deliberately reachable without signing in, so requiring sign-in to learn
// what a root means would make the verdict loop unreachable for exactly the
// readers likeliest to need it. An empty token is the whole assertion.
func TestTheSensesAreAskedForABearerTokenTheReaderHasNoAccountFor(t *testing.T) {
	h := withSenses(t)

	w := h.get(t, sensesPath, "")

	if w.Code != http.StatusOK {
		t.Fatalf("answered %d: %s", w.Code, w.Body.String())
	}
}

// The failure: a field is renamed and every phone applies an empty pack, or
// keeps one whose provenance prose it can no longer read. The keys here are the
// contract both halves of this wave were built against, so a rename on this
// side reddens rather than shipping.
func TestThePackIsMissingTheProseThatSaysWhoseReadingItIs(t *testing.T) {
	h := withSenses(t)

	pack := packOf(t, h.get(t, sensesPath, "").Body.String())

	for _, key := range []string{"version", "source", "attribution", "basis", "senses"} {
		if _, ok := pack[key]; !ok {
			t.Errorf("the pack carries no %q", key)
		}
	}
	senses, ok := pack["senses"].([]any)
	if !ok || len(senses) != 2 {
		t.Fatalf("senses came back as %#v", pack["senses"])
	}
	first, ok := senses[0].(map[string]any)
	if !ok {
		t.Fatalf("a sense came back as %#v", senses[0])
	}
	// Sorted by root, and رحم sorts before صبر.
	if first["root"] != "رحم" || first["en"] == "" || first["fr"] == "" {
		t.Errorf("the first sense is %#v", first)
	}
	// The poetic register is gated separately and has its own battery still to
	// write. The struct tag keeps it off the wire; this is the assertion that
	// the tag is still there.
	for _, key := range []string{"poetic_en", "poetic_fr", "PoeticEn"} {
		if _, leaked := first[key]; leaked {
			t.Errorf("the poetic register is served under %q", key)
		}
	}
}

// ADR 0010's one named risk, and the only thing in this package that reaches a
// reader as a false claim rather than as a missing feature. 1,642 machine-written
// drafts are being served and no person has read them; the prose the app draws
// under every one of them has to say so, and has to say what the thumb is for,
// because the reader's verdict is the review.
//
// This test is about the claim, not the wording. Reword the basis freely — but
// if the rewording stops saying that a machine wrote it and nobody checked it,
// or starts sounding like the deleted prose that said each sense was "kept only
// because their glosses bear it out", this is where that gets caught.
func TestTheBasisReadsAsThoughAPersonHadCheckedTheseSenses(t *testing.T) {
	h := withSenses(t)

	basis, _ := packOf(t, h.get(t, sensesPath, "").Body.String())["basis"].(string)

	for _, said := range []string{"machine", "no person", "thumb"} {
		if !strings.Contains(strings.ToLower(basis), said) {
			t.Errorf("the basis never says %q, and a reader has to be told: %q", said, basis)
		}
	}
	for _, claimed := range []string{"bear it out", "lexicon entry", "verified", "scholar's"} {
		if strings.Contains(strings.ToLower(basis), claimed) {
			t.Errorf("the basis claims %q of an unsigned draft: %q", claimed, basis)
		}
	}
}

// The failure: 805 KB moves on every foreground. HEAD is the check and GET is
// the fetch — the reader picks when bytes move — so a HEAD must carry the
// version and no rows, and a phone that already holds that version must be told
// 304 rather than handed the pack again.
func TestTheCheckMovesTheWholePackAndTheReaderNeverChose(t *testing.T) {
	h := withSenses(t)

	got := h.get(t, sensesPath, "")
	version, _ := packOf(t, got.Body.String())["version"].(string)
	etag := got.Header().Get("ETag")
	if etag != `"`+version+`"` {
		t.Fatalf("the ETag is %q where the version is %q, so a phone cannot ask about what it holds", etag, version)
	}
	if !strings.HasPrefix(version, "1-") {
		t.Errorf("the version is %q and does not lead with the provenance revision, so a corrected "+
			"basis reaches no device that already fetched", version)
	}

	head := h.serve(h.request(t, http.MethodHead, sensesPath, ""))
	if head.Code != http.StatusOK {
		t.Fatalf("HEAD answered %d", head.Code)
	}
	if head.Header().Get("ETag") != etag {
		t.Errorf("HEAD says %q where GET says %q", head.Header().Get("ETag"), etag)
	}
	// httptest keeps a HEAD body a real server would drop, which is what makes
	// this assertable: the handler must marshal nothing.
	if head.Body.Len() != 0 {
		t.Errorf("HEAD carried %d bytes, so the check moves the pack", head.Body.Len())
	}

	for _, sent := range []string{etag, version, `W/` + etag, `"nope", ` + etag} {
		r := h.request(t, http.MethodGet, sensesPath, "")
		r.Header.Set("If-None-Match", sent)
		w := h.serve(r)
		if w.Code != http.StatusNotModified {
			t.Errorf("If-None-Match %s answered %d with %d bytes", sent, w.Code, w.Body.Len())
		}
		if w.Body.Len() != 0 {
			t.Errorf("a 304 for %s carried %d bytes", sent, w.Body.Len())
		}
	}

	r := h.request(t, http.MethodGet, sensesPath, "")
	r.Header.Set("If-None-Match", `"1-somethingelse"`)
	if w := h.serve(r); w.Code != http.StatusOK {
		t.Errorf("a phone holding another version answered %d rather than the pack", w.Code)
	}
}

// The failure: a fresh environment, or a --dart-define=WIRD_ORIGIN build pointed
// at an unseeded laptop, reads as a broken route rather than as an empty one.
// "No senses are seeded here" is true and actionable; 404 is neither, and the
// client would have nothing to apply.
func TestAnUnseededServerAnswersTheSensesRouteAsMissing(t *testing.T) {
	h := newHarness(t)

	w := h.get(t, sensesPath, "")

	if w.Code != http.StatusOK {
		t.Fatalf("answered %d: %s", w.Code, w.Body.String())
	}
	pack := packOf(t, w.Body.String())
	if senses, ok := pack["senses"].([]any); !ok || len(senses) != 0 {
		t.Errorf("an unseeded server answered senses %#v, where an empty array is the answer", pack["senses"])
	}
	if pack["version"] == "" || pack["basis"] == "" {
		t.Error("an empty pack carries no version or no basis")
	}
}
