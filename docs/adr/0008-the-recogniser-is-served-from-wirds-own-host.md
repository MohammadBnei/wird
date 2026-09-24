# 8. The recogniser is served from Wird's own host

Date: 2026-09-25. Status: accepted. Supersedes ADR 0007. Amends ADR 0005
(deploying the API).

## Context

ADR 0007 is one day old and describes a deployment that does not exist. It
decided the three model files live in a Hugging Face repo, and said so
plainly: *"The API is not changed. The image is not changed.
`helm/values.yaml` is not changed."* It carries a section headed **"Not
`wird.bnei.dev/models/` proxied from Garage by the API"**.

That is what runs. `0757cb8` built it the same evening, and the live host
answers today:

```
$ curl -sS https://wird.bnei.dev/models/base-ar-quran/38853d7df20b/tokens.txt
<a href="https://s3.bnei.dev/wird-models/base-ar-quran/38853d7df20b/tokens.txt
  ?X-Amz-Algorithm=AWS4-HMAC-SHA256
  &X-Amz-Credential=GK…%2F20260924%2Fgarage%2Fs3%2Faws4_request…">Found</a>.

$ curl -sS -o /dev/null -w '%{http_code}\n' -r 0-0 -L \
    https://wird.bnei.dev/models/base-ar-quran/38853d7df20b/quran-encoder.int8.onnx
206
```

An ADR that records the opposite of what runs is worse than no ADR: the next
reader trusts it, re-derives nothing, and changes the wrong thing. So this one
replaces it rather than amending it, and 0007's status line now says so.

The motive for the reversal was the owner's: the one large asset this app has
belongs where the rest of it lives. 0007 had already written the cost of the
alternative into its own consequences — *"a third party can take the model
down"* — and accepted it. Reasonable people accept that risk; this owner does
not, for this asset, and that is a decision they get to make.

But the reversal is not right merely because it was asked for. 0007's
objections were sound objections to **a proxy**, and what shipped is not a
proxy.

## Decision

**`GET /models/<key>` on `wird.bnei.dev` mints a short-lived presigned SigV4
GET against Garage and answers `302`.** The bucket is `wird-models` on grey
`s3.bnei.dev`; the app holds the path `/models/base-ar-quran/<digest>/` and
never a URL.

Three properties carry it, and each answers a failure that has already
happened here.

**The route is open, and has to be.** Voice-follow is deliberately available
to a reader who has never signed in, so the phone fetching 160 MB holds no
token and never will. Before `/models/` existed the request fell through to
the authenticator and was refused for carrying no bearer token — the identical
failure `/auth/callback` had, in the same file, hours earlier. `/healthz`,
`/auth/callback`, `/models/`: three routes outside the authenticator, and the
reason is the same each time.

**The bytes never pass through the pod.** This is the whole of the difference
from the thing 0007 rejected. The pod computes an HMAC and writes a `Location`
header; the transfer is phone-to-store. A reader's `Range` travels on their
own request to Garage, so a resumed download is answered `206` by the store
and this route never sees it. 160 MB per reader through a single replica with
a 256Mi limit would be an outage rather than a feature — 0007 was right about
that, and it is precisely what does not happen.

**Objects are keyed by a digest of their own contents.** The last path segment
is a digest over the three files' digests, so a re-export cannot land on a key
that a half-finished download is resuming against. The client sends `If-Range`
besides, so a store that has changed underneath a resume answers the whole
file instead of appending to it. Two int8 halves that disagree load without
complaint and transcribe nothing, which is the same silent failure a
dynamo-exported graph gives, and it is not a thing to debug twice.

### What each of 0007's objections turned out to be worth

- **"Cloudflare orange, and 160 MB of ONNX per reader is the disproportionate
  non-HTML content the free plan's terms name."** Only the 302 is orange, and
  it is smaller than a sync response. The transfer is a direct fetch from grey
  `s3.bnei.dev`, which is the same split `wedding-wall` and Ente already use
  and which 0007 cited approvingly while concluding the opposite.
- **"A long download through a single-replica pod with a 256Mi limit."**
  Answered above. The pod's peak is still the migrations at startup.
- **"It needs SigV4 — a new Go dependency or sixty lines of HMAC nobody
  asked for."** It is 126 lines in `server/internal/api/presign.go`, held to
  Amazon's own published worked example in `presign_test.go`, which is the only
  way to know it is right without a store to ask. Somebody did ask for it.
