# 7. The voice model is published where its weights already live

Date: 2026-09-24. Status: superseded by ADR 0008, the day after it was written.
Amends ADR 0005 (voice-follow).

> What this decided is not what runs. The recogniser is served from
> `wird.bnei.dev/models/`, which is the option rejected below under *Not
> `wird.bnei.dev/models/` proxied from Garage by the API* — and what shipped is
> not a proxy. Read
> `0008-the-recogniser-is-served-from-wirds-own-host.md` for the decision in
> force and for what each objection below turned out to be worth. The context
> here — why a signed-out phone must be able to fetch this at all, and how
> three shipped features in one day had no host — is why this document stays.

## Context

The reader cannot download the recogniser, and never could.

`defaultVoiceModelOrigin` was `https://wird.bnei.dev/models/base-ar-quran/`.
All three files answer **401**. There is no `/models/` route in
`server/internal/api/api.go`, so the request falls through to
`a.Middleware(v1)` and is refused for carrying no bearer token — the same
failure `/auth/callback` had until `9078f09`, three hours earlier, in the same
file, for the same reason.

Underneath that, the deeper one: **nothing was ever published there.**
`scripts/export-voice-model.py` ran on somebody's machine and wrote three files
into `build/`. They were never uploaded anywhere, so fixing the route would
have served 404 instead of 401.

In Settings this is silent. `_download()` awaits `fetch()` and drops what it
returns, so the button goes back to reading `Download recogniser · 160 MB` with
its original caption and nothing has changed on the screen. The reader presses
it again. Nothing is what they get the third time too.

### The pattern, which is the finding

This is the third of the same shape in one day:

| What was built | What was missing |
| --- | --- |
| `syncNow` — outbox, retry budget, park, dead-letter, change cursor | twenty-four call sites, all in `app/test`, none in `app/lib`. No write ever left a phone. |
| `/auth/callback` — the redirect the app mints, the state check, the exchange | no route. Sign-in could not finish. |
| the voice model — resumable, cancellable, range-aware, removable | no host. 160 MB with a URL and nobody serving it. |

Each was correct, tested, and green. Each was tested **against a fake the test
process itself started** — `speech_test.dart` binds a `ServerSocket`, serves
the three names, honours `range:`, and cuts the connection on demand. It proves
the client. It cannot prove that anything outside the test has ever heard of
`quran-encoder.int8.onnx`.

So the gap is not sloppiness and no amount of unit testing closes it. A suite
answers its own requests. The question none of these suites could ask is
**does anything answer this URL**, and that question has to be asked of the
network, once, by the gate.

## Decision

**The three files are published as a Hugging Face model repo,
`MohammadBnei/wird-voice-base-ar-quran`, and `defaultVoiceModelOrigin` names
its `resolve/main/`.**

The API is not changed. The image is not changed. `helm/values.yaml` is not
changed. That is the decision, not an omission from it: nothing in the estate
has to grow a route, a credential or a gigabyte for a phone to fetch a public
file that a CDN already hosts for free.

### Why not the estate, option by option

**Not in the API image.** 160 MB into a container that is pulled on every
deploy, quadrupling it, to serve a file most readers never ask for. The estate
has already decided this exact question at fifteen times the size and written
it down: infra-bootstrap ADR-0045 took 2.4 GB of Parakeet weights *out* of
`ukubi-stt`'s image after the size was paid for three times — a blob push that
hit zot's 60s read timeout, registry retention cut to two tags for that repo
alone, and 21 GB pruned off the build runner to make room. Its rule is ours:
weights are an immutable artifact on a different lifecycle from the binary, and
they are fetched from HuggingFace rather than shipped.

**Not Garage — and this is the one that deserves the detail, because Garage is
otherwise exactly right.** It is the object store, `s3.bnei.dev` is already
public through Traefik, a bucket is an entry in
`infra-bootstrap/ansible/playbooks/garage-configure.yml` plus a
`--tags bucket_ops` run, and large binaries do belong there. Three things stop
it:

1. **It cannot answer anonymously today.** Garage has no bucket policy. Its
   only unauthenticated read path is website mode — `[s3_web]` in
   `garage.toml`, plus `garage bucket website --allow`, plus a host that routes
   to port 3902. There is no `[s3_web]` block in that playbook's `garage.toml`,
   and `--tags bucket_ops` deliberately skips the config rewrite and the
   restart. "A new bucket is one entry" is true; "a bucket a signed-out phone
   can read" is a different change — it edits and restarts the store that
   Longhorn's backup target and pgBackRest's off-host repo both live in.
   The alternative, presigned URLs, tops out at seven days by construction and
   cannot be a constant compiled into an APK.
