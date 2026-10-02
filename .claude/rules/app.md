---
paths:
  - "app/**"
---
# app/ — Flutter client

- Flutter via fvm only: `fvm flutter …`. Version pinned `.fvmrc` (3.47.5). Goldens depend on renderer + fonts → unpinned upgrade reddens every screen.
- Offline-first: `app/assets/corpus.db` bundled (SQLite). Sets generated on device. User writes → outbox → `POST /v1/sync`; pull `GET /v1/changes`.
- Senses ≠ bundled. Fetched from `/v1/senses`, cached (`lib/data/senses.dart`). ADR 0010.
- l10n: en + fr ARB (`lib/l10n`). Every user string through ARB.
- Tests: `fvm flutter test`. Test corpus = real shipped `corpus.db` copy (`test/corpus.dart`), not fixture.
- Visual gate: render at 402x874, look at PNGs, compare vs `docs/design/prayer-app-screens.html` (prepare + picker: `wird-prayer.html`, `sura-picker.html`). `docs/guides/gate-visual.md`.

## Run locally (macOS)
- `cd app && fvm flutter run -d macos`. Only local target exercising voice-follow (mic + sherpa_onnx resolve). Simulator mic useless.
- `scripts/device.sh` picks `$WIRD_E2E_DEVICE` → cabled iPhone → iPhone 16 sim → macOS. Gate on Mac: `WIRD_E2E_DEVICE=macos ./scripts/qa.sh` (user wants macOS, not sim).
- Corpus rebuild → bump `bundledCorpusVersion` (`lib/data/db.dart`) = `corpus_meta.corpus_version`, test enforces. Installed db upgraded on next launch, reader tables + `root_notes` carried (`upgradeCorpus`). Same version rebuild → no upgrade → delete `wird.db` by hand.
- Voice weights in sibling `voice/` dir, survive db delete. Trail log: `…/Documents/prayer-trail.log`, truncated each prayer.
- Android trail: `adb shell run-as dev.bnei.wird cat /data/data/dev.bnei.wird/databases/prayer-trail.log`.
- Debug builds also write `prayer-audio.f32` beside trail: raw f32 @16 kHz, every sample handed to recogniser → replay off device.
- Tree not `dart format`-clean (SDK formatter ≠ committed style). Never `dart format lib`/`test` whole → format only files you touched, or diff explodes.
- Two Wird builds on one Mac share container `dev.bnei.wird` → same `wird.db` → `disk I/O error` (6922) in the other. Stop one by PID, never `pkill -f wird.app`.
- Release = Actions → `release-app` → patch/minor/major, on main. Only path. Never hand-edit `version:` in `pubspec.yaml`, never push `v*` tag (apk.yml ignores tag push). Version single source = pubspec line → `--dart-define=WIRD_VERSION`; non-release builds report `dev`. ADR 0022, `docs/guides/releasing-the-apk.md`.
- CI `app-checks.yml` = analyze + `flutter test --exclude-tags golden` (Linux). New golden test file → `@Tags(['golden'])` + `library;` at top, or CI fails on pixel drift.
