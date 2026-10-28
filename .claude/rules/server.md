---
paths:
  - "server/**"
  - "helm/**"
  - "Dockerfile"
  - "docker-compose.yml"
---
# server/ — Go API + tools

- Build/test per module, as CI + qa.sh: `GOWORK=off go -C server build ./...`, `GOWORK=off go -C server test -p 1 ./...`. Never `./...` at root (root ≠ module). jidhr = require + `replace => ../jidhr` in `server/go.mod`, not go.work. ADR 0035.
- `-p 1` required: store tests share real throwaway Postgres.
- `cmd/api` = wird-api, Dockerfile `--target api`. Config: `cmd/api/config.go` `load(getenv)` only env reader; table `docs/architecture/api.md` (doc test). `DATABASE_URL`, `OIDC_ISSUER`, `OIDC_AUDIENCE` required unless `WIRD_DEV=1`. `WIRD_MODELS_S3_*` all-or-none, half → refuse start. Only api migrates.
- Local: `docker compose up -d postgres oidc-stub` → `WIRD_DEV=1 go run ./server/cmd/api` (adminweb same). Migrations embedded (`server/migrations`), run at startup via goose lib. No goose binary.
- Auth: validate JWT vs issuer JWKS only. Never mint tokens. Authentik public PKCE client. `OIDC_AUDIENCE` must = client id or every real token rejected. `docs/guides/authentik-wiring.md`.
- `cmd/adminweb` = wird-adminweb, Dockerfile `--target adminweb`, `helm/adminweb-values.yaml` (inert until infra-bootstrap work, ADR 0026). Authentik group gate, never per-reader (ADR 0004). `store.New`, never `store.Open` (no migrate). Exports `/reports.json`, `/verdicts.json`; `POST /reports/{id}` triage behind `http.CrossOriginProtection`. New store method → allowlist in `adminweb_test.go`. Config `cmd/adminweb/config.go`; `OIDC_CLIENT_ID` + `OIDC_CLIENT_SECRET` both or neither, dev too.
- Report body keys = `docs/adr/0002-sync-contract-vectors.json`. New key → server ships first (`DisallowUnknownFields` refusal permanent). Report column → `applyReport` + `sweepReportsSQL` (one list).
- Tafsir / iʿrāb / lexicon = placeholders, `"placeholder": true`. Never invent commentary.
- Go binaries built at root land as `/api`, `/etl`… → gitignored. Never `git add -A` blind.
- Deploy: push main → `.github/workflows/release.yml` → image tagged commit SHA → helm `values.yaml` bump → ArgoCD. DB from pigsty, secrets from Infisical.
- `internal/site/static` = public page at `/`. Verbatim vs adapted list: `internal/site/README.md`. Re-fetch from design project, never hand-edit verbatim files. Demos read `site-data.js` only → regen `python3 scripts/site-data.py`. Never put mockup data back.
- `GET /{file}` on outer mux: any new open route must be ≥2 segments or registered exactly, else page handler shadows it.
- Env ban: `server/env_test.go` walks server/ + jidhr/; only `config.go` per binary reads env (`envAllowed`). New env var → `config.go` + `envVars` + doc table, same PR. Guard reads outside module → CI runs `go test -count=1`.
