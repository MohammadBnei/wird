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
// iOS needs the same thing under a different name: appSiteAssociation below.
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

// iOS's half: the file an iPhone fetches (through Apple's CDN) before it will
// open https://wird.bnei.dev/auth/callback in the app rather than in Safari.
// The app claims the domain with its Associated Domains entitlement; this names
// the app back. The app ID is the paid team's prefix and the bundle id, neither
// of which changes, and neither of which is a secret.
const appSiteAssociationPath = "GET /.well-known/apple-app-site-association"

const appSiteAssociationBody = `{
  "applinks": {
    "details": [
      {
        "appIDs": ["KJYVRCCHU4.dev.bnei.wird"],
        "components": [{"/": "/auth/callback", "comment": "a finished sign-in"}]
      }
    ]
  }
}`

func appSiteAssociation(w http.ResponseWriter, _ *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Cache-Control", "public, max-age=300")
	fmt.Fprint(w, appSiteAssociationBody)
}
