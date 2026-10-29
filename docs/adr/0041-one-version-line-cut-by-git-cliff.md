# 41. One version line, cut by git-cliff on every push to main, for the server and the app

Date: 2026-10-29. Status: accepted. Supersedes ADR 0022 in part (where the version comes from, and that the button tags). Amends ADR 0005 (the image tag stays the commit; the image now also carries a version) and ADR 0019 (the tag is no longer checked against the pubspec).

## Context

The ukubi Code Standard has every server repo cut its versions with ukubi-ci's reusable `release.yml`. That workflow runs git-cliff over the Conventional Commit subjects since the last `X.Y.Z` or `vX.Y.Z` tag. It writes `CHANGELOG.md`, commits `chore(release): vX.Y.Z` to `main` and pushes the tag with it in one atomic push. The image is built from that commit with the version as a build-arg, and the binary says which release it is.

wird had no server version. ADR 0005 tagged the image with the commit and nothing else. The app had its own line, `v0.0.1` to `v0.0.14`. `release-app.yml` raised `version:` in `app/pubspec.yaml`, committed `Release vX.Y.Z`, which is not a Conventional subject, and tagged it (ADR 0022). Two workflows tagging `v*` in one repo would fight over the next number. ukubi-ci's README says this lane must make the button read the computed version instead.

Two facts shaped the server side. First, `TestPackageState` (ukubi-go's pkgstate analyzer) refuses a package var that `-ldflags -X` could set. An embedded string is allowed. Second, the Infisical identities of `apk.yml` and `ipa.yml` are bound to runs from a `v*` tag (or, for apk, from `main`), so the tags must keep their `v`.

## Decision

- **One line of `vX.Y.Z` tags, cut only by `release.yml`.** It runs checks, then ukubi-ci `release.yml` at the commit `checks.yml` already pins (v0.2.1), then the build, then the deploy. The first release after v0.0.14 is v0.1.0: there are `feat` commits since, and a breaking change at `0.x` raises the minor.
- **The image tag stays the commit**, now the release commit's: the helm values pin it, as before. The version goes in as `--build-arg VERSION`. Between releases it is `X.Y.Z+<sha>` on `main`, and `X.Y.Z-dev+<sha>` in a dry run on another branch. The Dockerfile writes it to `server/internal/buildinfo/version.txt`, which the binaries embed. The committed file says `dev`, so a local build never claims a release. It also sets `org.opencontainers.image.version`.
- **Both servers say their version.** It is on the start line of wird-api and wird-adminweb, at wird-api's open `GET /version` as `{"version":"X.Y.Z"}`, and in the adminweb footer. JSON, because `/download/android/version` beside it already answers in that shape. drop answers `text/plain`; a probe reading both reads one key more here.
- **The app ships the tags; it never makes one.** The release button takes the newest `vX.Y.Z` on `main` and dispatches `apk.yml` and `ipa.yml` on it. It refuses when `main` has commits past the tag that are not bots' own, and when that version is already published. The build name is the tag. The build number is `git rev-list --count` at the tag: it only rises, and was 548 at v0.0.14 against the pubspec's 15. So the arm64 version code jumps from 2015 to 2548 or more. The pubspec `version:` line stays, for local builds only.
- **rootd and the CLIs stay unversioned.** No pipeline builds them, so any version they printed would always be `dev`. One is added the day a pipeline builds one.

## Alternatives

- **`-ldflags -X main.version`**, as drop does. pkgstate refuses it, and a `//ukubicheck:table` var cannot be passed to a logger or returned.
- **A second tag line for the app** (`app-vX.Y.Z`). The Infisical subjects are bound to `v*`, and a second line would need a second git-cliff config. Rebinding identities is not possible while Infisical is down.
- **Keep the pubspec as the app's source.** Then a release would still need a non-Conventional commit on `main`, and two workflows would tag `v*`.
- **Drop the Markdown and `helm/` path filters**, so every push gets a run. A docs-only push would then cut a patch release and rebuild both images. Kept instead, with the recovery written in `release.yml` and in the button's refusal: `gh workflow run release.yml --ref main`.

## Consequences

- Every push to `main` that passes the checks and touches code is a tagged release, with a `chore(release)` commit and a `CHANGELOG.md` entry. A dispatch on `main` releases, builds and deploys the same way.
- A push touching only Markdown or `helm/` gets no run. So does one that lands while a code commit's run is in flight: that run then releases nothing, because ukubi-ci leaves newer commits to their own run. The next code push releases them, or a dispatch on `main` does. Until then the app button refuses.
- A failed `release` job now stops the build and the deploy. Before, only the checks gated them.
- `cancel-in-progress` is keyed on the ref, so a branch dispatch cannot cancel `main`'s run after its tag is pushed.
- After a partial failure (apk failed, ipa passed), pressing the button again fails the ipa run, because its build number is already used. Re-run only the failed workflow on the tag.
- Past 999 commits, the arm64 code (`2000 + N`) runs into the range Flutter gives the next ABI. That is harmless while only arm64 ships, and the code still rises.

## Reversibility

Cheap for the server: remove the `release` job and the build-arg, and the image is what it was. The tags and `CHANGELOG.md` stay as history. For the app, going back to the pubspec means a pubspec build number above the commit count, because Android refuses a lower version code. Undo it if git-cliff's bumps keep surprising whoever presses the button.
