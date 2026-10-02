# 23. The reader picks one of six reciters, and can hear each word spoken alone

Date: 2026-10-02. Status: accepted. Supersedes one line of ADR 0001: "Multiple reciters" is no longer deferred.

## Context

Wird shipped one reciter, Husary Muallim, fetched from everyayah.com at playback. A tapped word played as a clip cut out of its aya's file, using quran-align's CC BY 4.0 timings. The owner wants a choice of reciter, and a choice of voice for single words.

The timings have to belong to the exact recording that plays, or the highlight drifts. cpfair/quran-align `release-2016-11-24` aligns twelve everyayah recordings. Measured against the corpus text, six reconcile and six do not:

- Abdul Basit Mujawwad (14:1), Minshawy Mujawwad (13:1), Minshawy Murattal (10:1) and Tablaway (13:1) split one written word into three. `server/internal/timings` reconciles one extra index, not two.
- `Abdurrahmaan_As-Sudais_192kbps.json` opens with 154 KB of the aligner's crash log, so it is not valid JSON.
- Saood ash-Shuraym (12:76) and Minshawy Mujawwad (32:24) have an aya with no segments, which plays with no highlight.

One isolated word-by-word voice exists anywhere, quran.com's at `audio.qurancdn.com/wbw/`. The copies on archive.org and Hugging Face are re-uploads of the same files. Its file index is not the word's position: it counts the pause marks as words and drifts on 3,984 more words, 27,963 of 77,429 in all. For example, the second word of 12:1 is file `012_001_003.mp3`. The exact path is in the ingested quran.com responses as `words[].audio_url`.

The corpus has a 60 MiB budget (`scripts/qa.sh`, gate 7). Six recitations in the old `word_segments` shape would take it to about 60 MB.

## Decision

- The corpus carries six recitations: Husary Muallim (the default), Husary, Alafasy, Abdul Basit Murattal, Abu Bakr Ash-Shaatree and Hani Rifai. Ingest and ETL refuse a recitation that does not reconcile by name and keep the others. A recitation is refused when an aya has no timing, a word splits into more than two indices, or more than 100 words are untimed. The build fails only if the default is refused.
- `word_segments` is keyed `(recitation_id, word_id, seq)` and `WITHOUT ROWID`. `ayah_audio` holds one bare file name per aya, `096001.mp3`, the same in every reciter's folder. The corpus is 38 MB.
- Each reciter's everyayah folder is app config (`reciterFolders` in `app/lib/data/audio.dart`), beside the host. A host move stays a config change.
- The cache stays one flat directory. The folder is folded into the file name (`Alafasy_128kbps_096001.mp3`), so the sweep, the pins and the cache revision see every file.
- `words.wbw_path` stores each word's quran.com word-by-word path, copied from the API and never rebuilt from the position. A setting lets a tapped word play that file whole instead of the reciter's clip. The set's word files are fetched with its recitation into the same capped cache. A word with no file, or one not yet fetched, falls back to the clip.
- The choice is device-local, in `audio_pref`. A reciter that a later corpus drops falls back to the default.

## Alternatives

- **quranlab/quran-audio timings (44 recordings, CC BY 4.0).** Thirty-three of them were generated automatically in 2026 and nobody has checked them by ear. Taking them needs a new reader and spot checks. Left for later.
- **A per-aya override for the six that fail**, leaving one aya unhighlighted instead of refusing the reciter. It recovers five reciters, but the reconciliation gets a second rule. Left for later.
- **Word-by-word audio bundled in the app** (the Hugging Face Opus copy, about 400 MB). Too large, and it would be redistribution.
- **Building the word file name from the position.** It plays the neighbouring word on a third of the corpus, with no error.

## Consequences

- quran.com's Developer Terms (§3.1) cap caching of QF content at one week, outside Content Sync. Word-by-word audio is not in the Content Sync list. The capped cache can hold a word file longer than a week. The owner accepted this: the files are fetched at playback, the way everyayah's are, and never bundled or mirrored. If Wird takes the Developer Console route (`data/SOURCES.md`, open question 3), this is covered.
- Every shipped timings file needs its own CC BY attribution. `corpus_meta.notice` carries one per recitation, and the Sources screen must show them all (open item 4 in `data/SOURCES.md`).
- Switching reciter while offline leaves the set unplayable until its files arrive. The transport already says "Not downloaded" for that.
- `reciterFolders` and the corpus `recitations` must list the same slugs. A test holds them together.

## Reversibility

Dropping a reciter means removing one row from the ETL's table and one entry from `reciterFolders`, then rebuilding. Installs fall back to the default. Dropping the word voice means removing one setting; `wbw_path` can stay unread. Signals to revisit: a reciter whose highlight readers report as late, quran.com changing its word-by-word paths, or a written objection from Quran Foundation.
