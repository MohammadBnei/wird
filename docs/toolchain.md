# Toolchain

What is installed on the build machine, and why Wird needs it. Every install appends
a row here; QA check 7 diffs this file against `brew leaves`, so the record is
falsifiable rather than a promise.

Rules: Homebrew only, never `sudo`, never touch the system Python, Ruby or Node, no
global `npm -g`.

| Tool | Version | Why |
| --- | --- | --- |
| Go | 1.27.1 | `server/` and `jidhr/`. `net/http` `ServeMux` routing needs the method-pattern syntax. |
| Docker | 29.8.0 | The only way Postgres 18 and the OIDC stub run locally. |
| Xcode | active at `/Applications/Xcode.app/Contents/Developer` | `simctl` and `xcodebuild`, which `scripts/device.sh` and any iOS build need. |
| iOS runtime | 18.6 (22G86) | `iPhone 16` and `iPad Pro 11-inch (M4)` boot on it under `simctl`. **Xcode 26.6 will not build for any of them**: it wants the iOS 26.5 simulator platform, an 8.5 GB download nobody has authorised, and until then `xcodebuild -showdestinations` reports every iOS destination ineligible. `scripts/device.sh` asks Xcode, not `simctl`, and falls through to the macOS target. |
| fvm | 4.3.1 | Pins the Flutter SDK per `.fvmrc`. Goldens are renderer- and font-version dependent, so an unpinned `brew upgrade` reddens every screen. |
| Flutter | 3.47.5 (pinned in `.fvmrc`, **not yet installed**) | The client. Installed in the phase that creates `app/`. |
| jq | 1.8.2 | `scripts/qa.sh` and `scripts/device.sh` assemble and read JSON with it. |
| gh | — | Creating and pushing the GitHub repository. |
| CocoaPods | 1.17.0 | The toolchain the plan calls for on any iOS Flutter build. This app resolves its plugins through Swift Package Manager instead, so nothing needs it today; it stays installed for the first plugin that ships no SPM manifest. |

## What QA check 7 diffs

`scripts/qa.sh` reads the list below and fails when something named here is not
installed. Append a line the moment you `brew install` something for Wird, and only
then — the table above is prose for a human, this list is what the gate can falsify.

<!-- brew-leaves:start -->
- cocoapods
- fvm
- gh
- go
- jq
<!-- brew-leaves:end -->

Not yet installed, needed by the phase that first uses it: `goose` (migrations,
phase 5).

## Notes

`go build ./...` does not work from the repo root on Go 1.27.1: the root is not itself
a module, and Go rejects the pattern with "directory prefix . does not contain modules
listed in go.work". Name the modules instead, as `scripts/qa.sh` does:

```bash
go build ./jidhr/... ./server/...
```
