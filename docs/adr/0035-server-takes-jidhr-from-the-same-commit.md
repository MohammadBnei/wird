# 35. Server takes jidhr from the same commit, through a require and a local replace

Date: 2026-10-28. Status: accepted.

## Context

`server/cmd/jidhrcorpus` imports `jidhr/pkg/root`, but `server/go.mod` had no require for jidhr. The committed `go.work` hid that, so `go build ./jidhr/... ./server/...` passed while `server` could not build on its own. The ukubi Code Standard asks every module to build standalone, and `go.work` is to leave the repo (W3b). No other repo imports `server`.

## Decision

`server/go.mod` requires `github.com/MohammadBnei/wird/jidhr v0.0.0` and replaces it with `../jidhr`. CI and `scripts/qa.sh` build each module on its own with `GOWORK=off`. CI also sets `GOTOOLCHAIN=local`, so a module whose go line is newer than the installed Go fails the build.

## Alternatives

- **Keep `go.work` as the only link.** A missing require stays invisible until the workspace goes.
- **Require a pseudo-version of a main commit.** CI would build `server` against a frozen jidhr, not the one in the PR, so a `pkg/root` change that breaks `jidhrcorpus` would pass. Every `pkg/root` change would also need a manual bump to a commit that already exists on main.
- **Move `jidhrcorpus` into `jidhr/`.** It reads the server's Postgres through `server/internal/store`, an internal package jidhr cannot import.

## Consequences

- Deleting the require fails `GOWORK=off go -C server build ./...`.
- A `pkg/root` change and its `jidhrcorpus` fix land in one PR, and CI tests them together.
- Any build of `server` needs `jidhr/` next to it. The Dockerfile already copies both.
- jidhr can still be tagged as `jidhr/v*` for outside users; the replace only applies inside this repo.

## Reversibility

Cheap: drop the replace and pin a version. The signal would be a second repo that builds `server`, or `server` and `jidhr` moving to separate repos.
