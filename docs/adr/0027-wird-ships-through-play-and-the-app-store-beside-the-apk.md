# 27. Wird ships through Google Play and the App Store, beside the APK

Date: 2026-10-03. Status: accepted. Extends ADR 0019 (the APK) and ADR 0022 (the release button).

## Context

Until now Wird shipped as a sideloaded arm64 APK at `/download/android` (ADR 0019), and iOS was not built in CI, because no Apple certificate existed. A paid Apple developer team (`KJYVRCCHU4`) now exists, and a Google Play personal account is about to be created. People already run the APK, and their phones must not be stranded.

The constraints:

- **Play App Signing re-signs every install.** If Play held a key of its own, a phone with the APK could never take a Play update, and the App Links fingerprint in `helm/values.yaml` would stop matching.
- **The APK's version code is `2000+N`.** Flutter adds the ABI offset to split APKs (`app/android/app/build.gradle.kts`). A Play build at plain `N` would look like a downgrade to every APK phone.
- **Only `apk.yml` can read the keystore.** The Infisical identity trusts only this workflow file, run from a tag or main.
- **`flutter build ipa` cannot pass an App Store Connect API key, and exits 0 when the export fails.**
- **A new personal Play account must run a closed test** with at least 12 testers for 14 days before it can publish to production.
- **Both stores require a privacy policy URL and in-app account deletion.**

## Decision

- **Play App Signing holds the APK's key.** The key is exported once by the `pepk` job in `apk.yml`, encrypted to Google's public key, and never touches a laptop. CI uploads with a separate upload key (`WIRD_ANDROID_UPLOAD_*`), which Google can reset if it leaks.
- **The Play bundle is built at `--build-number=2000+N`.** That is the same code as the arm64 APK, so either channel updates the other.
- **The bundle is a second job, `aab`, inside `apk.yml`.** It uploads to the closed track (`alpha`), and promotion to production is done by hand in the Play Console. The job stays off until `PLAY_RELEASE_ENABLED` is set.
- **iOS is `ipa.yml` on a `macos-26` runner.** It runs `flutter build ios --config-only`, then `xcodebuild archive` and `-exportArchive`, using an Admin App Store Connect API key with cloud signing. The upload goes to TestFlight, and submission is done by hand. The job has its own Infisical identity, which cannot read the Android keystore. `release-app.yml` dispatches it only when `IOS_RELEASE_ENABLED` is set.
- **iPad is kept.** That means iPad screenshots are required.
- **No fastlane.** Store listings are typed into each console from `docs/guides/releasing-to-stores.md`.
- **The sign-in callback becomes a universal link on iOS.** It uses the Associated Domains entitlement and `/.well-known/apple-app-site-association`, so the paste-back fallback is no longer the normal path.

## Alternatives

- **Let Play generate its own app signing key.** APK phones could not update from Play, and App Links would need a second fingerprint.
- **Play at plain `N`.** Every APK phone would see the Play build as older than what it has installed.
- **fastlane.** A Ruby toolchain and a metadata tree, to save typing a listing that changes rarely.
- **`flutter build ipa`.** A failed upload would leave the job green.
- **iPhone only.** Fewer screenshots, but iPad readers get a stretched phone app.

## Consequences

- Each release can produce an APK, a Play bundle and a TestFlight build from one button press, once the two repo variables are set.
- Moving between the APK and Play is an update in both directions only while the two version codes stay aligned. Never upload to Play by hand at a different code.
- The upload key and the App Store Connect key are new secrets in Infisical. The `ipa.yml` identity needs infra-bootstrap work.
- `/privacy.html` must change in the same pull request as anything that changes what the app sends.

## Reversibility

The workflows are cheap to undo. Play App Signing with the APK's key cannot be undone: Google holds that key from then on. The signal to drop a channel would be a store rejecting Wird for good, in which case the APK path still works on its own.
