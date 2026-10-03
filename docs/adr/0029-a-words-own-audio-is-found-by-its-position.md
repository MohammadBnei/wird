# 29. A word's own audio is found by its position, not by the API's path

Date: 2026-10-03. Status: accepted. Amends ADR 0023: replaces its `words.wbw_path` decision.

## Context

ADR 0023 copied each word's word-by-word path from the quran.com API (`words[].audio_url`). It said the host's file index counts pause marks as words, so the position could not be trusted.

Readers heard the wrong word. Checked against `audio.qurancdn.com/wbw/` on 2026-10-03, the opposite is true. The host numbers its files by word. The API's `audio_url` is the one that counts the marks.

- For 6,234 of 6,236 ayas, file `n` exists and file `n+1` returns 404, where `n` is the aya's word count. Every aya was probed.
- 27,962 of 77,429 words had an `audio_url` that differed from their position. All of them sit after a pause mark (ۖ ۗ ۘ ۙ ۚ ۛ ۜ), ۩ or a leading ۞. No aya without a mark drifts. ADR 0023's "3,984 more" does not exist.
- Of those, 23,507 played a neighbouring word and 4,455 named a file past the end of the aya, which returns 404. A tap on them was silent.
- 2:2 has seven words and seven files. The API names its last word `002_002_009.mp3`, which does not exist. ADR 0023's example, 12:1, has five words and five files: its second word is `012_001_002.mp3`, not `003`.
- File sizes against the recited length of each word favour the position in 53 of 57 ayas compared.
- The live API still returns the shifted paths, so ingesting again does not fix it.
- The host has no file for two words: 12:8 word 15 and 79:1 word 2. The API names the same missing paths.

## Decision

- The ETL builds `words.wbw_path` as `wbw/SSS_AAA_WWW.mp3` from the sūra, the aya and the word's position (`server/cmd/etl/load.go`). The API's `audio_url` is no longer read.
- Every word now has a path. The two words the host lacks fail to load and fall back to the reciter's clip, like any word file that cannot be fetched.
- The corpus goes to version 8, so installs upgrade on their next launch.

## Alternatives

- **Keep the API's path.** It plays the wrong word for over a third of the Qur'an.
- **Correct the API's path by subtracting the marks before each word.** It reaches the same numbers by a longer road. It depends on the API's mark handling staying the same, which it has already failed to match once.
- **Probe the host for every word during the build.** That is 77,429 requests per build to confirm a rule that held for every aya. A full probe stays a manual check instead (below).

## Consequences

- A tapped word plays itself.
- Nothing upstream signals a renumbering any more. The host was re-uploaded between November 2024 and August 2025, and the API was never updated, so a future change could also arrive silently. The check is the probe recorded above: for each aya, file `n` returns 200 and `n+1` returns 404.
- Word files already cached stay correct. Their names already held the host's content, and the new paths never name a file past the end of an aya.

## Reversibility

Cheap. It is one line of the ETL and a corpus rebuild. Revisit if readers report a word that plays its neighbour again, or if the probe finds an aya whose files do not end at its word count.
