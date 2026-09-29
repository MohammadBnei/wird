# Handoff: senses, after ADR 0010

Read first: `docs/adr/0010-the-server-owns-the-roots-and-their-senses.md`. Spec: `.claude/spec.md` §Senses.

## Done on origin/main (skip)
- ✓ PR #1 merged, release ran, api deployed.
- ✓ Step 1 prod seed: `GET https://wird.bnei.dev/v1/senses` → 1642 senses, `ETag` `"2-4b9ce37f…"` (non-empty hash).
- ✓ `exec.LookPath("fvm")` guard in `server/internal/api/zz_gate_e2e_test.go`.
- ✓ Test corpus temp-dir leak: `app/test/corpus.dart` sweeps `wird-corpus*` > 1 h old on entry.

Order: 2 → 3 → 4. Each needs step 1 (done).

## 2. `/v1/senses` row in `scripts/qa.sh`
- Add row to `url_rows()` (~line 254). Format `origin|status|path|what breaks`. Model on `/v1/changes` row.
- Expect `200`, path `/v1/senses`. What breaks: no phone can fetch a sense; every root shows "not fetched" notice.
- App reaches URL via `syncOrigin` (`app/lib/data/flush.dart`). No new `https://` literal in `app/lib` → `every_url_the_app_ships_is_accounted_for` needs no change.
- Run `scripts/qa.sh`.

## 3. App names sense it judged (`sense_version`)
Server side live: column, decoder field, sweep (migration `00009`, `server/internal/store/sync.go`, `server/internal/store/admin.go`). App side NOT on origin/main.
- Why order matters: server refuses report body with unknown key → `OpRefused` (SQLSTATE 22/23), permanent, parks reader's words. Never ship app half against server lacking column.
- `app/lib/features/report/report.dart`: `reportContext` (~line 44) sends only `corpus_version` from bundled `corpus_meta` → no longer says which sense judged. Add `sense_version` from `sense_pack.version`. Empty string when no pack (`unknownSenseVersion` in `app/lib/data/senses.dart`). Server caps 64 chars (`senseVersionMax`), blanks longer, no refusal.
- `app/lib/features/report/report_screen.dart`: show reader what is sent.
- `docs/adr/0002-sync-contract-vectors.json`: `report_written` body. Read by Go `server/internal/store/sync_contract_vectors_test.go` + Dart `app/test/data/sync_contract_vectors_test.dart` (exact key set). Change file + both suites in one commit.
- Tests: `app/test/features/report/report_screen_test.dart` (key sets ~lines 76-84, 108-118), `app/test/features/report/sense_verdict_test.dart`.
- `reportContext` carries no reading content on purpose. Only exception = root reader judged. `sense_version` = version string, not content.
- Never refresh goldens inside gate. Report screen golden moves → regenerate as own reviewed step.
- Gate:
  - `cd app && fvm flutter analyze && fvm flutter test`
  - `docker compose up -d postgres`
  - `go test -p 1 -skip TestGateEndToEndWithTheRealClient ./jidhr/... ./server/...`
  - `scripts/qa.sh`

## 4. On a phone
Not in CI: runner has no Flutter toolchain.
```
adb shell run-as dev.bnei.wird rm databases/wird.db   # first, so new empty-senses bundle lands
fvm flutter run -d <android device id> --dart-define=WIRD_ORIGIN=https://wird.bnei.dev
```
- Voice weights in `databases/voice/` survive `rm`.
- Open root → "not fetched" notice. Foreground app → `Flusher.theFirstSenses` fetches once (2-min floor). Open root again → served sense; basis sheet opens, says no person checked it.
- Judge a sense → confirm report carries `sense_version`.

## Loose ends (none block 2-4)
- Finding 9 open: matcher margin rule pins cursor (27/48 windows refused, median margin 0.158 vs `followMargin` 0.32). `docs/journal/voice-follow-walk.md`. Another session owns it.
- `LoadSenses` in `server/cmd/etl/senses.go`: zero callers, not even own test (assigns `c.Senses` directly). Delete. Keep `checkSenses` in `server/cmd/etl/check.go` (`Corpus.Check` calls it) — inert while nothing assigns `c.Senses`; re-arms when a sense file loads.
- Reviewer flag, NOT investigated: regenerated `data/root_senses.json` + `server/cmd/rootcheck/build.go` may leave ETL byline gate fatal. Verify: `go run ./server/cmd/etl -in <abs path>/data/raw/ -out /tmp/corpus.db -corpus-version 4`. `data/raw` gitignored, owner's machine only. Never overwrite `app/assets/corpus.db`.
- Served senses carry no evidence words → "words this was read from" section never draws (test pins loss). Basis prose English only (no `basis_fr`). `note_fr` is drawn for a reader in French, with the English as the fallback.
- ~15 wide roots draft long (عرف 36 clauses, حقق 33). 40 rows unequal en/fr clause counts. Seeder never reorders.
- `data/root_senses.tsv` + `.json` stay → future signed pass promotes 523 curated senses.
- Untracked `no-sleep.sh` in owner's repo root: not ours, leave it.

## Rules
- Never sign work as AI-generated: no co-author trailer, no generated-with footer, no session-link trailer, in commits or PR bodies.
- Lane XML `data/raw/lane` gitignored: consulted, never committed, never shipped.
- Never silence `the_app_calls_what_it_ships` with `excused_doors` row when real caller about to land.
- Goldens never refreshed inside gate.
- Bump `provenanceRevision` in `server/internal/api/senses.go` by hand whenever `sensesAttribution|sensesBasis|sensesSource` change, or installed devices never learn.
- Prod seed/re-seed: DSN via env only (`DATABASE_URL=... go run ./server/cmd/senseseed -tsv data/root_senses_draft.tsv -roots app/assets/corpus.db`), never `-db` (visible in `ps`). `-dry` first. Ask owner for DSN, never guess. Same file re-seeded → version unchanged.
- Merge to `main` deploys. Open PR; only `checks` runs on it.
