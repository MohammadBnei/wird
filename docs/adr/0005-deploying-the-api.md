# 5. One image, the API only, and the database comes from Infisical

Date: 2026-09-24. Status: accepted.

## Context

`wird.bnei.dev` resolves and answers Traefik's bare `404 page not found` on
every path. The app already carries that host: `app/lib/data/flush.dart` sends
the outbox there, `app/lib/data/auth.dart` names it in the registered redirect.
So every write a reader makes — an aya understood, a kept note, a prayer, a bug
report — sits in a queue on their phone, and the report screen tells them it
will be sent next time they are connected, which is true and will stay true
until something answers.

infra-bootstrap has already done its half: `wirddb` and `dbuser_wird` exist in
pigsty with the `jidhr` schema, `DBUSER_WIRD_PASSWORD` is in Infisical, the
Authentik provider is blueprinted as a public client, and the app has a
registry entry pointing at `helm/values.yaml` in this repo. This repo had no
`Dockerfile`, no `helm/`, and no workflow, so nothing has ever been built.

## Decision

### One image, and it holds `server/cmd/api`

Three binaries could be deployed. One is.

`server/cmd/api` is what the phone talks to, and it is the whole of what is
broken today. It gets an image and a Deployment.

`server/cmd/adminweb` gets nothing, and the reason is upstream of deployment:
it authorises on a `groups` claim carrying `platform-admins`, and the Authentik
provider's `property_mappings` bind only `openid`, `email`, `profile` and
`offline_access`. There is no group scope mapping, its check is written the
safe way round — a nil claim contains nothing, so 403 — and shipping it today
would deploy a dashboard nobody can open. infra-bootstrap's registry comment
says the same. The scope mapping and the second image belong in one change.

`jidhr/cmd/rootd` gets nothing because nothing calls it over the network. It is
a product in its own right and the README says so, but today the root engine
reaches readers as data bundled in `corpus.db`, and a service with no caller is
a pod with an attack surface and no users.

One binary per image rather than one image with three: the alternative saves
one base layer and costs a shared release cadence, a shared `readOnlyRootFilesystem`
decision, and an entrypoint argument to get wrong. When `adminweb` ships it
gets its own image from the same Dockerfile with one line changed.

### `corpus.db` is not in the image, and must not be added "to be safe"

This is the question most likely to be answered wrong by assumption, so it was
answered by reading the imports.

`server/cmd/api/main.go` imports exactly three of our packages: `internal/api`,
`internal/auth`, `internal/store`. `internal/api` adds `internal/httpx`. None
of them touch SQLite. The package that does read `corpus.db` is
`internal/rootsense`, and its importers are `server/cmd/etl`,
`server/cmd/rootcheck` and `server/cmd/jidhrcorpus` — three command-line tools
that run on a developer's machine, none of which is deployed.

Tafsir, iʿrāb and lexicon prose reach the API from **Postgres**, seeded by
`server/cmd/ingest`, not from the bundled corpus. An unseeded row answers 404
by design; the README explains why inventing commentary in that gap would be
the worst defect this project could ship.

So the 23 MB is not in the image and not on a volume. It is in the app, where
it belongs, and the server never opens it.

### The database comes from Infisical, assembled, in one place

`DATABASE_URL` is built by `infra-bootstrap`'s
`gitops/bootstrap/wird-secret.yaml` from `DBUSER_WIRD_PASSWORD`, into the
Secret `wird-config`, which `helm/values.yaml` mounts with `envFrom` and
nothing else:

```
postgres://dbuser_wird@postgres.bnei.lan:5432/wirddb
```

By name, not by IP — CoreDNS forwards to Pi-hole precisely so pods can resolve
the pigsty VIP, and the name survives a renumber. Port 5432, not pgbouncer's
6432: pigsty's default transaction pooling breaks pgx's server-side prepared
statements and goose's session-scoped advisory lock, which is why
`pigsty.yml` already sets `pgbouncer: false` on both the user and the database.

Two alternatives were rejected.

