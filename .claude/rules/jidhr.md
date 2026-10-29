---
paths:
  - "jidhr/**"
---
# jidhr/ — Arabic root engine

- Own Go module, standalone product. No DB. No network except OTLP traces when `OTEL_EXPORTER_OTLP_TRACES_ENDPOINT` set. Only dep = ukubi-go (+ otel), ADR 0040 → jidhr's ukubi-go pin = server's (`server` `TestJidhrShipsTheUkubiGoItWasTestedWith`). Key required unless `ROOTD_DEV=1` (ADR 0036).
- `ROOTD_DEV=1 go run ./jidhr/cmd/rootd` → :8081. Config `cmd/rootd/config.go`, table in README (doc test). API doc: `jidhr/cmd/rootd/README.md` (keep in sync with handlers).
- Data: `jidhr/testdata/quran.json`. Rebuild: `WIRD_DEV=1 go run ./server/cmd/jidhrcorpus` (local compose PG; else `DATABASE_URL`, neither → `config refused`, ADR 0037) from `app/assets/corpus.db` → engine + app answer from one body of data. Never hand-edit json. server takes jidhr via `replace => ../jidhr` in `server/go.mod` → `pkg/root` change + jidhrcorpus build in same commit, no pin to bump. ADR 0035.
- Senses (meanings) = server-owned since ADR 0010. jidhr answers word → root, not sense authority.
- No mutable package var, no `init()`. Read-only data → `//ukubicheck:table <reason>`, only read (`slices.Clone` before append/alias). Checked from `server/state_test.go` `TestPackageState` (`-count=1`).
