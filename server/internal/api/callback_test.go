package api_test

import (
	"net/http"
	"strings"
	"testing"
)

// The route the whole sign-in hangs off, and the one nobody registered.
//
// authentik sends a reader here holding an authorization code and no bearer
// token. Every path but /healthz sat behind the auth middleware, so this
// answered `{"error":"a bearer token is required"}` — the reader authenticated,
// the issuer redirected, and the code died on the doorstep. Both ends of the
// flow were correct and sign-in still could not complete. Driven through the
// real router with no token, because "outside the middleware" is the claim.
func TestTheAddressTheIssuerSendsAReaderBackToAsksForATokenTheyCannotHaveYet(t *testing.T) {
	h := newHarness(t)

	w := h.get(t, "/auth/callback?code=abc123&state=xyz", "")

	if w.Code != http.StatusOK {
		t.Fatalf("the callback answered %d: %s", w.Code, w.Body.String())
	}
	body := w.Body.String()
	if !strings.Contains(body, "code=abc123") || !strings.Contains(body, "state=xyz") {
		t.Error("the page does not carry the address back, so the reader has " +
			"nothing to paste into the app that started the sign-in")
	}
}

// The state is what stops a link from anywhere signing a device in as somebody
// else's account, and complete() compares it — so the page has to hand back the
// whole address, not the code alone.
func TestTheCallbackDropsTheStateTheAppWillCheckTheAddressAgainst(t *testing.T) {
	h := newHarness(t)

	w := h.get(t, "/auth/callback?code=abc123&state=the-one-that-was-minted", "")

	if !strings.Contains(w.Body.String(), "the-one-that-was-minted") {
		t.Error("the state did not survive the page, so complete() refuses the " +
			"address as one that did not come from this sign-in")
	}
}

// A reader who is refused at the consent screen arrives with ?error= and no
// code — which is what a reader outside wird-users actually gets. Handing them
// an address to paste sends them to an app that can only reject it.
func TestARefusedSignInIsDrawnAsAnAddressToPasteAnyway(t *testing.T) {
	h := newHarness(t)

	w := h.get(t, "/auth/callback?error=access_denied"+
		"&error_description=Request+has+been+denied", "")

	if w.Code != http.StatusBadRequest {
		t.Errorf("a refused sign-in answered %d", w.Code)
	}
	body := w.Body.String()
	if !strings.Contains(body, "Request has been denied") {
		t.Error("the reader is not told why it failed")
	}
	if strings.Contains(body, "Copy this back into Wird") {
		t.Error("a refusal offers an address to paste, and the app will reject it")
	}
}

// The query is a credential and it is drawn into a page. A page that reflects
// it unescaped hands whoever wrote the link a script running on wird.bnei.dev.
func TestTheCallbackRunsWhateverScriptTheLinkPutInItsQuery(t *testing.T) {
	h := newHarness(t)

	w := h.get(t, "/auth/callback?code=x&state=%3Cscript%3Ealert(1)%3C%2Fscript%3E", "")

	if strings.Contains(w.Body.String(), "<script>alert(1)</script>") {
		t.Error("the state is written into the page unescaped")
	}
}

// An authorization code sitting in a proxy's cache, or handed to the next site
// in a Referer, is a credential left where somebody else can pick it up.
func TestTheCodeIsLeftWhereACacheOrTheNextSiteCanReadIt(t *testing.T) {
	h := newHarness(t)

	w := h.get(t, "/auth/callback?code=abc123&state=xyz", "")

	if got := w.Header().Get("Cache-Control"); got != "no-store" {
		t.Errorf("Cache-Control is %q", got)
	}
	if got := w.Header().Get("Referrer-Policy"); got != "no-referrer" {
		t.Errorf("Referrer-Policy is %q", got)
	}
}
