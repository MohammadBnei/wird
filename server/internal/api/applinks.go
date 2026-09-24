package api

import (
	"fmt"
	"net/http"
	"os"
	"strings"
)

// What makes the browser hand a finished sign-in straight back to the app
// instead of leaving the reader to copy an address out of a web page.
//
// The manifest already claims https://wird.bnei.dev/auth/callback with
// android:autoVerify, which makes Android fetch this file and compare the
// fingerprints in it against the certificate the installed app is signed with.
// Until it is served, verification fails, the link stays an ordinary web link,
// and /auth/callback renders its copy-this-back page — which works, and which
// nobody would choose.
//
// WIRD_ANDROID_SHA256 holds the fingerprints, comma-separated, because the
// answer changes with the key: a debug keystore is per-machine, and a release
// keystore is a different certificate again. Listing more than one lets a
// release build and a test build both verify, which is the whole reason the
// format takes an array. A fingerprint is not a secret — it is readable from
// any installed app — so it lives in configuration rather than a secret store.
//
// Unset means unset: this answers 404 rather than an empty statement, because
// an assetlinks file that grants nothing is indistinguishable to Android from
// one that has not been written yet, and the 404 is the honest one.
//
// iOS needs the same thing under a different name — apple-app-site-association,
// with an Associated Domains entitlement that a personal team cannot hold. That
// is why sign-in on the iPhone stays the paste-back path for now.
const assetLinksPath = "GET /.well-known/assetlinks.json"

func assetLinks(w http.ResponseWriter, r *http.Request) {
	raw := strings.TrimSpace(os.Getenv("WIRD_ANDROID_SHA256"))
	if raw == "" {
		http.NotFound(w, r)
		return
	}

	var quoted []string
	for _, f := range strings.Split(raw, ",") {
		if f = strings.TrimSpace(f); f != "" {
			quoted = append(quoted, fmt.Sprintf("%q", f))
		}
	}
	if len(quoted) == 0 {
		http.NotFound(w, r)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	// Android re-checks this periodically and a stale answer silently unverifies
	// a link that used to work, so it is cached briefly rather than indefinitely.
	w.Header().Set("Cache-Control", "public, max-age=300")
	fmt.Fprintf(w, `[{
  "relation": ["delegate_permission/common.handle_all_urls"],
  "target": {
    "namespace": "android_app",
    "package_name": "dev.bnei.wird",
    "sha256_cert_fingerprints": [%s]
  }
}]`, strings.Join(quoted, ", "))
}
