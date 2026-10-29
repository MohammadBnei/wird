# Changelog

## 0.1.0 - 2026-10-29

### Features

- **errors:** Keyed error bodies via ukubi-go errs (#48)
- **logs:** JSON logs on stdout, http.Server, ErrorLog, graceful shutdown (#49)
- **traces:** Opt-in OTLP traces for api, adminweb and rootd (#50)

### Fixes

- **cli:** [**breaking**] Stop using secrets as flag defaults (#44)
- **config:** [**breaking**] One Config per service binary, failing closed (#46)

### Other

- Go test -race and a commit check on pull requests (#43)
- Require jidhr in server/go.mod and build with GOWORK=off (#45)
- **config:** [**breaking**] One Config per CLI binary (#47)
- No mutable package state in server and jidhr (#51)
- Call ukubi-ci reusable checks; declare tier and trailer rule in CLAUDE.md (#52)
- **deps:** Pin ukubi-go v0.1.0 instead of its pseudo-version (#53)
- Stop depending on a committed go.work (#54)
- Cut versions and CHANGELOG with ukubi-ci release; servers show theirs (#55)

