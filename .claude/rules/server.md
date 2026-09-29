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
- `cmd/api` = wird-api, only binary in image. Env: `DATABASE_URL`, `OIDC_ISSUER`, `OIDC_AUDIENCE`, `API_ADDR` (local defaults).
- Local: `docker compose up -d postgres oidc-stub` → `go run ./server/cmd/api`. Migrations embedded (`server/migrations`), run at startup via goose lib. No goose binary.
- Auth: validate JWT vs issuer JWKS only. Never mint tokens. Authentik public PKCE client. `OIDC_AUDIENCE` must = client id or every real token rejected. `docs/guides/authentik-wiring.md`.
- `cmd/adminweb` separate binary, not in image. Authentik group gate, totals only (ADR 0004). Reads `docs/design/nocturne-styles.css`.
- Tafsir / iʿrāb / lexicon = placeholders, `"placeholder": true`. Never invent commentary.
- Go binaries built at root land as `/api`, `/etl`… → gitignored. Never `git add -A` blind.
- Deploy: push main → `.github/workflows/release.yml` → image tagged commit SHA → helm `values.yaml` bump → ArgoCD. DB from pigsty, secrets from Infisical.
