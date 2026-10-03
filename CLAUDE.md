# Wird — agent context

Quran prayer companion. Flutter app offline-first + Go API + Go root engine. AGPL-3.0, public repo.
Deep context: `.claude/spec.md`. Per-area rules: `.claude/rules/*.md` (load by path). Humans read `docs/README.md`.

## Doc families — RULE
Two families, two styles. Never mix.

| Family | Files | Style |
|---|---|---|
| Agent | `CLAUDE.md`, `.claude/**` | caveman ultra |
| ADR | `docs/adr/NNNN-*.md` | caveman lite. Template `docs/adr/TEMPLATE.md` |
| Human | `docs/**` (not adr), `README.md`, `CONTRIBUTING.md` | light English prose, mermaid heavy. Guide `.claude/rules/docs.md` |

Caveman ultra:
- no articles, filler, pleasantries, hedging. Fragments ok.
- symbols ok: → = ≠ ✓ ✗. Abbreviation only if unambiguous.
- never drop not/never/no/only/except.
- code, paths, commands, identifiers, errors verbatim.
- bullets + tables > prose.

Caveman lite (ADRs): full sentences, terse, no filler. Readable by human cold.

## Upkeep — RULE
- Change behaviour → same PR updates matching `docs/architecture/**` page (contract, diagram, `path#Lnn` links you shifted).
- Decision with alternatives/trade-off → new ADR, next free number. Existing ADRs immutable; supersede, never edit body (status line only).
- New trap/fact agents need → `.claude/rules/*` or `.claude/spec.md`, caveman ultra.
- `docs.yml` CI: links, `#Lnn` bounds, mermaid parse. Warns when PR touches code a doc links into → recheck those links.

## Map
```
app/      Flutter client. fvm 3.47.5. lib/{data,features/*,theme,l10n,shell,widgets}
server/   Go. cmd/{api,adminweb,etl,ingest,jidhrcorpus,rootcheck,rootdraft,senseseed}, internal/*, migrations/ (goose, embedded)
jidhr/    Go root engine, own module. cmd/rootd :8081
data/     SOURCES.md licence record, root-sense-prompt.md (runtime input), raw/ gitignored
scripts/  qa.sh = gate. device.sh, voice-*.py
helm/     values.yaml, CI bumps image tag → ArgoCD
docs/     human docs + adr/ + design/ (vendored, never hand-edit)
```

## Commands
- gate: `./scripts/qa.sh` → exit code = verdict, writes `qa-report.json`
- Go: `go build ./server/... ./jidhr/...` · `go test -p 1 ./server/... ./jidhr/...` (never `./...` at root)
- app: `cd app && fvm flutter analyze && fvm flutter test`
- local API: `docker compose up -d postgres oidc-stub && go run ./server/cmd/api`
- reader feedback (reports, sense verdicts) → triage + issues: `.claude/rules/feedback.md`

## Load-bearing paths — never move/rename
- `docs/adr/0002-*-vectors.json` ← 4 tests (app + server)
- `docs/toolchain.md` brew-leaves block ← `qa.sh` check 7
- `docs/design/nocturne-styles.css` ← `app/test/theme/nocturne_tokens_test.dart`, `server/cmd/adminweb`
- `data/root-sense-prompt.md` ← `server/cmd/rootdraft/main.go`
- doc paths cited in code comments → `git grep` before moving any doc

## Hard rules
- no marker `TO`+`DO` without `(#issue)` — qa.sh fails, untracked files included.
- never golden-refresh flag in tracked files; refresh = own reviewed step.
- test name = failure it prevents. Never assert mock called.
- `ponytail:` comment = deliberate ceiling. Keep unless removing shortcut.
- code comments, commits, human docs: normal English.
- no AI attribution anywhere (commits, PRs, docs).
- conventions detail: `CONTRIBUTING.md`. Visual gate: `docs/guides/gate-visual.md`.
