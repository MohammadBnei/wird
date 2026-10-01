# 18. The public page is embedded in wird-api, and its demos run on the corpus

Date: 2026-10-01. Status: accepted. Amends ADR 0005.

## Context

`https://wird.bnei.dev/` answered `a bearer token is required`: every path the
API did not know fell to the authenticator ([api.go](../../server/internal/api/api.go#L77)).
Wird had no page that says what it is, and no way to get the Android app
without a cable.

The design project has a landing page, `Wird Site.dc.html`, with two live
demos (`Wird Reader`, `Wird Prayer`). Claude Design's runtime renders them in
the browser. It loads React, ReactDOM and Babel from unpkg, and fetches each
demo as `./<name>.dc.html`. The demos came with hand-typed Qur'an text and
invented scholarship: senses, form notes, verse notes, related roots and counts
that the mockup itself called "my own summaries".

ADR 0005 keeps one image and one workload. ADR 0008 serves large files from
the models bucket by a 302, under a key that names the file's digest.

## Decision

- The page is embedded in wird-api (`server/internal/site`, `//go:embed all:static`).
  It is served at `GET /`, `GET /{file}` and `GET /_ds/`, with `Cache-Control: no-cache`.
- The design runtime, the device frame and the Nocturne files are kept
  verbatim. `index.html` and the two demos are Wird's adaptations, and the
  site's README lists every change.
- The demos read `site-data.js`, which `scripts/site-data.py` writes from
  `corpus.db` and the sense drafts. Anything Wird has no source for is
  removed, never filled in: which sense applies here, the form label and its
  note, the verse note, and related roots. Senses carry the same "machine
  draft" basis the app shows.
- `GET /download/android` redirects to the APK in the models bucket. Its key
  comes from `WIRD_APK_KEY` and names the build's digest, as ADR 0008 does
  for the model. The APK is signed with the release key, whose fingerprint
  `WIRD_ANDROID_SHA256` lists.

## Alternatives

- **A second deployment for the page** (nginx or a static host). It would be
  one more workload, ingress and image, all for about 250 KB. ADR 0005 chose
  one image on purpose.
- **Screenshots instead of live demos.** This is lighter, needs no unpkg and
  shows without JavaScript. The owner chose live demos.
- **Ship the mockups' data as an illustration.** That would publish invented
  commentary on Wird's own host, against the server's rule that commentary is
  never invented.
- **A fixed key like `android/wird.apk`.** A re-upload would land under a
  download that is being resumed, which is the failure ADR 0008 exists to
  prevent.

## Consequences

- Every image carries the page, so a deploy changes the page and the API together.
- Without JavaScript, or without unpkg, the page shows nothing. Crawlers and
  link previews see only the template, so the `<title>` and description carry them.
- A one-segment unknown GET now answers 404, not 401, and `/_ds/` lists its directory.
- `_ds/.../styles.css` duplicates `docs/design/nocturne-styles.css`. A test fails if they drift apart.
- A fresh copy of a demo from the design project brings the invented tables
  back. A test fails if either demo stops reading `window.WIRD_SITE`.
- The live rows for `/` and `/download/android` join `scripts/qa.sh` once the
  page is deployed and an APK is published. Adding them earlier would turn
  the gate red against production for reasons this change already knows.

## Reversibility

Cheap. Delete the three patterns and the package, and the root answers 401 again.
Move the page out if it ever needs a release cycle of its own, or if the
runtime's unpkg dependency becomes a reliability problem. Self-hosting
React and dropping the in-browser Babel step would come first.
