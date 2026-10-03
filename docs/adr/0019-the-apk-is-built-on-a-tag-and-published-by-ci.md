# 19. A version tag builds the APK and publishes it at /download/android

Date: 2026-10-01. Status: proposed, amended by ADR 0022 (a release is started by a button, not a hand-pushed tag), extended by ADR 0027 (Play and the App Store). Amends ADR 0018 (the APK key is set by CI, not by hand).

## Context

[ADR 0018](0018-the-public-site-is-served-by-the-api.md) added `GET /download/android`. It presigns the object named by `WIRD_APK_KEY` and answers 302 ([apk.go](../../server/internal/api/apk.go#L21)). Publishing a build was manual: build and sign on a laptop, upload under a digest-named key, set the key in `helm/values.yaml`. Nobody else could reproduce a build, and the page answered 503 until someone did all three.

The facts that shape automating it:

- The only self-hosted runner has 9.6 GB free, 4 GB of RAM and no JDK. Its disk is the image build cache.
- The object store answers SigV4 only. A single PUT through its public route is cut at 60 seconds.
- The release keystore cannot be replaced. If it is lost or leaked, no build can ever update an installed Wird again.
- `release.yml` already pushes a values bump to main from a GitHub-hosted runner, and ArgoCD rolls the pod from it.

## Decision

- `.github/workflows/apk.yml` runs on a `v*` tag on a GitHub-hosted runner. It builds the arm64 APK, checks that the release key signed it, and uploads it with multipart as `android/wird-<sha12>.apk` in the voice model bucket.
- The same job sets `WIRD_APK_KEY` in `helm/values.yaml` on main and pushes, the way `release.yml` bumps the image tag. ArgoCD rolls the pod and the route hands out the new build. A manual run uploads but never publishes.
- The keystore moves into Wird's own Infisical project. It is moved, not copied, so it lives in one place once CI has proven the copy. The store key is copied there, because the pod and the bucket playbook keep reading it from the root project. CI reads both over OIDC with an identity that can read only that project, and that accepts only this workflow file from a tag or from main.
- iOS is not built. There is no Apple certificate or provisioning profile in the estate.

## Alternatives

- **A route of its own that serves `app/<tag>/` and an overwritten `app/latest/`** — built first, then dropped. It duplicated `/download/android`, and an overwritten key lets a resumed download mix two builds.
- **A dedicated APK bucket** — CI would hold a key that cannot touch the voice model. It needs a playbook change and one more key in the pod. Worth doing if the risk below starts to matter.
- **Build on every push to main** — about 50 MB per push into a store with no expiry, and every merge would replace what the page hands out. A tag is a deliberate release.
- **Build on the self-hosted runner** — it has no room for the toolchain.

## Consequences

- A release is: bump the pubspec, merge, push a matching tag. The workflow fails on a tag that disagrees with the pubspec.
- Only arm64 is published. A 32-bit phone has no download.
- CI holds the voice model bucket's key, and that key can write. A bad workflow could overwrite the recogniser files phones download. We accept this for now.
- The store key lives in two projects. Rotating it means updating both.
- Old `android/` objects are never deleted. Pruning becomes a workflow step if they pile up.

## Reversibility

Cheap. Deleting the workflow returns publishing to the manual steps in `docs/architecture/deploy.md`. Move to a dedicated bucket when CI's write access to the voice model becomes a concern.