- **"Garage cannot answer anonymously today, and presigned URLs top out at
  seven days by construction."** Both true, and both stop mattering once the
  app holds a path rather than a URL: the signature is minted per request, 15
  minutes at a time, and expiry is not the client's problem. No `[s3_web]`, no
  website mode, no bucket policy, and no restart of the store that Longhorn's
  backup target and pgBackRest's repo live in. The bucket still answers `403`
  to an unsigned GET — verified, not assumed. Anonymous reach is this route's
  job, and that keeps the download behind Traefik's rate limiter, which a
  world-readable bucket would not have been.
- **"The LXC is 200 GB shared with the backups."** This one stands, and it is
  the constraint that survived the reversal. Reads do not grow the disk;
  exports do, and content-addressed keys mean every export adds a version and
  removes none. See Consequences.
- **"Every byte leaves over the home uplink, once per install."** Stands.
  Bought deliberately, in exchange for an asset nobody else can withdraw.

### What a publishing step has to satisfy

Not a command list, because the exporter is a script and scripts move. Three
things bind whatever puts the files there:

- **The key is `base-ar-quran/<digest>/<file>`**, `<digest>` taken over the
  three files' digests. It is not a version number and not a date; a name
  chosen by a human is a name that can be reused, and reuse is the failure the
  digest exists to make impossible.
- **`defaultVoiceModelOrigin` in `app/lib/data/speech.dart` names that same
  digest**, and moving it costs a release. The constant and the prefix are one
  fact written in two places, which is the one duplication here worth having:
  the app must be able to say which weights it trusts.
- **The Apache-2.0 card goes in the prefix beside the weights**, for the
  reason under Consequences.

A key that can write is needed for this and for nothing else; it is not the
key in `wird-config`.

## Consequences

- **The chart carries the deployment now.** `WIRD_MODELS_S3_BUCKET` and
  `WIRD_MODELS_S3_ENDPOINT` are plain values in `helm/values.yaml`;
  `WIRD_MODELS_S3_ACCESS_KEY` and `WIRD_MODELS_S3_SECRET` join `DATABASE_URL`
  in the `wird-config` Secret that infra-bootstrap assembles. Four are required
  together and `WIRD_MODELS_S3_REGION` defaults to `garage`; with any of the
  four missing the route answers `503` and nothing else is wrong — the probes
  pass, the API is healthy, and the only broken thing is a reader's Download
  button. That is the failure the chart's comment is written against.
- **The key pair reaches `wird-models` and nothing else, but it can write
  there.** infra-bootstrap's `garage-configure.yml` grants `--read --write` to
  every bucket's key unconditionally, so wird-api holds a credential that can
  replace the weights a phone is about to trust. Read-only is what this wants
  and it is not one command: the grant re-applies on every run, and a new
  export still has to be uploaded by something. Open against infra-bootstrap.
- **Voice-follow now depends on the cluster.** If wird-api is down the
  recogniser cannot be fetched; the feature degrades to the tap the prayer
  screen has always answered, which is the same degradation 0007 accepted for
  a third party's outage.
- **The Apache-2.0 obligation travels with the bytes, not with the host.**
  Hugging Face would have rendered the model card; a bucket renders nothing.
  The card `scripts/export-voice-model.py` writes belongs uploaded into the
  same prefix as the weights, and the licence is no less binding for the store
  being ours.
- **Nothing prunes old exports.** Each export is a new digest, so the bucket
  grows by ~160 MB per re-export on a disk shared with the Longhorn backups.
  Two versions is the useful number — the shipped one and the one before it —
  and pruning is a hand step until something on that LXC measures it.

## What would have caught it

The drift was not the reversal. It was that the reversal lived only in a
running pod: the code read five environment variables that appeared in no
chart, no document and no workflow in this repo, so a fresh deploy of `main`
would have come up healthy and served `503` to every reader, with the sentence
in `helm/values.yaml` still insisting the secret was *"DATABASE_URL, and only
DATABASE_URL"*.

The gate's `every URL the app ships answers` is the check that covers it,
because the URL it fetches is the deployment's. It cannot see a hand-fed pod
as different from a deployed one, which is the limit worth naming: it proves
the host answers, not that this repo is what made it answer.

## Reversibility

Two-way, at the cost of a release, exactly as 0007 said — the app's constant
is what names the host. What has changed is the price of the return trip: a
move back to a public hub is now also the removal of a route, two chart values
and a key pair, and the re-acceptance of a takedown risk this owner declined.
