# 16. Installed corpora upgrade, and words carry their lemma

Date: 2026-10-01. Status: accepted.

## Context

The reading screen (ADR 0014) counts a root's forms the way the design does: raḥīm 116, raḥma 114, raḥmān 57. The app grouped a root's words by spelling, so وَرَحْمَتِى and رَحْمَةً were two forms. The lemma is in the Quranic Arabic Corpus file as the `LEM:` feature, in an extended Buckwalter transliteration, and the bundled corpus kept it only inside `words.morphology`.

A new column needs a new corpus. But `openWird` copied the bundled corpus only when no file was there ([db.dart](../../app/lib/data/db.dart)), so no installed phone ever received a newer one. Corpus 5's French never reached a phone that had corpus 4. The reader's own tables share that file.

## Decision

The ETL writes `words.lemma_key`, the lemma as the corpus publishes it, and `words.lemma`, its Arabic. The lemma is read from the same segment as the word's root. The digit the corpus uses to tell apart two lemmas spelled alike stays in the key and is dropped from the Arabic. The Buckwalter table covers every character the corpus uses, and any other character fails the build. `Check` holds r-ḥ-m to 116, 114 and 57.

The app upgrades an installed corpus. The app carries the version it ships as `bundledCorpusVersion`, held equal to the asset by a test. When the installed version is lower:

1. The new corpus is filled in `wird.db.next`.
2. Every table the corpus does not ship is copied across, and the senses fetched into `root_notes`.
3. The files are swapped by rename.

A failure before the swap keeps the old file.

## Alternatives

- **Read the lemma from `words.morphology` in the app.** No corpus change, but Buckwalter decoding would live in Dart, and corpus delivery would stay broken for the next column.
- **Keep counting by spelling.** The counts would be wrong for what the design means by a form.
- **Split the reader's tables into their own database and attach the corpus.** A cleaner upgrade, but every query that joins the reader's rows to the corpus would change.

## Consequences

A corpus rebuild now has to bump the version, in the ETL default and in `bundledCorpusVersion`, or it is not delivered. Developers no longer delete `wird.db` after a rebuild that bumps it.

The upgrade copies the corpus once per version, about 33 MB, on the launch after an update.

## Reversibility

The columns are additive, and the upgrade path can be turned off by not bumping the version. Signal to revisit: an upgrade that loses a reader's rows, or a launch made slow by it.
