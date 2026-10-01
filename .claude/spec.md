# Wird — spec for coding agents

Distilled from design history + ADRs, checked against code. Code wins. ADRs in `docs/adr/` carry rationale; read them, not this, for "why".

## Purpose
- Reader studies small set of ayas before prayer (`1a`), recites it inside prayer (`1b`), opens any word's Arabic root (`3a`/`2b`/`1c`).
- Progress = ayas understood, not pages. (`1d` progress, `1e` kept.)
- Success: `1a → 1b → 3a` loop in airplane mode, no spinner, prayer counted after; next set still available offline.
- Quality order: in-prayer reliability > freshness > cold-tap latency on root lookup (local only, never network).
- Stack decision: `docs/adr/0001-stack.md`.

## Components + boundaries
| Part | Path | Role |
|---|---|---|
| App | `app/` | Flutter, iOS + Android + tablet. Owns bundled corpus, generates sets, outbox for writes. |
| wird-api | `server/cmd/api` | Go, stdlib `ServeMux`, `pgx/v5`, `goose`, hand SQL. Source of truth for user state + senses. Only deployed binary. |
| jidhr | `jidhr/` | Standalone Arabic root engine, own Go module. `rootd` serves `jidhr/testdata/quran.json` in memory: no DB, no network, no key. ✗ not deployed (no caller). |
| adminweb | `server/cmd/adminweb` | Ops view, totals only. ✗ not deployed (no groups scope mapping yet). ADR 0004, `docs/adr/0005-deploying-the-api.md`. |
| CLI tools | `server/cmd/{ingest,etl,rootcheck,rootdraft,jidhrcorpus,senseseed}` | Dev-machine only. Never in image. |
- `go.work` unions `server/` + `jidhr/`; server imports jidhr types across modules. Build modules by name: `go build ./server/... ./jidhr/...` (`./...` at root fails).
- `server/internal/rootsense` is only SQLite reader in server tree; importers = CLI tools only. `corpus.db` never in image.

## Data
### Bundled `app/assets/corpus.db` (SQLite, tracked binary)
- Tables: `surahs ayahs words roots root_notes recitations ayah_audio word_segments ayah_translations irab irab_roles corpus_meta`.
- `corpus_version` = 5. ~31 MB. Budget 60 MB (gate `corpus_under_budget`).
- Natural keys: `ayah_id = surah*1000 + ayah`, `word_id = ayah_id*1000 + position`, roots keyed by joined letters (`وصي`, not spaced).
- `root_notes` ships EMPTY since ADR 0010; senses arrive over HTTP.
- `surahs.revelation_order` = Egyptian standard chronology.
- Sources + licences per table: `data/SOURCES.md`. Morphology = Quranic Arabic Corpus (GPL) → why repo is AGPL-3.0. Timings = quran-align (CC BY 4.0), notice in `corpus_meta.notice`; ETL refuses build without it. Gloss/translit = Quran Foundation API; one-week storage rule → unsettled. `words.gloss_fr` = The Last Dialogue pages, written grant 2026-09-30 (ADR 0012); matched by Arabic (LCS), never position; 128 words NULL → app shows `gloss_en`. `irab_roles.role_fr` drawn for French reader.
- Exactly one agent/lane rebuilds `corpus.db` at a time.
- ETL: `go run ./server/cmd/etl -in <abs path>/data/raw/ -out <out> -corpus-version N`. `data/raw/` gitignored → worktrees have none; pass absolute path to owner's checkout.
- ETL hazards: word text + segment timings must come from same segmentation; overlapping segments exist → assert monotonic starts, not non-overlap.
### Device `wird.db`
- One sqflite file = corpus copy + user tables (joins; no ATTACH). `openWird` (`app/lib/data/db.dart`) installs asset only when file absent; atomic via `.part` rename.
- Old install (corpus < 5) lacks `words.gloss_fr` → `_ensureFrenchGlossColumn` (`app/lib/data/db.dart`) adds empty column at open → English fallback. Never query new corpus column without same guard.
- User tables: `ayah_understood user_prefs display_prefs mic_consent sets set_prayers set_span sense_pack outbox auth_tokens prayer_prefs prayer_history`. `prayer_*` device-local, never synced.
- `sqflite_common_ffi` required under `flutter test`.
### Server Postgres (migrations `server/migrations/00001..00009`)
- `users sets set_prayers ayah_understood root_known kept_items user_prefs op_log` + `change_seq` cursor, `lexicon_entries tafsir_entries irab_entries corpus_meta`, `reports report_inbox sync_outcomes`, `root_senses`.
- User-state ids client-minted uuid. `kept_items` tombstoned, never hard-deleted.
- `1d` derives counts, never stores. Percent = `count(ayah_understood)/6236`.
- Tafsir/iʿrāb/lexicon in Postgres = placeholders flagged `"placeholder": true`; unseeded → 404. Nothing licensed. Never invent commentary.
- Migrations run at api startup. Seeders never migrate.

