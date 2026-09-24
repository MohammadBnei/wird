package api

import (
	"html/template"
	"log/slog"
	"net/http"
	"net/url"
)

// Where the identity server sends a reader back to, and the only route besides
// /healthz that answers without a bearer token.
//
// It has to be unauthenticated, and the reason is the whole point of it: the
// reader arrives here holding an authorization code and nothing else. Behind
// the middleware it answered 401, so authentik authenticated a reader, sent
// them here, and the code died on arrival — sign-in could not complete no
// matter how correct both ends were.
//
// The page hands the address back rather than completing anything. Wird is a
// phone app and this is a web page: they share no session, and the code is
// single-use, so a server that redeemed it here would burn it and leave the
// app with nothing. The app's own settings panel takes the address, checks the
// state it minted against the one that comes back, and does the exchange from
// the device.
//
// That becomes invisible once the app claims this URL as an App Link — Android
// verifies /.well-known/assetlinks.json and iOS apple-app-site-association
// against the signing certificate, and the browser hands over without the
// reader seeing this at all. Both need a stable release key, which is why this
// page exists now and why it stays afterwards: a reader whose link verification
// has not run, or who opened the flow on a different device, still gets through.
const callbackPath = "GET /auth/callback"

// The code is a credential. It is shown to the one person holding it and is
// never logged, never stored, and never sent anywhere by this page.
var callbackPage = template.Must(template.New("callback").Parse(`<!doctype html>
<html lang="en"><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="referrer" content="no-referrer">
<title>Wird</title>
<style>
  :root { color-scheme: dark; }
  body { margin:0; background:#161826; color:#e9e7f3;
         font:16px/1.6 -apple-system,BlinkMacSystemFont,"Segoe UI",system-ui,sans-serif;
         display:flex; justify-content:center; }
  main { max-width:34rem; padding:48px 20px 64px; display:flex; flex-direction:column; gap:20px; }
  h1 { font-size:24px; font-weight:600; margin:0; letter-spacing:-0.01em; }
  p { margin:0; color:#b6b3ca; }
  .addr { background:#22253a; border:1px solid #2b2e45; border-radius:8px; padding:13px 15px;
          font-family:ui-monospace,SFMono-Regular,Menlo,monospace; font-size:13px;
          word-break:break-all; color:#b9b0e8; }
  button { font:inherit; font-size:15px; color:#b9b0e8; background:transparent;
           border:1px solid #6f65a8; border-radius:8px; padding:11px 18px; cursor:pointer; }
  button:focus-visible { outline:2px solid #9184d9; outline-offset:2px; }
  .bad { color:#dd9090; }
</style></head>
<body><main>
{{if .Error}}
  <h1>That sign-in did not finish</h1>
  <p class="bad">{{.Error}}</p>
  <p>Nothing has changed on your phone. You can close this and try again from
     Settings.</p>
{{else}}
  <h1>Copy this back into Wird</h1>
  <p>Wird is on your phone and this page is in your browser, so the last step is
     yours: copy the whole address below, open Wird, and paste it where it asks.</p>
  <div class="addr" id="addr">{{.Address}}</div>
  <button id="copy" type="button">Copy the address</button>
  <p>It works once and only in the app that started this sign-in.</p>
{{end}}
</main>
<script>
  var b = document.getElementById('copy');
  if (b) b.onclick = function () {
    navigator.clipboard.writeText(document.getElementById('addr').textContent).then(
      function () { b.textContent = 'Copied'; },
      function () { b.textContent = 'Select it and copy'; });
  };
</script>
</body></html>`))

// authCallback renders what the issuer sent, and does nothing with it.
func authCallback(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()

	// The reader's own address, rebuilt rather than echoed: r.URL carries no
	// scheme or host, and reflecting a caller-supplied Host header would let a
	// link from anywhere put its own domain in front of a reader about to
	// paste it somewhere trusted.
	addr := url.URL{
		Scheme:   "https",
		Host:     "wird.bnei.dev",
		Path:     "/auth/callback",
		RawQuery: r.URL.RawQuery,
	}

	// The sentence this page speaks is one Wird wrote. error_description is
	// written by whoever wrote the link, and a reader in the middle of signing
	// in would read it as Wird's own words on Wird's own domain. OAuth names a
	// small fixed vocabulary in ?error=, which is enough to say what happened;
	// the description goes to the operator instead.
	var fail string
	switch code := q.Get("error"); {
	case code != "":
		d := q.Get("error_description")
		slog.Default().Warn("the issuer refused a sign-in", "error", code,
			"description", d[:min(len(d), 200)])
		fail = "The identity server refused this sign-in."
		if code == "access_denied" {
			fail = "The identity server did not let this sign-in through. An " +
				"account that is new here may not have been given access to Wird yet."
		}
	case q.Get("code") == "":
		fail = "The identity server sent no authorization code."
	}

	// Never cached and never handed to a referrer: this URL is the credential.
	w.Header().Set("Cache-Control", "no-store")
	w.Header().Set("Referrer-Policy", "no-referrer")
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	if fail != "" {
		w.WriteHeader(http.StatusBadRequest)
	}
	_ = callbackPage.Execute(w, struct {
		Error   string
		Address string
	}{Error: fail, Address: addr.String()})
}
