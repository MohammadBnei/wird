# Contributing to Wird

## The gate

`./scripts/qa.sh` is the verdict. It writes `qa-report.json` and exits non-zero on
failure. Nothing merges on an opinion; it merges on that exit code.

A red test is never deleted in the gate it reddens. Deleting a dead test is a
separate commit in a later phase, with the doctrine violation named.

Goldens are never refreshed from inside the gate. `scripts/qa.sh` fails if the
flutter golden-update flag appears anywhere in tracked files or the staged diff.
Refreshing goldens is an owned, reviewed step of its own.

## Test naming

Every test's name states the failure it prevents, in the language of the product:
`replayed outbox flush counts one prayer, not two`. If you cannot name the failure,
the test has no purpose and does not get written.

Never assert that a mock was called. Assert observable behaviour, or real state in a
real throwaway database.

## The `ponytail:` convention

A `ponytail:` comment marks a **deliberate** simplification — the simplest thing that
works, chosen with its ceiling known. It is intent, not an oversight, and it is not
noise to be cleaned up. Leave it in place.

The comment names the ceiling and the upgrade path, so the next reader can tell
whether the ceiling has been reached:

```dart
// ponytail: linear scan over <= 8 derivatives. Index it if a root ever renders all 103.
```

```go
// ponytail: one connection, no pool. Pool it when ingest runs concurrently.
```

Removing a `ponytail:` marker is only correct when you are removing the shortcut it
describes. `ponytail:` is a ceiling that has not been hit yet; `// TODO` is work that
is owed and needs an issue number.

## Comments

Low. A comment earns its place by saying what the code cannot — an invariant, a
ceiling, a reason. No file headers, no banners, no commented-out code, no comment
that restates the line under it.

## Prose

Code, comments and commit messages are written in normal English sentences.
