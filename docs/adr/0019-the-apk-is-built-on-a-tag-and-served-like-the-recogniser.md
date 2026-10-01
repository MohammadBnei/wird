# 19. The APK is built on a tag and served like the recogniser

Date: 2026-10-01. Status: proposed.

## Context

Release APKs were built by hand and copied into a shared file bucket. Nobody else could reproduce them, and a link to one either expired in seven days (a presigned URL) or did not exist (the store allows no anonymous reads). We want a signed APK built by CI and a download link that never expires.

The facts that shape it:

- The only self-hosted runner has 9.6 GB free, 4 GB of RAM and no JDK. Its disk is the image build cache.
- The object store answers SigV4 only. A single PUT through its public route is cut at 60 seconds.
- The release keystore cannot be replaced. If it is lost or leaked, no build can ever update an installed Wird again.
- `/models/` already presigns a key in the voice model bucket and answers 302 ([models.go](../../server/internal/api/models.go#L35)).

## Decision

- `.github/workflows/apk.yml` runs on a `v*` tag on a GitHub-hosted runner. It builds one APK per ABI, checks that the release key signed it, and uploads with multipart to `app/<tag>/` in the voice model bucket. It then mirrors that prefix to `app/latest/`.
- The keystore moves into Wird's own Infisical project. It is moved, not copied, so it lives in one place once CI has proven the copy. The store key is copied there, because the pod and the bucket playbook keep reading it from the root project. CI reads them over OIDC with an identity that only this repository may use and that can read only this project. CI never reads from the shared project that every app can read, nor from the root project, where any identity that reads a row could also read every platform credential.
- wird-api serves `GET /app/...` the way it serves `/models/`: it presigns the key under `app/` and answers 302 ([models.go](../../server/internal/api/models.go#L46)).
- iOS is not built. There is no Apple certificate or provisioning profile in the estate.

## Alternatives

- **A dedicated APK bucket** — cleaner quota and key, but it needs one more key in wird-api to serve it. Worth doing when the two prefixes need different access.
- **The shared file bucket** — it has no quota and nothing prunes it, and it also holds other projects' files.
- **Build on every push to main** — about 150 MB per push into a store with no expiry. A tag is a deliberate release.
- **Build on the self-hosted runner** — it has no room for the toolchain.

## Consequences

- A release is `git tag vX.Y.Z && git push --tags`, after the pubspec version is bumped. The workflow fails on a tag that disagrees with the pubspec.
- `/models/app/...` also reaches the APKs. This is harmless while both are public.
- `GET /download/android` ([ADR 0018](0018-the-public-site-is-served-by-the-api.md)) stays: it serves one digest-named object set by hand, for the public page. `/app/latest/` is overwritten on each tag, so a download resumed across a release can mix two builds. Android then refuses the file, so the reader retries rather than installs something broken. Pointing `WIRD_APK_KEY` at a CI build would unify the two.
- CI holds the voice model bucket's key, and that key can write. A bad workflow could overwrite the recogniser files phones download. We accept this for now. A bucket of its own for APKs, with its own key, removes it.
- The store key lives in two projects: the root project, which the pod and the bucket playbook use, and Wird's project, which CI uses. Rotating it means updating both.
- `app/<tag>/` is never deleted. Pruning old tags becomes a step in the workflow if they pile up.
- The App Links fingerprint list must carry the release certificate, or sign-in on a CI build stays stuck in the browser.

## Reversibility

Cheap. Deleting the workflow and the route undoes it. Move to a dedicated bucket when the APKs need access rules that differ from the voice model's.
