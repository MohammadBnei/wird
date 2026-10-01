package api_test

import (
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"
)

// Somebody arriving at wird.bnei.dev has no account and no app yet. Before the
// page existed every path fell to the authenticator and the host's front door
// answered `a bearer token is required`.
func TestThePublicPageAsksForATokenNobodyArrivingHasYet(t *testing.T) {
	h := newHarness(t)

	w := h.get(t, "/", "")

	if w.Code != http.StatusOK {
		t.Fatalf("answered %d: %s", w.Code, w.Body.String())
	}
	if ct := w.Header().Get("Content-Type"); !strings.HasPrefix(ct, "text/html") {
		t.Errorf("Content-Type is %q", ct)
	}
	if !strings.Contains(w.Body.String(), "وِرْد") {
		t.Error("the page is not Wird's")
	}
}

// The page is a shell: its look is the design system's stylesheet under _ds/,
// and its demos are fetched by name, spaces and all. Any one of them missing
// renders an unstyled page or an empty phone, and the page itself still 200s.
func TestThePageArrivesWithoutTheFilesItRendersFrom(t *testing.T) {
	h := newHarness(t)

	for _, path := range []string{
		"/_ds/nocturne-f1420674-3c74-41e9-8af5-2fa684fcd021/styles.css",
		"/_ds/nocturne-f1420674-3c74-41e9-8af5-2fa684fcd021/_ds_bundle.js",
		"/" + url.PathEscape("Wird Reader") + ".dc.html",
		"/" + url.PathEscape("Wird Prayer") + ".dc.html",
		"/support.js", "/android-frame.jsx", "/site-data.js", "/wird-icon.svg",
	} {
		if w := h.get(t, path, ""); w.Code != http.StatusOK {
			t.Errorf("%s answered %d", path, w.Code)
		}
	}
}

// Embedded files have no modification time, so without this a cache keeps an
// old script beside a new page after a deploy, and the demo breaks for as long
// as the edge decides.
func TestANewPageIsServedBesideAnOldScript(t *testing.T) {
	h := newHarness(t)

	if got := h.get(t, "/support.js", "").Header().Get("Cache-Control"); got != "no-cache" {
		t.Errorf("Cache-Control is %q", got)
	}
}

// The page's patterns sit in the same mux as the API's open routes and in front
// of the authenticator. Matching too much would answer /healthz with a file
// listing or let a request past the token check.
func TestThePageSwallowsTheRoutesBesideIt(t *testing.T) {
	h := newHarness(t)

	if w := h.get(t, "/healthz", ""); w.Code != http.StatusOK || w.Body.Len() != 0 {
		t.Errorf("/healthz answered %d with %q", w.Code, w.Body.String())
	}
	if w := h.get(t, "/v1/me", ""); w.Code != http.StatusUnauthorized {
		t.Errorf("/v1/me without a token answered %d", w.Code)
	}
	if w := h.get(t, "/auth/callback?code=x&state=y", ""); strings.Contains(w.Body.String(), "<x-dc>") {
		t.Error("/auth/callback answered with the public page")
	}
}

// Without a published build the button has nothing to hand out, and it must
// say so rather than redirect to a key the store does not hold.
func TestTheDownloadButtonRedirectsToABuildNobodyPublished(t *testing.T) {
	h := withStore(t)

	if w := h.get(t, "/download/android", ""); w.Code != http.StatusServiceUnavailable {
		t.Errorf("answered %d: %s", w.Code, w.Body.String())
	}
}

// A published build is fetched from the store, signed, never through this
// process, and never from a cached redirect whose signature has died.
func TestTheDownloadButtonServesTheApkThroughTheApi(t *testing.T) {
	const key = "android/wird-3f2a9c.apk"
	t.Setenv("WIRD_APK_KEY", key)
	h := withStore(t)

	w := h.get(t, "/download/android", "")

	if w.Code != http.StatusFound {
		t.Fatalf("answered %d: %s", w.Code, w.Body.String())
	}
	to, err := url.Parse(w.Header().Get("Location"))
	if err != nil || to.Host != "s3.bnei.dev" || to.Query().Get("X-Amz-Signature") == "" {
		t.Fatalf("Location is %q", w.Header().Get("Location"))
	}
	if !strings.Contains(to.Path, "wird-3f2a9c.apk") {
		t.Errorf("signed %s, not the published build", to.Path)
	}
	if got := w.Header().Get("Cache-Control"); got != "no-store" {
		t.Errorf("Cache-Control is %q", got)
	}
}

// The page asks with HEAD before it sends the browser anywhere, and shows a
// notice instead of a bare 503 page when nothing is published. A HEAD that
// redirected while GET did not, or the reverse, would send a visitor to the
// error page the check exists to spare them.
func TestThePageCheckAndTheDownloadDisagree(t *testing.T) {
	head := func(h *harness) int {
		w := httptest.NewRecorder()
		h.routes.ServeHTTP(w, httptest.NewRequest(http.MethodHead, "/download/android", nil))
		return w.Code
	}

	if got := head(withStore(t)); got != http.StatusServiceUnavailable {
		t.Errorf("unpublished: HEAD answered %d", got)
	}
	t.Setenv("WIRD_APK_KEY", "android/wird-3f2a9c.apk")
	if got := head(withStore(t)); got != http.StatusFound {
		t.Errorf("published: HEAD answered %d", got)
	}
}