## Sets + reading order
- Pure on-device fn of corpus + order + understood. `app/lib/data/sets.dart`.
- Default order `nuzul` (revelation), `mushaf` switchable. Walk = next aya not yet understood in chosen order → switching never corrupts progress.
- Orders by sūra; ayas within sūra in muṣḥaf order.
- Proposal: ≤ `setMaxAyas` 5, word budget `setWordBudget` 25; reader may drag to `setMaxDragAyas` 20. Set may cross sūra boundary. None left → null, completion state.
- Set id = `uuidv5(ns, "<order>:<start>:<end>")`, ns = `uuidv5(NameSpace_URL, "https://wird.bnei.dev/set")`. Server recomputes + refuses mismatch. Server assigns `ordinal`. Vectors: `docs/adr/0002-set-identity-vectors.json`. ADR 0002.
- `set_prayed` op upserts set + prayer together. Written only by `PrepareScreen._keep` (`app/lib/features/prayer/prepare_screen.dart`) on return from `1b`, only if a reached rakʿah recited credited set (`from` ?? `nextSet`). ADR 0018.
- Visiting an aya / reading a passage: ADR 0003, ADR 0006 (passage is read, set is answered for).

## Sync contract
- One write path: every write → outbox → `POST /v1/sync`, online or not. Each op carries `client_op_id`; server idempotent via `op_log (user_id, client_op_id)`.
- Op kinds: `ayah_understood kept_upsert kept_delete set_recorded set_prayed prefs_set report_written`.
- Per-op result: `applied duplicate refused failed`. `refused` permanent. Client dead-letters after `maxAttempts` = 10 (`app/lib/data/outbox.dart`), surfaced in settings, never mid-prayer.
- Pull: `GET /v1/changes?since=<cursor>` rows + tombstones.
- Contract vectors shared by Go + Dart suites: `docs/adr/0002-sync-contract-vectors.json`. Dart test asserts `report_written` key set EXACTLY. Change vectors + both suites in one commit.
- Server refuses report body with unknown key (→ `refused`, permanent, parks reader's words). Never ship app field before server column is live.
- GETs side-effect free.
- Routes (`server/internal/api/api.go`): bearer-gated `v1` mux: `/v1/me /v1/corpus/version /v1/sync /v1/changes /v1/progress /v1/kept /v1/ayahs/{s}/{a}/tafsir /v1/ayahs/{s}/{a}/irab /v1/roots/{letters}/lexicon`. Open on outer mux: `/healthz`, `/auth/callback`, `/.well-known/assetlinks.json`, `/models/`, `/v1/senses`.
- App origin = `syncOrigin` in `app/lib/data/flush.dart`; override `--dart-define=WIRD_ORIGIN=...`. Never add new `https://` literal casually (qa URL checks).

## Auth
- Sign-in optional; nothing blocks on it; no login wall. App fully usable signed out.
- Authentik OIDC, public client, Auth Code + PKCE (S256 enforced by Authentik policy), no secret. Hand-rolled in `app/lib/data/auth.dart` (dio + `app_links`); tokens in sqflite `auth_tokens`. Issuer/client id/redirect = compile-time defines there.
- Redirect `https://wird.bnei.dev/auth/callback` (App Link), strict match.
- Server: `coreos/go-oidc` JWKS verify, `aud` = client id (not `wird`). Mints no tokens. Cluster shares one signing key across apps → `aud`/`iss` checks load-bearing.
- Local: `docker compose up -d postgres oidc-stub` (mock issuer :8082). api env: `DATABASE_URL OIDC_ISSUER OIDC_AUDIENCE API_ADDR`.
- Different reader signing in clears device (`_handOver`); signing out drops tokens only.
- Ops view auth = Authentik `platform-admins` group via forwardAuth. ADR 0004.

## Senses pipeline (ADR 0010)
- Rule: what Wird wrote → served; upstream content → bundled.
- Postgres `root_senses` (PK `root_letters`, `sense_en`, `sense_fr`, `poetic_*` stored never served). No `reviewed` column.
- Seed: `server/cmd/senseseed -tsv data/root_senses_draft.tsv -roots app/assets/corpus.db`. Full replace; last row per root wins (`ON CONFLICT`); skips header; no clause reordering. DSN via `DATABASE_URL` env only, never `-db` arg for prod. `-dry` checks only.
- `GET|HEAD /v1/senses` open, no auth. Body `{version,source,attribution,basis,senses:[{root,en,fr}]}`. `ETag` = version, 304 on `If-None-Match`, never 404 (empty = `senses: []`).
- Version = `<provenanceRevision>-<md5 over rows ORDER BY root_letters>`. Bump `provenanceRevision` in `server/internal/api/senses.go` BY HAND whenever `sensesAttribution|sensesBasis|sensesSource` prose changes.
- Prose has one holder: Go consts beside handler.
- App: `app/lib/data/senses.dart` applies pack in one txn: delete `root_notes WHERE word_id IS NULL`, insert, write `sense_pack`. Validate body before txn. Empty pack never wipes existing senses.
- Fetch trigger: `Flusher.theFirstSenses` on foreground (2-min floor) + Settings manual row. HEAD checks, GET fetches.
- Two refusal strings: not written vs not fetched. `_whose` always tappable so basis sheet reachable.
- Served senses carry no evidence words. `note_fr` is drawn for a reader in French, English is the fallback.
- Rate limiting = ingress, host-wide. No limiter in Go server.
- `jidhrcorpus` exports meanings for `rootd`; `rootd` keeps reading exported file.
- Draft prompt `data/root-sense-prompt.md`; drafts log `data/root_senses_draft.tsv` append-only, prompt digest per row. Curated `data/root_senses.{tsv,json}` kept for future signed promotion.

## Voice-follow
- `1b` baseline = manual next/prev taps. Voice-follow optional enhancement, off by default. No permission ever required to pray; mic consent never on path to `1b`.
- `1b` reached only via `Routes.prepare` (`Routes.prayer` gone). `1b` writes nothing; reports via `PrayerOutcome`. ADR 0018.
- Prayer = rakʿahs, each Al-Fātiḥa + passage (`rakahOf`, `prayer_plan.dart`). One `PrayerVoice` per prayer; `follow()` per rakʿah, generation counter drops in-flight decode. Next rakʿah begins only on sure full window (`heardTailLetters`) inside Fātiḥa words < `openingWords` 8 → bowing praise must not begin it.
- Unseen basmala inserted into heard words before passage (not At-Tawba). Remove it → basmala snaps cursor to 1:1.
- Pace (`prayer_pace.dart`): voice leads; pace steps after `lostAfter` 3 s with no sure match; pace's own moves never count as recognition.
- Cursor invariant: never throw, never name word outside rakʿah. Moves both ways (repeat aya = rewind). Wrong move blocked upstream by `followMargin`. Property-tested.
- `1b`: wakelock held (tested); no dialog, error, spinner, snackbar, ever.
- Engine: on-device `sherpa_onnx`, Arabic-only Qurʼanic phoneme CTC model (ADR 0009, supersedes model choice in ADR 0005). Audio never leaves phone. Job = locating, not transcribing.
- Model served from `https://wird.bnei.dev/models/...` → presigned redirect to object store (ADR 0008; ADR 0007 superseded). Origin `defaultVoiceModelOrigin` in `app/lib/data/speech.dart`. Weights in `voice/` dir beside `wird.db`.
- Matcher: `app/lib/features/prayer/alignment.dart`, `followMargin = 0.32`.
- Field log: `docs/journal/voice-follow-walk.md` (findings 1–11).

## Audio
- Recitation fetched by device from everyayah.com at playback. Not mirrored, not bundled, not hosted. `ayah_audio.rel_path` relative; origin + cache cap in `app/lib/data/audio.dart`.
- Long-press uncached → show transliteration, never spin.

## UI
- Nocturne, dark only, no light mode. Tokens only from `app/lib/theme/nocturne.dart` (source `docs/design/nocturne-styles.css`). Never hard-code a hex a token carries.
- Scheherazade New + Inter bundled.
- Locales `en` + `fr` (`app/lib/l10n/app_{en,fr}.arb`); parity gated.
- French ayah translation bundled (`ayah_translations`, resource 779).
- Screens `app/lib/features/`: study (1a), prayer (prepare + 1b), root (3a/2b), deepdive (1c tablet), progress (1d), kept (1e), index, report, settings, about (Sources and licences), dashboard.
- Lexicon section removed from app; iʿrāb real from bundled `irab`; tafsir shows honest notice.

## Deploy
- Merge to `main` deploys. PR runs `checks` only.
- `.github/workflows/release.yml`: Go half of gate (build/vet/test `-p 1` on Postgres 18, issue-marker rule, corpus budget) → image build on self-hosted runner → bump `image.tag` in `helm/values.yaml` → ArgoCD (infra-bootstrap) syncs. Tag = short SHA, no semver.
- One image = `server/cmd/api` only. `Dockerfile` copies workspace.
- `DATABASE_URL` from Secret assembled in infra-bootstrap; direct 5432, never pgbouncer (pgx prepared stmts + goose advisory lock break under txn pooling). DB role `connlimit` 20.
- Flutter half (analyze, test, e2e) never runs in CI → run `scripts/qa.sh` locally before push.
- Host: `https://wird.bnei.dev`.

## Gate: `scripts/qa.sh`
- Exit code = verdict; writes `qa-report.json`. Fresh-context reviewer reads artifact, not implementer's reasoning.
- Checks incl.: `no_golden_refresh`, issue-marker rule, `toolchain_recorded`, `arb_locales_agree`, `corpus_under_budget`, `release_manifest_is_shippable`, `the_app_calls_what_it_ships` (public fn in `app/lib/data/*.dart` needs caller outside its file; tests don't count), `every_url_the_app_ships_is_accounted_for`, `every_url_the_app_ships_answers` (`url_rows()`), `gates_all_accounted`, `every_journey_still_runs`.
- e2e journeys in `app/integration_test/`, skip list `qa-skips.json`. Target via `scripts/device.sh`: cabled iPhone > iPhone 16 sim (iOS 18.6) > macOS. Skips recorded loudly.
- Commands:
  - `cd app && fvm flutter analyze && fvm flutter test`
  - `go build ./server/... ./jidhr/... && go vet ./server/... ./jidhr/... && go test -p 1 ./server/... ./jidhr/...` (needs `docker compose up -d postgres`)
  - `DEV=$(./scripts/device.sh) && fvm flutter test integration_test/ -d "$DEV"`
- Flutter pinned via `.fvmrc` (3.47.5). Always `fvm flutter`.

## Invariants / must-nots
- Never refresh goldens inside gate; golden refresh = separate owned reviewed step. Gate greps tracked files and staged diff for the refresh flag and fails on a hit — so name the rule, never spell the flag (`scripts/qa.sh` splits its own copy in two for the same reason).
- Never delete red test in gate it reddens. Flakes quarantined with issue.
- Test names state failure prevented. Never assert only that a mock was called.
- Issue-marker comments need issue number. `ponytail:` comments = deliberate ceilings; keep them.
- Go handlers thin, SQL in `store`, internals never reach client (opaque 500, detail to log).
- Local reads never await network. Lexicon-style remote sections collapse on failure, never the screen.
- Never commit secrets, `data/raw/`, Lane XML (`data/raw/lane`: consulted, never committed/shipped).
- Never run bulk ETL against shared Postgres.
- Never put a clause count/figure in `data/root-sense-prompt.md` rules (becomes target). State the test, not counterexample. Judge prompt changes on held-out roots.
- Never silence `the_app_calls_what_it_ships` with `excused_doors` row when real caller about to land.
- Never sign work as AI-generated (no co-author trailer, no generated-with footer, no session links).
- Ask first: schema changes, new Flutter package, anything touching Authentik/shared Postgres, `corpus.db` > 60 MB.
- Homebrew only, never `sudo`; installs recorded in `docs/toolchain.md`.
- Parallel agents: own worktree each, commit own work, single-owner files (`theme/nocturne.dart`, goldens, `corpus.db`, `docs/toolchain.md`, `go.work`, `pubspec.yaml`).

## Superseded plan claims (don't reintroduce)
- `speech_to_text` platform ASR ✗ → sherpa_onnx phoneme model (ADR 0005, 0009).
- Whisper / multilingual transducer ✗ superseded by ADR 0009.
- Mirror MP3s to own origin ✗ dropped (licence; fetched from third party).
- Timings from QUL / quran.com ✗ → quran-align.
- "Closed app bundle" licensing blocker ✗ → AGPL.
- jidhr meanings table in Postgres `jidhr` schema ✗ → server `root_senses` (ADR 0010); rootd reads file.
- Senses bundled in `corpus.db` ✗ superseded by ADR 0010.
- Server never assigns `ordinal` ✗ → server assigns; id derived (ADR 0002).
- Client-minted set uuid ✗ → derived uuidv5 (ADR 0002).
- English-only UI ✗ → en + fr.
- `flutter_appauth` + `flutter_secure_storage` ✗ → hand-rolled PKCE, tokens in sqflite.
- Dead-letter after 5 ✗ → 10.
- `rootd` deployed/public ✗ not deployed.
- `corpus.db` 23.31 MB ✗ → ~30 MB (v4).
- "Signs in and lands on current set" e2e journey ✗ not in journey list.

## Phase status
| Area | State |
|---|---|
| Scaffold, gate, jidhr, Nocturne, ingest/ETL, sets | ✓ |
| `1a` + audio, `1b` taps, `3a`/`2b`, `1d`/`1e`, `1c` tablet | ✓ |
| wird-api, sync/outbox/changes, reports, ops view code | ✓ |
| Real Authentik + DB (infra-bootstrap #251) | ✓ provider + DB exist |
| Deploy api to `wird.bnei.dev` | ✓ |
| Voice-follow engine + model hosting | ✓ built; matcher open (finding 9) |
| Locale en/fr, French translation | ✓ |
| ADR 0010 server-owned senses | ✓ server + app fetch + prod seeded (1642). Open: see `.claude/handoffs/senses-next-steps.md` |
| adminweb deploy | ✗ open — needs groups scope mapping + own image |
| Poetic register | ✗ stored, not served; own battery unwritten |
| Human signing workflow | ✗ deferred |
| Tafsir licensing, QF gloss one-week rule, QF dev account | ✗ open questions (`data/SOURCES.md`) |

## Known traps
- **Stale `wird.db` after corpus rebuild**: `openWird` never replaces existing file; nothing reads `corpus_version`. New-column reads throw. Fix:
  - macOS: `rm ~/Library/Containers/dev.bnei.wird/Data/Documents/wird.db`
  - Android: `adb shell run-as dev.bnei.wird rm databases/wird.db`
  - voice weights in sibling `voice/` survive.
- **Local run on Mac**: `cd app && fvm flutter run -d macos`. Only local target exercising voice-follow (sim has no useful mic). `scripts/device.sh` will NOT pick Mac if sim/iPhone available. Trail log `~/Library/Containers/dev.bnei.wird/Data/Documents/prayer-trail.log`, truncated each prayer. Bundle id `dev.bnei.wird`, sandboxed.
- **Test corpus temp dirs**: `app/test/corpus.dart` copies 24+ MB corpus per test process into `wird-corpus*` temp dir; swept on entry only if > 1 h old. Disk-full errors (`No space left on device`, `SqliteException(13)`) → check `du -sh $TMPDIR` before blaming change.
- **`app/test/corpus.dart` caches db per process**; empties user tables + `root_notes` per call. Seed senses via its helper, not committed writes elsewhere.
- **Prompt numbers anchor**: any number in sense prompt rules → drafts pile onto it. Removing a cap exposed three hidden rules (one sense split across clauses; heaviest sense must lead by occurrence counts; incidental denotation dressed as verb). Negative examples get echoed.
- **Go e2e gate test** `server/internal/api/zz_gate_e2e_test.go` shells to `fvm`; skips via `exec.LookPath` guard when absent. Some runs use `-skip TestGateEndToEndWithTheRealClient`.
- **`url_rows` rows only after route live** or `every_url_the_app_ships_answers` reddens every lane.
- **L2/L3-style merges**: new public fn in `app/lib/data` must land in same commit as its caller.
- **Goldens move twice** when prose + bundle change together; refresh only after both land.
- **`checkSenses`** (`server/cmd/etl/check.go`) inert while nothing assigns `c.Senses`; re-arms if a sense file is loaded again.