2. **The LXC is 200 GB shared with the backups.** The playbook's own comment
   about `zot-registry` says what that means: unbounded growth there "doesn't
   just fill its own space, it takes the *backups* down with it", which is a
   data-durability failure rather than a storage one. A public download is the
   one workload whose size we do not control — it is a copy per reader, off the
   same disk the Longhorn PV backups land on.
3. **Every byte leaves over the home uplink,** once per install, for a file
   that is bit-identical for everybody and already sits on a CDN.

**Not `wird.bnei.dev/models/` proxied from Garage by the API.** It keeps the
URL the app already carries, which is the one real argument for it, and it
fails on the rest: `wird.bnei.dev` is Cloudflare **orange**, and 160 MB of ONNX
per reader is precisely the "disproportionate non-HTML content" the free plan's
terms name — a risk taken with the account that fronts every other `bnei.dev`
service, to save one constant. It also puts a long download through a
single-replica pod with a 256Mi limit (`replicaCount: 1` is load-bearing; see
the chart's comment), and it needs SigV4 in the server, which is either a new
Go dependency or sixty lines of HMAC nobody asked for. The repo already reasons
this way about orange and grey: `wedding-wall` proxies its images through
Cloudflare on purpose and Ente's bulk objects go direct to grey `s3.bnei.dev`.

**Not `registry.bnei.lan:5000`.** LAN-only. A phone cannot reach it. Listed so
the next reader does not re-derive it.

### Why Hugging Face is the right place rather than the lazy one

- **The weights came from there.** `tarteel-ai/whisper-base-ar-quran` is a HF
  model repo. What we publish is that checkpoint in a different file format.
  A model hub is where a model goes.
- **The estate already depends on HF for exactly this** — ADR-0045's init
  container fetches from it, and treats the local copy as a cache rather than a
  dependency. Wird does the same: the model on the phone is a cache, and its
  absence is the tap the prayer screen never stopped answering.
- **Wird already asks a third party for its bulk bytes**, deliberately:
  `defaultAudioOrigin` is `everyayah.com`, 2.75 GB of recitation, because Wird
  neither bundles it nor serves it from an origin of its own. The model is the
  same shape of object with better terms.
- **Anonymous, and range-capable.** Measured rather than assumed:
  `curl -r 0-0` against a public `resolve/main/` file returns **206** after one
  redirect to the CDN, with no token. `dio` follows the redirect and dart:io
  copies the `range:` header onto the redirected request, so a resumed download
  is still a resumed download. No bearer, no Traefik rate limiter and no
  Cloudflare plan on the path — the constraint that a signed-out reader must be
  able to fetch this is met by removing the things that would have had opinions
  about it.
- **The licence grants it.** Upstream is Apache-2.0, which permits the
  conversion and its republication provided the licence travels with it and the
  changes are stated. `scripts/export-voice-model.py` now writes the model card
  that does both, so publishing is one command with nothing to remember.

### What the code does now

- `defaultVoiceModelOrigin` names the HF repo, and its comment no longer claims
  a server override. There is no server override. `VoiceModel.beside`'s
  `origin` argument is passed by nothing in `app/lib`, and saying otherwise is
  how the constant stayed pointed at a host that served nothing: it read like
  something operations could fix. Moving the model costs a release. One line.
- `fetch()` returns `VoiceModelTrouble?` instead of `bool`. Null is "the model
  is on the phone". `notServed` is an answer that was not the file — a 401 from
  a host with no route, a 404 from one serving nothing — and **no phone can fix
  it**. `interrupted` is bytes that stopped arriving. The distinction exists
  because the reader must never be shown a failure that reads as theirs.
- `scripts/export-voice-model.py` prints a SHA-256 per file, writes the
  Apache-2.0 model card, and ends by printing the `hf upload` command. Its last
  line says `exported, not published`, because that gap is the whole of this
  ADR.

## What would have caught it

`scripts/qa.sh` gains one check beside `the_app_calls_what_it_ships` —
which exists because of `syncNow` — and it is that check's mirror:

```
every URL the app ships answers
```

A table of the URLs a reader's phone actually requests, each fetched for real
with a one-byte `range:`, each with the expected status and a sentence naming
what a reader loses when it does not answer. The range is deliberate: it proves
the file is there *and* that the host honours resumption, which is what a
reader on a train depends on.

It is **red right now**, on the three model files, and it stays red until the
list below has been followed. That is the check working. The other two rows —
`everyayah.com/…/001001.mp3` and `wird.bnei.dev/auth/callback?code=…` — pass,
and the callback row would have been red for the fortnight before `9078f09`.

What it does not cover: a URL built at runtime rather than written down, and a
host that answers with the wrong bytes. Both are worth less than the failure
class it does cover, which has now produced three separate outages of
already-shipped features in one day. It needs the network, so a machine with
none records a loud `skip` rather than a pass.

## How to publish the model

For someone who has not read any of the above. Steps 1 to 6 are one sitting;
step 7 is the next time the app is built.

1. **Check the account.** <https://huggingface.co/MohammadBnei> exists. If the
   model should live under a different account or name, change it in three
   places and keep them identical: `defaultVoiceModelOrigin` in
   `app/lib/data/speech.dart`, the `--publish` default in
   `scripts/export-voice-model.py`, and the three URLs in
   `every_url_the_app_ships_answers` in `scripts/qa.sh`.

2. **Export the three files**, on a machine with the Python toolchain (this is
   the slow step — it downloads the checkpoint and runs a torch export):

   ```
   pip install torch transformers openai-whisper onnx onnxruntime onnxscript
   python scripts/export-voice-model.py
   ```

   It writes `build/voice-model/` and prints a size and a SHA-256 per file.
   Expect about 29 MB of encoder, 131 MB of decoder, 0.8 MB of tokens. It ends
   by printing the upload command from step 4.

3. **Install the Hub CLI and sign in** with a token that may write:

   ```
   pip install -U huggingface_hub
   hf auth login
   ```

   (On huggingface_hub older than 0.34 the command is `huggingface-cli`.)

4. **Create the repo and upload.** `hf upload` creates it if it is not there:

   ```
   hf upload MohammadBnei/wird-voice-base-ar-quran build/voice-model . --repo-type=model
   ```

   That pushes the three files and the `README.md` card the export wrote, which
   carries the Apache-2.0 licence and states what was changed. Both are
   obligations of the licence the weights arrive under; do not upload without
   the card.

5. **Confirm the repo is public.** On the repo's Settings page it must not say
   Private. A private repo answers 401 to a phone — the exact failure this
   replaces.

6. **Check it from outside**, with no token anywhere:

   ```
   ./scripts/qa.sh
   ```

   The row `every URL the app ships answers` must pass. To check only that
   part:

   ```
   curl -sSLo /dev/null -w '%{http_code}\n' -r 0-0 \
     https://huggingface.co/MohammadBnei/wird-voice-base-ar-quran/resolve/main/quran-decoder.int8.onnx
   ```

   `206` is the answer. `200` means the host ignored the range and a reader who
   loses signal restarts from zero — investigate before shipping. `401` or
   `404` means step 4 or step 5 did not take.

7. **Close the honesty gap in Settings**, which is the one edit this work did
   not make because `app/lib/features/` was out of its hands.
   `_VoiceModelState._download()` in
   `app/lib/features/settings/settings_screen.dart` awaits `fetch()` and
   discards what it returns, so a failed download looks identical to no press
   at all. It now returns a `VoiceModelTrouble?`. Keep it in a field and let
   `_caption` say it:

   - `VoiceModelTrouble.notServed` — *"The recogniser is not available to
     download right now. This is not your phone or your connection; try again
     another day."* Never a retry-shaped instruction, because retrying is
     exactly what does not work.
   - `VoiceModelTrouble.interrupted` — the caption the panel already has for a
     stopped download: what arrived is kept, pressing Download carries on from
     there.
   - null — the model is on the phone; the panel already says so.

   A test named for the failure: *a download that could not be served does not
   leave the panel looking like the reader mistyped their wifi password.*

## Consequences

- Voice-follow's 160 MB never touches the cluster, the registry, the Garage
  LXC, the Cloudflare account or the home uplink. The chart, the image and the
  API are untouched, and the smallest change that makes the feature real is one
  constant plus an upload.
- Wird now redistributes a third-party model, which it does not do for the
  recitation audio. The difference is written down rather than assumed: the
  weights are Apache-2.0, which grants it; the audio's terms do not, which is
  why `defaultAudioOrigin` points at everyayah and always will.
- A third party can take the model down. Voice-follow degrades to the tap the
  prayer screen has always answered, the gate goes red the same day, and the
  fix is the in-estate route written out above at the cost of a release.
- `fetch()` no longer returns a bool. Settings ignores the value today, which
  is step 7; nothing else calls it.

## Reversibility

Two-way, one line. If HF becomes unacceptable, `[s3_web]` on the Garage host
plus a grey `models.bnei.dev` and `garage bucket website --allow` puts the same
three files in the estate, and `defaultVoiceModelOrigin` moves to them. That
costs a release, and a release is what any change to this constant costs —
which is the honest description of the thing, and is now what the code says.
