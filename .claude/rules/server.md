---
paths:
  - "server/**"
  - "helm/**"
  - "Dockerfile"
  - "docker-compose.yml"
---
# server/ — Go API + tools

- Build/test from root: `go build ./server/... ./jidhr/...`, `go test -p 1 …`. Never `./...` at root (go.work, root ≠ module).
- `-p 1` required: store tests share real throwaway Postgres.
- `cmd/api` = wird-api, Dockerfile `--target api`. Env: `DATABASE_URL`, `OIDC_ISSUER`, `OIDC_AUDIENCE`, `API_ADDR` (local defaults). Only api migrates.
- Local: `docker compose up -d postgres oidc-stub` → `go run ./server/cmd/api`. Migrations embedded (`server/migrations`), run at startup via goose lib. No goose binary.
- Auth: validate JWT vs issuer JWKS only. Never mint tokens. Authentik public PKCE client. `OIDC_AUDIENCE` must = client id or every real token rejected. `docs/guides/authentik-wiring.md`.
- `cmd/adminweb` = wird-adminweb, Dockerfile `--target adminweb`, `helm/adminweb-values.yaml` (inert until infra-bootstrap work, ADR 0026). Authentik group gate, never per-reader (ADR 0004). `store.New`, never `store.Open` (no migrate). Exports `/reports.json`, `/verdicts.json`; `POST /reports/{id}` triage behind `http.CrossOriginProtection`. New store method → allowlist in `adminweb_test.go`. Reads `NOCTURNE_CSS`.
- Report body keys = `docs/adr/0002-sync-contract-vectors.json`. New key → server ships first (`DisallowUnknownFields` refusal permanent). Report column → `applyReport` + `sweepReportsSQL` (one list).
- Tafsir / iʿrāb / lexicon = placeholders, `"placeholder": true`. Never invent commentary.
- Go binaries built at root land as `/api`, `/etl`… → gitignored. Never `git add -A` blind.
- Deploy: push main → `.github/workflows/release.yml` → image tagged commit SHA → helm `values.yaml` bump → ArgoCD. DB from pigsty, secrets from Infisical.
- `internal/site/static` = public page at `/`. Verbatim vs adapted list: `internal/site/README.md`. Re-fetch from design project, never hand-edit verbatim files. Demos read `site-data.js` only → regen `python3 scripts/site-data.py`. Never put mockup data back.
- `GET /{file}` on outer mux: any new open route must be ≥2 segments or registered exactly, else page handler shadows it.
