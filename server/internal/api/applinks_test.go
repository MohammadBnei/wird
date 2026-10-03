package api_test

import (
	"encoding/json"
	"net/http"
	"testing"
)

const testFingerprint = "45:85:EA:58:05:B0:DC:C7:86:E1:2C:12:A0:5A:59:80:" +
	"7B:8C:0C:D2:CC:6D:7B:34:14:C2:CC:24:8C:22:F2:5E"

// Without this file Android will not treat /auth/callback as Wird's link, so
// the browser keeps it and the reader is left copying an authorization code out
// of a web page by hand — which is what a reader actually had to do.
//
// The platform fetches it, not a signed-in reader, so it has to answer without
// a bearer token like /healthz and /auth/callback do.
func TestAndroidCannotVerifyTheLinkBecauseNothingServesTheAssetLinks(t *testing.T) {
	t.Setenv("WIRD_ANDROID_SHA256", testFingerprint)
	h := newHarness(t)

	w := h.get(t, "/.well-known/assetlinks.json", "")

	if w.Code != http.StatusOK {
		t.Fatalf("answered %d: %s", w.Code, w.Body.String())
	}

	var got []struct {
		Relation []string `json:"relation"`
		Target   struct {
			Namespace    string   `json:"namespace"`
			Package      string   `json:"package_name"`
			Fingerprints []string `json:"sha256_cert_fingerprints"`
		} `json:"target"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &got); err != nil {
		t.Fatalf("Android parses this as JSON and it is not: %v", err)
	}
	if len(got) != 1 {
		t.Fatalf("%d statements", len(got))
	}
	if got[0].Target.Package != "dev.bnei.wird" {
		t.Errorf("package is %q, so the statement is about another app",
			got[0].Target.Package)
	}
	if len(got[0].Target.Fingerprints) != 1 ||
		got[0].Target.Fingerprints[0] != testFingerprint {
		t.Errorf("fingerprints are %v", got[0].Target.Fingerprints)
	}
	if len(got[0].Relation) != 1 ||
		got[0].Relation[0] != "delegate_permission/common.handle_all_urls" {
		t.Errorf("relation is %v, and Android needs handle_all_urls to open a link",
			got[0].Relation)
	}
}

// A release key and a test key are different certificates, and a reader may
// hold either. Dropping one silently unverifies that build's links.
func TestOnlyOneSigningKeyCanEverVerifyTheLink(t *testing.T) {
	t.Setenv("WIRD_ANDROID_SHA256", testFingerprint+" , AA:BB")
	h := newHarness(t)

	var got []struct {
		Target struct {
			Fingerprints []string `json:"sha256_cert_fingerprints"`
		} `json:"target"`
	}
	w := h.get(t, "/.well-known/assetlinks.json", "")
	if err := json.Unmarshal(w.Body.Bytes(), &got); err != nil {
		t.Fatalf("not JSON: %v — %s", err, w.Body.String())
	}
	if len(got[0].Target.Fingerprints) != 2 {
		t.Errorf("a second key was dropped: %v", got[0].Target.Fingerprints)
	}
	if got[0].Target.Fingerprints[1] != "AA:BB" {
		t.Errorf("the surrounding spaces were kept: %q",
			got[0].Target.Fingerprints[1])
	}
}

// A statement granting nothing reads to Android exactly like one that was
// never written, and pretending to have an answer hides a missing deployment
// variable behind a link that quietly never verifies.
func TestAnUnconfiguredDeploymentPublishesAStatementThatGrantsNobody(t *testing.T) {
	t.Setenv("WIRD_ANDROID_SHA256", "")
	h := newHarness(t)

	if w := h.get(t, "/.well-known/assetlinks.json", ""); w.Code != http.StatusNotFound {
		t.Errorf("answered %d: %s", w.Code, w.Body.String())
	}
}

// Without it an iPhone opens the sign-in callback in Safari and the reader is
// left pasting the address back by hand. Fetched by Apple, never with a token.
func TestTheIPhoneCannotVerifyTheSignInLink(t *testing.T) {
	h := newHarness(t)

	w := h.get(t, "/.well-known/apple-app-site-association", "")

	if w.Code != http.StatusOK {
		t.Fatalf("answered %d: %s", w.Code, w.Body.String())
	}
	if ct := w.Header().Get("Content-Type"); ct != "application/json" {
		t.Errorf("Content-Type is %q; Apple wants application/json", ct)
	}
	var got struct {
		Applinks struct {
			Details []struct {
				AppIDs     []string            `json:"appIDs"`
				Components []map[string]string `json:"components"`
			} `json:"details"`
		} `json:"applinks"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &got); err != nil {
		t.Fatalf("Apple parses this as JSON and it is not: %v", err)
	}
	d := got.Applinks.Details
	if len(d) != 1 || len(d[0].AppIDs) != 1 || d[0].AppIDs[0] != "KJYVRCCHU4.dev.bnei.wird" {
		t.Fatalf("names %+v, not Wird", d)
	}
	if len(d[0].Components) != 1 || d[0].Components[0]["/"] != "/auth/callback" {
		t.Fatalf("claims %+v, not the sign-in callback", d[0].Components)
	}
}