A per-app Infisical project (the `editable-blog-555c` pattern, and what
infra-bootstrap's registry comment used to say) would put the password in two
entries with a hand-copy between them. `docs/secrets.md` in that repo records
that exact drift biting twice, and records that a `secretsScope` narrows the
sync but not the identity's read grant — so the second project buys no
containment either.

Setting `infisical.enabled: true` with `projectSlug: infra-bootstrap-1-ge1` in
this repo's `values.yaml` would work and would mount the entire root project
into the pod: the Proxmox API token, the pigsty CA key, the break-glass
cluster-admin token. `common-app-chart`'s own
`templates/shared-infisicalsecret.yaml` names that move as the thing an app
repo must never be able to do. The narrowing happens in the repo that reviews
its own changes; this repo's values file names a Secret and no project.

`OIDC_ISSUER` and `OIDC_AUDIENCE` are plain values in `values.yaml`. The
audience is the **client id**, not the string `wird`: Authentik puts the client
id in the ID token's `aud`, and a public client's id ships inside the APK
anyway — infra-bootstrap's `docs/secrets.md` records deliberately having no
`WIRD_OIDC_CLIENT_ID` row for that reason.

### The image tag is a commit SHA, not a semver

Every other build repo in this estate cuts a version with `release-it` and tags
the image with it. Wird does not, and the deviation is deliberate: nothing
outside this repo names a `wird-api` version, the Flutter app is versioned in
its own `pubspec.yaml`, and the cost would be a root `package.json` and a Node
release tool in a Go-and-Flutter repo to produce a string nobody reads. The
short SHA is unique, ordered by history, and cannot disagree with the code it
was built from. Swap in `release-it` the day something outside this repo needs
to name a release.

### CI runs the Go half of the gate, and says which half it skips

`./scripts/qa.sh` is the gate and its exit code is the verdict — on a machine
with `fvm`, a simulator and Homebrew. A GitHub runner has none of those, and
the only self-hosted runner here is a build LXC with no cluster access and no
device. Running a crippled `qa.sh` under its own name would be worse than not
running it, so the workflow runs gate 1 (`go build`, `go vet`, `go test -p 1`
against a real Postgres 18 from this repo's own `docker-compose.yml`) plus the
two gate-7 checks that are pure shell — the marker/issue rule and the 60 MB
corpus budget.

Gate 1 turned out not to be purely Go, and the first CI run is what found it:
`server/internal/api/zz_gate_e2e_test.go` shells out to `fvm flutter test`, so
on a runner with no Flutter toolchain it does not skip, it fails with
`exec: "fvm": executable file not found in $PATH`. The workflow skips that one
test by name. The better fix is a `exec.LookPath("fvm")` guard in the test
itself, which would make it skip loudly on any machine without the toolchain
rather than only under this one workflow; that file belongs to the server, not
to the pipeline, so it is not changed here.

Gates 2 and 3, the Flutter suite and the e2e journeys, stay
where they already are: `./scripts/qa.sh` on a developer's machine before the
push. A macOS runner is what would change that, and the workflow says so in
its own header rather than leaving it to be discovered.

## Consequences

**What this fixes.** The outbox gets somewhere to land: `/v1/sync`,
`/v1/changes`, `/v1/progress`, `/v1/kept` and the report path all answer, so a
report stops being "will be reported next time you are connected" forever.

**What this does not fix, and is not pretending to.**

*Sign-in still fails.* The app's default build sends `dev.bnei.wird://` as its
redirect (`app/lib/data/auth.dart`, `authRedirect`) and Authentik registers
exactly one URI, `https://wird.bnei.dev/auth/callback`, matched with a
fullmatch. That is an app-side define (`WIRD_REDIRECT`), not a change here or
in the blueprint — infra-bootstrap's ADR-0050 rejects custom schemes on
purpose, because they are first-come and unclaimable and PKCE does not stop a
copycat app that runs the whole flow itself. And the redirect only completes in
the app once `wird.bnei.dev` serves `/.well-known/assetlinks.json` and
`/.well-known/apple-app-site-association`, which this image does not: it serves
`/v1/*` and `/healthz`, and has no route for `/auth/callback` either. Deploying
the API is a prerequisite for fixing sign-in, not the fix.

*The microphone is not on this path at all.* Nothing in `server/` touches
audio; recitation is fetched by the device from everyone's favourite third
party and the microphone permission is the app's manifest.

*Content is empty until somebody seeds it.* `server/cmd/ingest` fills the
tafsir, iʿrāb and lexicon tables and is not run by this deployment. Until it
is, those three endpoints answer 404 — which is the designed behaviour, not a
failure, but it will look like one.

**One replica, and that is load-bearing.** `server/cmd/api/main.go` runs the
op-log prune and the report sweep as tickers inside the process, and its own
`ponytail:` comments say two of them racing can lose or double a report. A
second replica needs those moved to a cron job first. `replicaCount` is left at
the chart's 1 rather than written down as 1, so the reason lives in one place —
here, and in the comment in `helm/values.yaml`.

**The first deploy has an ordering requirement.** `helm/values.yaml` ships with
`tag: "unreleased"`, which does not exist in the registry. The first push to
`main` builds an image and rewrites that line. infra-bootstrap's registry entry
must not be synced before that has happened, or the first reconcile is an
`ImagePullBackOff` against a tag that was never built. This repo's build also
needs `MohammadBnei/wird` added to the Infisical OIDC identity's repository
allowlist, or the registry-password step fails with an authentication error
that reads like a broken identity.

**`Synced Healthy` does not mean your commit is running.** The deploy job bumps
`tag:` in a commit of its own, and ArgoCD reported `Synced Healthy` for about
twenty minutes afterwards — truthfully, against the revision it had last
reconciled, which predated the bump. To know whether a release landed, compare
the Deployment's image tag against `helm/values.yaml`, or ask the route itself.
Measured on run `36074938048`, the first push-triggered release to reach
`deploy`: every earlier run was a manual dispatch, which the job skips.
