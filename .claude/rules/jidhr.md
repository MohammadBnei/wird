---
paths:
  - "jidhr/**"
---
# jidhr/ — Arabic root engine

- Own Go module, standalone product. No DB, no network, no key.
- `go run ./jidhr/cmd/rootd` → :8081. API doc: `jidhr/cmd/rootd/README.md` (keep in sync with handlers).
- Data: `jidhr/testdata/quran.json`. Rebuild: `go run ./server/cmd/jidhrcorpus` from `app/assets/corpus.db` → engine + app answer from one body of data. Never hand-edit json.
- Senses (meanings) = server-owned since ADR 0010. jidhr answers word → root, not sense authority.
