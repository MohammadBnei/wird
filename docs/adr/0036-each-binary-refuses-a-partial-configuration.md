# 36. Each binary refuses a partial configuration

Date: 2026-10-28. Status: accepted, amended by 0037. Amends ADR 0008.

## Context

`wird-api`, `wird-adminweb` and `rootd` each read the environment with a per-key fallback, spread over `main` and, for the API, over `internal/api` at route construction and on every request. A missing value was never an error:

- An unset `DATABASE_URL` or `OIDC_ISSUER` started against `localhost` and the OIDC stub. A pod whose Secret had not landed came up and failed later, less plainly.
- ADR 0008 records that with any of the four `WIRD_MODELS_S3_*` values missing, the API is healthy and only a reader's Download button answers 503. That was the accepted trade-off.
- `wird-adminweb` with `OIDC_CLIENT_SECRET` but no `OIDC_CLIENT_ID` verified against the audience `wird-admin`, which the proxy never issues for. With the id but no secret, it checked keys the proxy never signs with.
- `rootd` with no `ROOTD_API_KEY` served `/v1` unauthenticated, logged only as `authenticated=false`. An unreadable `ROOTD_RATE` logged a warning and used 5, and a negative, NaN or infinite rate turned the limiter off.

The ukubi Code Standard (§5) asks for one `Config` per binary, built from `load(getenv)`, validated once at start, failing closed with every error at once, and no other code reading the environment.

## Decision

- Each of the three binaries has `config.go` with `load(getenv)` and `fromProcess()`. `load` reports every problem at once with `errors.Join`, in one `config refused` line, and the process exits 1 before it opens anything. A refusal names variables, never values.
- `wird-api` and `wird-adminweb` require `DATABASE_URL`, `OIDC_ISSUER` and an audience. `WIRD_DEV=1` is the one switch that lets the local compose stack fill whatever is unset. It changes nothing else.
- A half-set store (`WIRD_MODELS_S3_*`, `REGION` included) refuses to start. All unset is still no store and a 503. `WIRD_APK_KEY` without a store, and `WIRD_APK_VERSION` without a key, refuse too.
- `OIDC_CLIENT_ID` and `OIDC_CLIENT_SECRET` come together or not at all, with or without `WIRD_DEV`.
- `rootd` requires `ROOTD_API_KEY` unless `ROOTD_DEV=1`. `ROOTD_RATE` must be `0` (off) or a finite rate of at least `0.25` a second, so the burst is at least one token.
- `internal/api` takes an `api.Config` from `cmd/api` and reads no environment. `server/env_test.go` refuses every other reader in `server/` and `jidhr/`.

## Alternatives

- **Keep the fallbacks and log loudly.** A log line in a healthy pod is read by nobody. The 503 in ADR 0008 was exactly that.
- **A `-dev` flag instead of `WIRD_DEV`.** It would give each binary a flag parser it does not have, for one boolean, and `load(getenv)` would become `load(args, getenv)`. The CLIs (W4b) take flags; the services do not.
- **`ROOTD_OPEN=1` instead of `ROOTD_DEV=1`.** A keyless `rootd` is what the README offers a reader trying it on their own machine, and that is a dev run. A listener anyone else reaches should have a key. One name across the services (`*_DEV`) is easier to remember than one per effect.
- **Refuse a half-set store only in production.** There is no production flag to read, and a half-set store on a laptop is the same mistake.

## Consequences

- A Secret row that renders empty is now a pod that exits, not a healthy pod with a broken Download button. The chart's default rolling update keeps the old pod serving while the new one crashloops, so the rollout stalls rather than taking the API down. ArgoCD can then show Synced with an unfinished rollout: the deploy check must look at the new ReplicaSet being Ready, and at the pod log for `config refused`.
- A missing download credential now also stops sync, the trade ADR 0008 made the other way. A credential is either meant or not; half of one is a mistake to see at deploy time.
- Every local run needs `WIRD_DEV=1` (or `ROOTD_DEV=1`, or a key). The docs and the agent context say so.
- `rootd`'s "no key" mode is an explicit opt-in.
- Every new variable goes into `config.go`, its `envVars` list and the doc table in the same PR, or `TestConfigDocumented` fails. Variables read by libraries (pgx's `PG*`, `net/http`'s proxy variables, `crypto/x509`'s `SSL_CERT_*`) are listed beside each table, not in it.
- The env ban reads files outside the `server` module (`../jidhr`, `../docs`), which the Go test cache does not recheck, so CI (`release.yml`) and `scripts/qa.sh` run the Go tests with `-count=1`.

## Reversibility

Cheap: restoring a default is one line in a `load`. The signal to undo a refusal is a deployment that needs a partial configuration on purpose; none does today: as infra-bootstrap writes them, prod's `wird-config` and `wird-admin-config` Secrets and the helm values carry every value these rules require.
