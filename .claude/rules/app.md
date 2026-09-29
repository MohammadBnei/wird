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
- Visual gate: render at 402x874, look at PNGs, compare vs `docs/design/prayer-app-screens.html`. `docs/guides/gate-visual.md`.

## Run locally (macOS)
- `cd app && fvm flutter run -d macos`. Only local target exercising voice-follow (mic + sherpa_onnx resolve). Simulator mic useless.
- `scripts/device.sh` picks iPhone → iPhone 16 sim → macOS. Never picks Mac while sim exists.
- After ANY corpus rebuild: `rm ~/Library/Containers/dev.bnei.wird/Data/Documents/wird.db`. `openWird` (`lib/data/db.dart`) installs asset only when file absent → stale db → new-column reads throw.
- Voice weights in sibling `voice/` dir, survive db delete. Trail log: `…/Documents/prayer-trail.log`, truncated each prayer.
- Android trail: `adb shell run-as dev.bnei.wird cat /data/data/dev.bnei.wird/databases/prayer-trail.log`.
