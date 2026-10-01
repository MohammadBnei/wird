package api_test

import (
	"net/http"
	"net/url"
	"strings"
	"testing"
)

const (
	modelKey  = "base-ar-quran/38853d7df20b/quran-tokens.txt"
	modelPath = "/models/" + modelKey
)

func withStore(t *testing.T) *harness {
	t.Helper()
	t.Setenv("WIRD_MODELS_S3_BUCKET", "wird-models")
	t.Setenv("WIRD_MODELS_S3_ENDPOINT", "https://s3.bnei.dev")
	t.Setenv("WIRD_MODELS_S3_ACCESS_KEY", "GKtest")
	t.Setenv("WIRD_MODELS_S3_SECRET", "secrettest")
	return newHarness(t)
}

// The bug a reader actually hit: every model file answered
// `a bearer token is required`. Voice-follow is available to somebody who has
// never signed in, so the phone fetching 160 MB holds no token and never
// will — the route has to answer without one, like /healthz and
// /auth/callback.
func TestTheRecogniserIsAskedForABearerTokenThePhoneCannotHave(t *testing.T) {
	h := withStore(t)

	w := h.get(t, modelPath, "")

	if w.Code != http.StatusFound {
		t.Fatalf("answered %d: %s", w.Code, w.Body.String())
	}
}

// 160 MB per reader through a pod sized for JSON is an outage, not a feature,
// and the store's own route carries no rate limit while this one does. The
// answer is a redirect; the bytes must never enter this process.
func TestTheModelIsStreamedThroughTheApiInsteadOfRedirectedTo(t *testing.T) {
	h := withStore(t)

	w := h.get(t, modelPath, "")

	if w.Body.Len() > 512 {
		t.Errorf("the body is %d bytes, so this is serving the file", w.Body.Len())
	}
	to, err := url.Parse(w.Header().Get("Location"))
	if err != nil || to.Host != "s3.bnei.dev" {
		t.Fatalf("Location is %q", w.Header().Get("Location"))
	}
	if to.Query().Get("X-Amz-Signature") == "" {
		t.Error("the redirect is unsigned, so the store refuses it")
	}
	if !strings.HasPrefix(to.Path, "/wird-models/") {
		t.Errorf("not path-style: %s — a bucket subdomain has no certificate", to.Path)
	}
}

// A signed URL expires. A cached 302 does not, so a reader resuming tomorrow
// would be handed a signature that died today.
func TestTheRedirectIsCachedAndOutlivesTheSignatureInIt(t *testing.T) {
	h := withStore(t)

	if got := h.get(t, modelPath, "").Header().Get("Cache-Control"); got != "no-store" {
		t.Errorf("Cache-Control is %q", got)
	}
}

// A key that climbs out of the prefix gets a signature for an object this
// route was never meant to hand out.
//
// ServeMux cleans the path and redirects before the handler sees it, so the
// guard in serve() is a second line rather than the first — which is worth
// knowing, because the first line is somebody else's code and this asserts
// the property rather than the mechanism: no traversal is ever answered with
// a signed URL.
func TestAKeyCanClimbOutOfTheModelsPrefix(t *testing.T) {
	h := withStore(t)

	for _, key := range []string{
		"../wird-models-private/secret",
		"a/../../b",
		"%2E%2E/%2E%2E/elsewhere",
	} {
		w := h.get(t, "/models/"+key, "")
		if w.Code == http.StatusFound {
			t.Errorf("%q was signed: %s", key, w.Header().Get("Location"))
		}
	}
}

// An empty key is a request for the prefix itself, which is not an object.
func TestThePrefixItselfIsSignedAsThoughItWereAFile(t *testing.T) {
	h := withStore(t)

	if w := h.get(t, "/models/", ""); w.Code != http.StatusNotFound {
		t.Errorf("answered %d", w.Code)
	}
}

// Every local run, and any deployment whose secret has not arrived. The
// reader's phone is fine and the file is not missing, so this must not be a
// 404 — the client turns it into "the recogniser cannot be fetched" rather
// than anything that reads as the reader's own fault.
func TestADeploymentWithNoStoreTellsTheReaderTheirFileIsMissing(t *testing.T) {
	t.Setenv("WIRD_MODELS_S3_BUCKET", "")
	t.Setenv("WIRD_MODELS_S3_ENDPOINT", "")
	t.Setenv("WIRD_MODELS_S3_ACCESS_KEY", "")
	t.Setenv("WIRD_MODELS_S3_SECRET", "")
	h := newHarness(t)

	w := h.get(t, modelPath, "")

	if w.Code != http.StatusServiceUnavailable {
		t.Errorf("answered %d, and 404 would say the file does not exist", w.Code)
	}
}

// The reader's own Range travels on their own request to the store. This
// route must not read it, answer it, or consume it.
func TestTheApiAnswersTheRangeItselfAndBreaksTheResume(t *testing.T) {
	h := withStore(t)

	r := h.request(t, http.MethodGet, modelPath, "")
	r.Header.Set("Range", "bytes=1000-")
	w := h.serve(r)

	if w.Code != http.StatusFound {
		t.Errorf("a ranged request answered %d rather than redirecting", w.Code)
	}
	if w.Header().Get("Content-Range") != "" {
		t.Error("this route answered the range itself")
	}
}
