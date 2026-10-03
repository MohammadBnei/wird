# 30. Play carries on from what the reader touched last

Date: 2026-10-03. Status: accepted.

## Context

The reading screen has two gestures on a word: a tap opens it, and a long-press hears it. The play button recites from the open word when nothing is playing, and resumes a pause.

Two things lost the reader's place. Any word heard took the player's turn and cleared the pause, so a reader who paused, long-pressed a word to check it, and pressed play started from the top of the sūra (`_take()` cleared `_paused` in `app/lib/data/audio.dart`). And a word tapped after a pause was ignored: play resumed the pause, not the word the reader had just moved to.

The design went through an interview and three rounds of adversarial review. The first two rounds broke a design built on separate flags (`_paused`, a hold, a touched word, a "primed" player) in 33 ways, most of them a flag left stale by a playback that finished late.

## Decision

- What the next press of play does is one value on `SetAudio`, `Resume`: `Held(place)`, `Touched(wordId)` or none. Only these events change it:
  - A pause sets `Held` at the word the recitation had reached.
  - A long-press while the recitation plays, or is still loading, also sets `Held`. The word is heard, and the recitation waits.
  - A long-press while paused leaves it alone.
  - A tap while paused sets `Touched`. A tap while playing moves nothing.
  - A start, a stop, or the end of the sūra clears it.
- The place follows the highlight and is always a word's start, so a resume never cuts into a word. It is not moved by position reports from a playlist still being replaced.
- A resume takes a turn of its own, like every playback, so the playback it replaced cannot settle the transport after it starts.
- When a word ends with the recitation held, the bar goes back to naming the recitation (the sūra or the one aya), so it can be resumed from any screen.
- Two knobs, each with today's old behaviour as one of its values:
  - `OpenAfterPause`: `restart` (default) or `resume`.
  - `HearWhileReciting`: `hold` (default), `resume` (carry on by itself after the word) or `cut`.
  - The reader sets them in Settings, stored per column in `playback_pref`, where NULL means the build default. A build sets the defaults with `--dart-define=WIRD_OPEN_AFTER_PAUSE` and `WIRD_HEAR_WHILE_RECITING`. The recitation reads them at each press, so a change from the drawer reaches a recitation already paused.
- The memory lives as long as the set does: leaving the reading screen keeps it, while a restart, another reciter or another sūra drops it.

## Alternatives

- **Persist the place across restarts.** It needs a schema and an upgrade path for a small gain. The bar already survives leaving the screen.
- **Count a long-press as the touch.** Hearing a word is checking it, not choosing where to recite from. Opening a word is the existing way the header picks a start.
- **A tap during the recitation moves the place.** A reader looking at words while listening would lose the recitation.
- **Carry on by itself after a heard word, as the default.** The reader chose to wait for play. It stays available as a knob.
- **Flags patched one by one.** This was tried in review and lost the place on ordinary sequences of presses.
- **Add columns to `audio_pref`.** That table is written as a whole row, which would reset columns the writer does not know.

## Consequences

- A word heard over the recitation now pauses it rather than ending it. The `cut` knob restores the old behaviour.
- `SetAudio` no longer has `_paused`, and `paused` means "the next press carries on". Code that read `paused` as "the player is paused" must read `resume`.
- The test fake player can hold a load in flight and report a position, so these sequences are tested rather than assumed.

## Reversibility

Cheap. Both knobs at `resume`/`cut` give back the old behaviour without a release, and the code is one class. Revisit if readers report play starting somewhere they did not expect.
