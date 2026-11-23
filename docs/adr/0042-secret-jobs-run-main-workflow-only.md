# 42. The jobs that read release secrets run main's workflow file only

Date: 2026-11-23. Status: accepted. Amends ADR 0022, ADR 0019 and ADR 0028 (where the build runs).

## Context

`release-app.yml` dispatched `apk.yml` and `ipa.yml` with `--ref "$TAG"`. GitHub runs the workflow file as it exists at the ref, so a tag pushed by hand on an unreviewed commit carried its own workflow. That workflow could drop the "tag is on main" check and still match the Infisical identities, which accepted `apk.yml` from `refs/tags/v*` (Android keystore) and any `v*` tag (App Store key). The checks in the workflow were guarding secrets with code the attacker controls.

## Decision

- `release-app.yml` dispatches both workflows on `main`: `gh workflow run apk.yml --ref main -f tag="$TAG"`.
- `apk.yml` and `ipa.yml` take a `tag` input. They refuse a tag unless the run is on `refs/heads/main`, check the `vX.Y.Z` shape, check out `refs/tags/$TAG` with full history, and require the tag commit to be an ancestor of `origin/main`. The tag reaches scripts through the `TAG` env var, never inline.
- Publishing and the Play upload run only when `tag` is set. A manual run from `main` with no tag builds and uploads, as before. `ipa.yml` always needs a tag.
- The Infisical identities accept only `main`: the Android one binds `workflow_ref` to `apk.yml@refs/heads/main`; the iOS one binds its subject to `ref:refs/heads/main` plus a `workflow_ref` claim for `ipa.yml@refs/heads/main`. Those bindings live in Infisical, not git.

## Alternatives

- **Keep the tag ref and trust the in-file checks.** Rejected: the file is the attacker's.
- **Protect `v*` tags in the repository settings.** Good defence in depth, but it guards the tag, not the workflow file the identity trusts.

## Consequences

- A hand-pushed tag cannot read a secret: its workflow file never runs with the identities.
- A retry of a failed build is **Actions -> apk (or ipa) -> Run workflow** on `main` with the tag typed in the `tag` input, no longer a tag chosen as the ref.
- `release-app.yml` finds an already-shipping run by apk.yml's run title (`apk vX.Y.Z`), as the run's branch is now `main`.

## Reversibility

Cheap: revert the workflows and widen the identity bindings. We would not, as it reopens the hole.
