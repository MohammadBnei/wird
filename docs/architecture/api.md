# API

> wird-api: the Go service that keeps each reader's state, serves senses and the voice model to anyone, and serves the public page at its root. Level L1 · Parent [Overview](../README.md) · Children [Auth](api/auth.md), [Sync endpoints](api/sync-endpoints.md)

## Black box

wird-api is the only server Wird deploys. It answers at `https://wird.bnei.dev`. The app talks to it for two reasons: to keep a signed-in reader's state (what they understood, kept and prayed) on the server, and to fetch things that change after a release, such as senses and the voice model. Everything a reader does works without it; the app catches up when a network is there.

| In | Out | Depends on |
|---|---|---|
| Batches of writes from the app's outbox | One verdict per write | Postgres, for all state |
| Pulls since a cursor | Rows changed since then, plus the next cursor | Authentik, to check bearer tokens |
| Senses fetches, signed in or not | The senses pack, or "not changed" | An object store holding the voice model |
| Voice model fetches, signed in or not | A redirect to a short-lived download link | |
| A visitor's browser at `/` | The public page and its two live demos | |
| The page's Download button | A redirect to the published APK | |

```mermaid
sequenceDiagram
  participant App as Wird app
  participant API as wird-api
  participant IdP as Authentik
  participant DB as Postgres
  participant OS as Object store

  App->>IdP: sign in, get a token
  App->>API: POST /v1/sync with bearer token
  API->>IdP: fetch its signing keys, when needed
  Note over API: check the token signature
  API->>DB: land each write
  API-->>App: one verdict per write
  App->>API: GET /v1/changes?since=cursor
  API-->>App: changed rows + next cursor
  App->>API: GET /v1/senses, no token
  API-->>App: senses pack or 304
  App->>API: GET /models/..., no token
  API-->>App: 302 to a download link
  App->>OS: download the model
```

### The endpoints

There are two groups. The open group needs no token, because the app is fully usable signed out. The bearer group needs a valid Authentik token.

