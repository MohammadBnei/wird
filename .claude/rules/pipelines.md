---
paths:
  - "data/**"
  - "server/cmd/ingest/**"
  - "server/cmd/etl/**"
  - "server/cmd/rootdraft/**"
  - "server/cmd/senseseed/**"
  - "server/cmd/jidhrcorpus/**"
  - "server/internal/lane/**"
  - "server/internal/rootsense/**"
---
# Pipelines — corpus + senses

## Corpus
- `ingest` → `data/raw/` (gitignored) → `etl` → `app/assets/corpus.db`.
- Every table → licence row in `data/SOURCES.md`. New source w/o row = ✗.
- Full `ingest` run also saves The Last Dialogue French word pages → `data/raw/tld/` (index + 114 sura + 28 section pages). ETL matches card→word by Arabic letters (LCS), never position. `Corpus.Check` ✗ if any aya has zero French words. ADR 0012.
- After rebuild: `jidhrcorpus` (refresh `jidhr/testdata/quran.json`) + bump `-corpus-version` + `bundledCorpusVersion` → installs upgrade themselves (`.claude/rules/app.md`).

## Senses (ADR 0010)
- `rootdraft` (LLM + `data/root-sense-prompt.md`) → TSV → `senseseed` → Postgres → `/v1/senses` → app cache.
- `senseseed` = command, not migration: corrections re-seed w/o schema churn.
- Draft log append-only, prompt digest per row → generations diff side by side.

## Prompt `data/root-sense-prompt.md` — traps
- Loaded at runtime by `server/cmd/rootdraft/main.go`. Path load-bearing.
- Never put a number in clause-count rule, not even "typical". Any figure = target, not bound (measured: cap "2-6" → all 30 roots at 6; no number → mean 8.17, range 4-13).
- Cap removal exposed 3 rules it enforced by accident, now explicit: one sense ≠ many clauses; heaviest sense (occurrence counts) leads, not Lane's order; incidental denotation dressed as verb ("to be a swift horse") forbidden same as noun.
- Negative examples get echoed. State test, not counterexample.
- Judge prompt change on held-out roots, never tuned-on ones.
- Lane's Lexicon not used as source (`docs/research/lane-lexicon.md`); `{{LANE}}` placeholder + `internal/lane` still exist — read doc before touching.
