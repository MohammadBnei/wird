# 25. The reader recites the whole sūra, and streams what is not on disk

Date: 2026-10-02. Status: accepted. Amends ADR 0023: a word with no file on disk no longer falls back to the clip when it can be fetched.

## Context

Since ADR 0014 the reading screen shows a whole sūra, but the recitation still carried only the ayas around the open word: the reading width, five ayas by default (`readingWidth`, `app/lib/data/sets.dart#L338`). Readers hit three faults:

- The play button stopped after 96:5 in the middle of al-ʿAlaq.
- Opening a word outside those ayas built a new player and disposed the old one, so a running recitation went silent.
- A word pressed past those ayas was silent in both voices: `playWord` looked words up only in the carried tracks, and played only files already on disk. A press does not open the word, so nothing carried it.

The per-aya play button sat only on the open word's aya, and the root sheet could not be put away for plain reading.

The cache is capped at 200 MB (`audioCacheBytes`). Al-Baqarah in Husary Muallim is about 217 MB, more in Hani Rifai. Pinning a whole sūra would hold the cache over its cap, and an unbounded cache is a copy of the recitation, which ADR 0023 rules out.

## Decision

- The recitation carries every aya of the open sūra. The same sūra carried again keeps its player.
- A file on disk plays from disk. Anything else is handed to the player as its public URL (`AudioCache.sourceFor`) and fetched as it plays. This is the runtime fetch the licence comment in `app/lib/data/audio.dart` already describes, with nothing kept.
- The screen keeps the open aya and the next `aheadAyas` (10) on disk, pinned, with the open aya's word files first. The files the player has loaded are pinned too, so eviction never pulls a file from under a recitation.
- The play button recites from the open word to the end of the sūra. A hold starts from the first aya. A held aya number recites that aya alone. A tap still marks it understood.
- One core runs every playback (`SetAudio._run`): the turn, the pause state, the notifiers and the player's error stream. One helper owns the bar (`Recitation._own`).
- A player error, such as an aya that cannot be reached offline, pauses the player and reports the playback as failed, so the bar goes dark.
- A word in the word-alone voice plays its own file from disk if it is there. Offline, when only its aya is on disk, it plays the reciter's stretch. Otherwise it streams its own file.
- Downloads are written under a `.part` name and renamed when whole.
- A drag down on the root sheet's handle folds the sheet to the handle. The choice is kept in `display_prefs.root_open`.

## Alternatives

- **Download first, append to the playlist as files land.** This was the first plan. A file landing while the last cached aya plays changes no index, so the player reaches the end and stops. Recovering from that needs append-on-arrival, a restart after completion, and a fetch-then-play path for every press. Streaming removes all three.
- **Pin the whole sūra.** This breaks the cap on long sūras, as above.
- **Keep a play button beside every aya.** It turns the reading into a column of buttons. The hold on the number the reader already taps costs no space.

## Consequences

- A reader online hears any aya or word of the sūra at once. Offline, only the window is playable, and past it the recitation ends silently.
- A streamed file is fetched again on every play until the window reaches it. That is more traffic than download-first for a reader who replays the same distant aya.
- A word clip streamed from a URL depends on the host answering byte-range requests. Both hosts answer `206` to ExoPlayer's user agent. Seek accuracy on a streamed clip has to be checked on a device against `seekCalibration`.
- `pathsToKeep` no longer has a caller in the app. The walk's next set is not prefetched by the reader any more.

## Reversibility

Cheap. `sourceFor` is the one place that chooses a URL over a file. Returning null for anything not on disk restores download-only playback. The signals to undo it: streamed word clips landing on the wrong word, or traffic complaints from readers on metered data.