| Endpoint | Token | What it answers | Called by the app |
|---|---|---|---|
| `GET /healthz` | no | 200, for the liveness probe | no |
| `GET /auth/callback` | no | A page that hands the sign-in code back to the app | through the browser |
| `GET /.well-known/assetlinks.json` | no | Android's proof that the app owns `/auth/callback` | by Android |
| `GET /.well-known/apple-app-site-association` | no | iOS's proof that the app owns `/auth/callback` | by iOS |
| `GET /models/...` | no | 302 to the voice model file; 503 when no store is set up | yes |
| `GET /v1/senses` | no | Every sense, with who wrote them; 304 when unchanged. `HEAD` checks without the body | yes |
| `GET /`, `GET /{file}`, `GET /_ds/...` | no | The public page and the files it renders from. See [the site](#the-public-page) | no |
| `GET /download/android` | no | 302 to the published APK; 503 until one is published | no |
| `POST /v1/sync` | yes | The one write path. See [Sync endpoints](api/sync-endpoints.md) | yes |
| `GET /v1/changes` | yes | What changed since a cursor. See [Sync endpoints](api/sync-endpoints.md) | yes |
| `GET /v1/me` | yes | The reader the token belongs to | no |
| `DELETE /v1/me` | yes | Deletes the reader and everything they own; 204. A token signed in before the deletion is refused from then on | yes |
| `GET /v1/progress` | yes | Counts for the progress screen | no |
| `GET /v1/kept` | yes | Kept items, optionally of one kind | no |
| `GET /v1/corpus/version` | yes | The server's record of the corpus version | no |
| `GET /v1/ayahs/{s}/{a}/tafsir` | yes | Placeholder commentary, or 404 | no |
| `GET /v1/ayahs/{s}/{a}/irab` | yes | Placeholder parsing, or 404 | no |
| `GET /v1/roots/{letters}/lexicon` | yes | Placeholder lexicon entries, or 404 | no |

The last column comes from the app's code. The app calls only [`/v1/sync`](../../app/lib/data/sync.dart#L59), [`/v1/changes`](../../app/lib/data/sync.dart#L77), [`/v1/senses`](../../app/lib/data/senses.dart#L94), [`DELETE /v1/me`](../../app/lib/data/auth.dart#L275) and [`/models/`](../../app/lib/data/speech.dart#L65). The other bearer routes are served and tested, but no screen reads them today.

Every error a wird-api handler writes has one shape, ukubi-go's `{"code", "key", "message", "source", "detail"}`, with the HTTP status that the code maps to:

```json
{"code":"unauthenticated","key":"auth.token_rejected","message":"token rejected","source":"","detail":""}
```

`message` is for a person to read. It says what the caller did wrong, never which table or statement failed, and it may be reworded. `key` is what a client branches on, and it never changes meaning. Every key lives in one file, [keys.go](../../server/internal/keys/keys.go), and a test runs ukubi-go's `errkeys` analyzer to fail any key made anywhere else ([errkeys_test.go](../../server/errkeys_test.go)). A 500 carries ukubi-go's own key, `internal`. `source` and `detail` are always empty here, because wird-api passes on no other service's errors. ADR [0038](../adr/0038-api-errors-carry-a-key.md) records the choice.

`/models/` and `/download/android` use the same JSON body. A presign failure on either answers 500, not 503, because the public page reads a 503 as "not published yet". Four answers stay plain text: the app-link files' 404, `/models/` with an empty key or one holding `..` (a static 404), the sign-in page at `/auth/callback`, and the router's own 404 and 405 for a path or method no route serves (for example `POST /v1/me`), which Go's `ServeMux` writes before any handler runs.

## White box

```mermaid
flowchart TB
  env[/"environment variables"/]
  load["load (config.go)<br/>every refusal at once"]
  main["cmd/api main"]
  open_db["store.Open<br/>connect + run migrations"]
  authn["auth.New<br/>discover the issuer"]
  routes["api.Routes"]
  outer{"outer mux"}
  openh["open handlers<br/>healthz, callback, assetlinks,<br/>models, senses"]
  mw["auth middleware<br/>verify token, find or mint reader"]
  v1{"v1 mux"}
  h["thin handlers"]
  st["store package<br/>all SQL"]
  pg[("Postgres")]
  bg["background loops<br/>prune op log, sweep reports"]

  env --> load --> main
  main --> open_db --> pg
  main --> authn
  main --> routes --> outer
  outer --> openh
  outer -->|"any other path"| mw --> v1 --> h --> st --> pg
  openh --> st
  main --> bg --> st
```

### 1. Start: read the environment, migrate, listen

`main` reads its whole configuration once, through `load` in `config.go`, before it opens anything. `load` reports every problem in one `config refused` line and the process exits 1; a refusal names variables, never their values ([config.go:51-125](../../server/cmd/api/config.go#L51-L125), [main.go:36-42](../../server/cmd/api/main.go#L36-L42)). Then it opens Postgres, which also applies every migration not yet run, and asks the identity server to describe itself. If either step fails, the process exits. [main.go:44-58](../../server/cmd/api/main.go#L44-L58)

It fails closed. A deployment that is missing a value refuses to start rather than starting against `localhost`, and a store that is half configured refuses rather than silently answering 503 ([ADR 0036](../adr/0036-each-binary-refuses-a-partial-configuration.md)). `WIRD_DEV=1` is the one switch for a local run: it fills the three required values with the compose stack's and changes nothing else.

| Variable | Default | What it sets |
|---|---|---|
| `WIRD_DEV` | unset | `1` lets the three required values below default to the local compose Postgres and OIDC stub. Any other value is refused. [config.go:54-60](../../server/cmd/api/config.go#L54-L60) |
| `DATABASE_URL` | required; with `WIRD_DEV=1`, the local compose Postgres | The database. [config.go:79](../../server/cmd/api/config.go#L79) |
| `OIDC_ISSUER` | required; with `WIRD_DEV=1`, the local OIDC stub | Where tokens come from, passed through byte for byte (production's trailing slash matters). [config.go:82](../../server/cmd/api/config.go#L82) |
| `OIDC_AUDIENCE` | required; with `WIRD_DEV=1`, `wird` | The `aud` a token must carry; in production, the app's client id. [config.go:83](../../server/cmd/api/config.go#L83) |
| `API_ADDR` | `:8080` | The listen address. [config.go:61-63](../../server/cmd/api/config.go#L61-L63) |
| `WIRD_MODELS_S3_BUCKET` | unset, so `/models/` and `/download/android` answer 503 | The bucket of the voice model store. The four store values come together: one set without the others is refused. [config.go:88-107](../../server/cmd/api/config.go#L88-L107) |
| `WIRD_MODELS_S3_ENDPOINT` | unset | The store's S3 endpoint. |
| `WIRD_MODELS_S3_ACCESS_KEY` | unset | The store's access key. |
| `WIRD_MODELS_S3_SECRET` | unset | The store's secret key. |
| `WIRD_MODELS_S3_REGION` | `garage` | The region the signature is computed over; a wrong one is a 403. Set alone, it is refused like the other four. [models.go:62](../../server/internal/api/models.go#L62) |
| `WIRD_APK_KEY` | unset, so the download answers 503 | The object key of the published APK in that same store, named by its digest. Refused without a store. [apk.go:26](../../server/internal/api/apk.go#L26) |
| `WIRD_APK_VERSION` | unset, so `/download/android/version` answers 204 and the page prints plain "APK" | The release that key is, printed beside the page's Download button. Set by `apk.yml` together with the key, and refused without it. [apk.go:51](../../server/internal/api/apk.go#L51) |
| `WIRD_ANDROID_SHA256` | unset, so 404 | Signing-key fingerprints for `assetlinks.json`, comma-separated, parsed once at start. [applinks.go:35-44](../../server/internal/api/applinks.go#L35-L44) |

`TestConfigDocumented` holds this table, the variables `load` reads, and its `envVars` list to the same set, and `server/env_test.go` refuses any other code that reads the environment.

Read by libraries, not by `load`, and so not in the table:

- pgx fills any part `DATABASE_URL` leaves out from `PGHOST`, `PGPORT`, `PGUSER`, `PGPASSWORD`, `PGSSLMODE` and the rest of libpq's variables.
- go-oidc's discovery and key fetches go through `net/http`, which honours `HTTPS_PROXY`, `HTTP_PROXY` and `NO_PROXY`.
- `crypto/x509` reads `SSL_CERT_FILE` and `SSL_CERT_DIR` for the roots it trusts.

Migrations are embedded in the binary. The server and the test database both come up through `Open`, so a migration cannot work in one and fail in the other. [store.go:28-55](../../server/internal/store/store.go#L28-L55)

```go
func Migrate(ctx context.Context, url string) error {
	db := stdlib.OpenDB(*mustParse(url))
	defer db.Close()
	goose.SetBaseFS(migrations.FS)
	goose.SetLogger(goose.NopLogger())
	if err := goose.SetDialect("postgres"); err != nil {
		return err
	}
	return goose.UpContext(ctx, db, ".")
}
```

### 2. Routes: two muxes, one gate

`Routes` builds a `v1` mux for everything that needs a reader, and an outer mux for everything that does not. The outer mux hands any path it does not know to the auth middleware wrapped around `v1`. An open route stays open because it is registered on the outer mux, not because the middleware skips it. [api.go:49-105](../../server/internal/api/api.go#L49-L105)

```go
	v1 := http.NewServeMux()
	v1.HandleFunc("GET /v1/me", h.me)
	v1.HandleFunc("DELETE /v1/me", h.deleteMe)
	v1.HandleFunc("GET /v1/corpus/version", h.corpusVersion)
	v1.HandleFunc("POST /v1/sync", h.sync)
	v1.HandleFunc("GET /v1/changes", h.changes)
	v1.HandleFunc("GET /v1/progress", h.progress)
	v1.HandleFunc("GET /v1/kept", h.kept)
	v1.HandleFunc("GET /v1/ayahs/{surah}/{ayah}/tafsir", h.tafsir)
	v1.HandleFunc("GET /v1/ayahs/{surah}/{ayah}/irab", h.irab)
	v1.HandleFunc("GET /v1/roots/{letters}/lexicon", h.lexicon)
```

`/v1/senses` is the one `/v1/` path on the outer mux. Go's `ServeMux` picks the most specific pattern, so it wins over the catch-all and never meets the middleware. [api.go:94-103](../../server/internal/api/api.go#L94-L103)

### The public page

The page sits on the same outer mux. Its files are one path segment deep, or under `_ds/`, and every API route is two segments or more, so `GET /{file}` never reaches `v1`. `/healthz` is matched exactly and wins over it. An unknown one-segment path now answers 404 rather than 401. [api.go:95-102](../../server/internal/api/api.go#L95-L102)

The files are embedded with `//go:embed all:static`. A plain `static` would leave out `_ds/`, because embed skips names that start with an underscore, and the page would render unstyled. Every response carries `Cache-Control: no-cache`, because embedded files have no modification time to revalidate against. [site.go](../../server/internal/site/site.go)

The two demos are Claude Design prototypes, rendered in the visitor's browser by the design runtime, which loads React and Babel from unpkg. Their Qur'an text, glosses, roots, senses and counts come from `site-data.js`, which `scripts/site-data.py` writes from the corpus. [The site's README](../../server/internal/site/README.md) says which files are verbatim and which are Wird's. [ADR 0018](../adr/0018-the-public-site-is-served-by-the-api.md) records why the page lives here.

```mermaid
flowchart LR
  V[Visitor] -->|GET /| P[index.html]
  P --> R[support.js + React from unpkg]
  R -->|fetch| D[Wird Reader / Prayer .dc.html]
  D --> S[site-data.js, from the corpus]
  V -->|Download| A[GET /download/android] -->|302| O[(Object store)]
```

The middleware verifies the token, then finds the reader behind its subject, creating the row the first time. [Auth](api/auth.md) has the details. [auth.go:48](../../server/internal/auth/auth.go#L48)

### 3. Handlers stay thin

A handler checks what came off the wire, calls the store once, and writes JSON. Two helpers in `httpx` write the only two response shapes: `JSON` for an answer, and `Error(w, code, key, message)` for an error, which hands the body to ukubi-go's `errs.Write`. [httpx.go:12-29](../../server/internal/httpx/httpx.go#L12-L29)

When the store fails, `fail` decides what the caller may learn. A missing row is a 404. Anything else is a 500 that says only `unavailable`, and the real reason goes to the log. [api.go:227-234](../../server/internal/api/api.go#L227-L234)

```go
func (h *Handler) fail(w http.ResponseWriter, what string, err error) {
	if errors.Is(err, store.ErrNotFound) {
		httpx.Error(w, errs.NotFound, keys.NotFound, "nothing here yet")
		return
	}
	h.log.Error(what, "err", err)
	httpx.Error(w, errs.Internal, errs.KeyInternal, "unavailable")
}
```

Input checks are small and local. An aya path must name a sūra from 1 to 114 and an aya from 1 to 999, folded into a `surah*1000 + ayah` key ([api.go:201-209](../../server/internal/api/api.go#L201-L209)), a root must be at most 32 bytes of Arabic letters ([api.go:213-223](../../server/internal/api/api.go#L213-L223)), and a kept kind must be `aya`, `root` or `note` ([api.go:140-147](../../server/internal/api/api.go#L140-L147)).

### 4. The store holds every SQL statement

`server/internal/store` is the only package that speaks SQL. It uses `pgx/v5` with hand-written queries and no ORM. [store.go:1-3](../../server/internal/store/store.go#L1-L3)

```mermaid
erDiagram
  users ||--o{ sets : "prays"
  users ||--o{ set_prayers : "records"
  sets ||--o{ set_prayers : "prayed on"
  users ||--o{ ayah_understood : "marks"
  users ||--o{ root_known : "learns"
  users ||--o{ kept_items : "keeps"
  users ||--o| user_prefs : "chooses"
  users ||--o{ op_log : "sent"
```

The tables come from nine migrations in `server/migrations`:

| Migration | Adds |
|---|---|
| [00001](../../server/migrations/00001_user_state.sql) | Reader state: `users`, `sets`, `set_prayers`, `ayah_understood`, `root_known`, `kept_items`, `user_prefs`, and `op_log` for replays |
| [00002](../../server/migrations/00002_content.sql) | Placeholder `tafsir_entries`, `irab_entries`, `lexicon_entries`, and `corpus_meta` |
| [00003](../../server/migrations/00003_change_order.sql) | The `change_seq` sequence that orders the change stream |
| [00004](../../server/migrations/00004_derived_set_ids.sql) | Set identity per reader, for derived set ids |
| [00005](../../server/migrations/00005_reports_and_health.sql) to [00008](../../server/migrations/00008_reports_are_written_by_the_clock_not_by_the_reader.sql) | Anonymous `reports`, `report_inbox`, and the `sync_outcomes` totals |
| [00009](../../server/migrations/00009_the_server_owns_the_senses.sql) | `root_senses`, the senses the server serves |
| [00010](../../server/migrations/00010_reading_positions.sql) | `reading_positions`, the reader's place in each sūra |
| [00011](../../server/migrations/00011_report_triage.sql) | A report's `locale` and `sense_hash`, the `verdict_root` the sweep settles for a sense verdict, and the operator's triage: `category`, `status`, `issue_url` |

Read endpoints are pure queries. Progress is counted on each request, never stored; `percent` is understood ayas over 6236, as a fraction. [store.go:187-238](../../server/internal/store/store.go#L187-L238)

### 5. Placeholders answer honestly

No licensed tafsir, iʿrāb or lexicon text exists yet. The content tables hold a few rows marked `is_placeholder`, and the payload carries `"placeholder": true`. An aya or root with no row is a 404, never an invented answer. [00002_content.sql:3-8](../../server/migrations/00002_content.sql#L3-L8), [store.go:293-317](../../server/internal/store/store.go#L293-L317)

`corpus_meta` is seeded once by that migration and nothing updates it, so `/v1/corpus/version` does not follow the corpus the app ships. [00002_content.sql:41](../../server/migrations/00002_content.sql#L41)

### 6. Two loops run beside the server

`main` starts two goroutines. One prunes `op_log` rows older than 90 days, once a day ([main.go:107-116](../../server/cmd/api/main.go#L107-L116), [store.go:409-418](../../server/internal/store/store.go#L409-L418)). The other moves anonymous reports from the inbox into the table the operations view reads, every ten minutes ([main.go:129-144](../../server/cmd/api/main.go#L129-L144)). [main.go:68-70](../../server/cmd/api/main.go#L68-L70)

```go
	var loops sync.WaitGroup
	loops.Go(func() { maintain(ctx, db, log) })
	loops.Go(func() { sweep(ctx, db, log) })
```

Both are marked as deliberate ceilings: they assume one replica ([main.go:105-106](../../server/cmd/api/main.go#L105-L106)). Two replicas racing the report sweep could lose or double a report. [main.go:135-137](../../server/cmd/api/main.go#L135-L137)

### 7. Logs and shutdown

The first line of `main` installs ukubi-go's JSON logger on stdout, so every line is one JSON object with `time`, `level` and `msg`, which is what Loki reads. ERROR means something on our side failed. When a request fails because its caller hung up, `httpx.Failed` logs the same words at WARN instead, so a phone dropping mid-sync never counts toward the error-rate alert ([serve.go:52](../../server/internal/httpx/serve.go#L52)). `server/logs_test.go` pins every ERROR line with its words.

The server runs through `httpx.Serve`: timeouts on reading and writing, net/http's own lines at ERROR, and a drain on SIGTERM. The requests in flight get up to 20 seconds to finish. The two loops stop, a sweep already running commits, and the database closes last ([main.go:76](../../server/cmd/api/main.go#L76), [main.go:91](../../server/cmd/api/main.go#L91)). [ADR 0039](../adr/0039-logs-are-json-on-stdout-and-sigterm-drains.md) has the why.

## Why it is this way

- [ADR 0001](../adr/0001-stack.md) — Go, Postgres and hand-written SQL; the server owns user state, the app owns the corpus.
- [ADR 0002](../adr/0002-set-identity.md) — a set id is derived, and one op records a prayer.
- [ADR 0004](../adr/0004-the-operations-view-behind-authentiks-group.md) — the operations view sees totals only, which is why reports pass through an inbox and a sweep.
- [ADR 0005](../adr/0005-deploying-the-api.md) — one image, holding only this binary; the corpus is never in it.
- [ADR 0026](../adr/0026-reports-are-triaged-and-turned-into-issues.md) — a report says which language and which sentence a sense verdict was about; this binary alone runs the migrations.
- [ADR 0008](../adr/0008-the-recogniser-is-served-from-wirds-own-host.md) — the voice model is served from Wird's own host, as a redirect.
- [ADR 0010](../adr/0010-the-server-owns-the-roots-and-their-senses.md) — the server owns the senses, and serves them without a token.
- [ADR 0039](../adr/0039-logs-are-json-on-stdout-and-sigterm-drains.md) — logs are JSON on stdout with deliberate levels, and a SIGTERM drains.

## Go deeper

- [Auth](api/auth.md) — how the middleware checks a token and finds the reader.
- [Sync endpoints](api/sync-endpoints.md) — `POST /v1/sync` and `GET /v1/changes` in detail.
- [Sync in the app](app/sync.md) — the outbox on the other end of those calls.
- [Senses in the app](app/senses.md) and [the senses pipeline](pipelines/senses.md) — who reads `/v1/senses` and where its rows come from.
- [Admin web](adminweb.md) — a separate binary that reads the same Postgres through the same store package.
- [Deploy](deploy.md) — how this binary reaches `wird.bnei.dev`.
- Tour: [A prayer, from tap to Postgres](../tours/prayer-to-postgres.md).
