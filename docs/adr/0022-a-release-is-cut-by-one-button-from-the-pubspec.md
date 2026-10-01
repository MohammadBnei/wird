# 22. A release is cut by one button, and the pubspec holds the only version

Date: 2026-10-01. Status: accepted. Amends ADR 0019 (how a release is started).

## Context

ADR 0019 made a version tag build and publish the APK. Cutting one still took five hand steps: edit `version:` in `app/pubspec.yaml`, edit `appVersion` in `report.dart` to match, refresh the report screen's golden, merge, then type and push a tag that matched. Each step was a place to drift.

It drifted on the first release. Version 0.0.1 changed the pubspec and `appVersion` but not the golden, and `main`'s CI runs no Flutter test, so the stale screenshot reached `main` unnoticed. The next release could only be started by someone who knew all five steps, and a tag pushed by hand would publish whatever commit it named, tested or not.

The owner asked for one source of truth for the version and a controlled chain of events, started by a button.

## Decision

- **The pubspec's `version:` line is the only place the version is written.** The release build passes it to the app as `--dart-define=WIRD_VERSION`; `appVersion` reads that, and every other build reports `dev`. The report screen's golden shows `dev` and never moves on a release.
- **A release starts from one button.** `release-app.yml` is run by hand on `main` with patch, minor or major. It runs `app-checks.yml` (`flutter analyze` and the app tests without the goldens), computes the next version and build number from the pubspec, commits `Release vX.Y.Z` and the tag, and pushes both atomically. A moved `main` refuses the push and nothing is tagged.
- **The tag starts the build by dispatch.** A tag pushed with the built-in token starts no workflow, so the button dispatches `apk.yml` on the tag. `apk.yml` no longer starts on a tag push: a tag pushed by hand publishes nothing. On a tag it refuses to build unless the tag matches the pubspec and is on `main`.
- **App checks run on pull requests too.** The same `app-checks.yml` runs on every PR that touches `app/`, so the checks that gate a release are the checks a merge already passed.

## Alternatives

- **A release PR.** The button opens a PR with the bump and merging it tags. One more review of a one-line change that a computer wrote. Rejected for the slower chain; easy to add later.
- **A local script.** `scripts/release.sh` bumping and tagging from a laptop. The chain would then depend on whoever's machine runs it, and on that machine's state.
- **Keep the `appVersion` constant.** A test pinned it to the pubspec, but a release still edited three files and refreshed a golden. That is the drift this ADR removes.
- **`package_info_plus`.** Reads the version at runtime, at the cost of a dependency and a platform channel for one string the build already knows.
- **A personal access token or a GitHub App, so the tag push itself starts `apk.yml`.** A long-lived secret to rotate, where a dispatch needs none.

## Consequences

- Nobody edits a version or types a tag. The build number always rises, so Android always accepts the update.
- Builds made outside the release workflow, on a laptop or from a manual run on `main`, report `dev`. A bug report from one is visibly not from a release.
- `main` now runs Flutter on Linux for every app PR. The goldens stay Mac-only, behind the `golden` tag; `./scripts/qa.sh` on a Mac is still the merge gate.
- The release commit is pushed with the built-in token, so it starts no image build. The image does not change on a release; only `/download/android` does.

## Reversibility

Cheap. Restoring the `push: tags` trigger on `apk.yml` brings back hand-made tags; deleting `release-app.yml` removes the button. Signals to revisit: branch protection that refuses the workflow's push to `main`, or a second app (iOS) that needs its own build from the same tag.
