# 15. The reading position is kept per sūra and synced

Date: 2026-10-01. Status: accepted.

## Context

The whole-sūra reader (ADR 0014) has no set to come back to, so the app needs to know where the reader stopped. A reader moves between a phone and a tablet, and reads more than one sūra at a time.

What the reader understood is a different fact. `ayah_understood` is declared, aya by aya, and many screens read it. A position is where the reader happens to be.

## Decision

A new op, `position_moved`, carries `{surah_id, word_id, updated_at}`. The server keeps one row per reader and sūra in `reading_positions` and streams it back as the change kind `reading_positions`. Both sides keep the latest `updated_at`.

- The server refuses a word outside its sūra, a position with no time, and one dated more than five minutes ahead of its own clock.
- The app writes the row and queues the op in one transaction, two seconds after the reader settles on a word, and on leaving the screen.
- The app flushes when it is put away, so the other device does not open at an old place.
- A build saves its cursor with how many change kinds it applies. A newer build that finds a cursor saved by an older one replays the stream once, so the positions an old build skipped are not lost.
- The table is cleared when another reader signs in.

## Alternatives

- **A column on `user_prefs`, through `prefs_set`.** One position per reader, not one per sūra.
- **Local only.** The owner wants the place to follow the reader across devices.
- **Derive the place from `ayah_understood`.** The next aya not understood is where the walk goes, not where the reader was reading.

## Consequences

The contract vectors (ADR 0002) carry a sixth change kind. The server must be deployed before the app, or the app's first move is refused and parked.

Last-write-wins trusts device clocks within five minutes. A move made offline on a phone whose clock runs slow can lose to an older move from a correct clock.

## Reversibility

The op and table are one-way once phones send them. Old builds ignore the kind, and the server accepts it forever.
