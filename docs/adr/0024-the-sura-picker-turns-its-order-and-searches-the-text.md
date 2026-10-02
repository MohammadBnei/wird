# 24. The sūra picker turns its own order, and searches the text of the Qur'an in memory

Date: 2026-10-02. Status: accepted.

Style: caveman lite. Full sentences, short, no filler. A reader with no context must follow it.

## Context

The index and the prayer's passage chooser draw one shared list, `SuraPicker` ([sura_picker.dart](../../app/lib/features/index/sura_picker.dart#L104-L153)). Until now it listed the sūras in the reading order from Settings, which defaults to revelation order, and searched only sūra names, numbers and a reference such as `2:255`.

The updated design (`docs/design/sura-picker.html`, used by `docs/design/wird-prayer.html`) adds two things:

- A Muṣḥaf / Revelation toggle above the list, with juz headers in written order and Makkī / Madanī headers by revelation.
- Search by the words of an aya and by root.

A reader who reads by revelation still knows most sūras by their written number. Changing the order in Settings to find one would also move their walk.

The corpus already ships every aya's Uthmani text, Pickthall's English and Rashid Maash's French (6236 rows each), and each word's root in `words.root_letters`. It has no search index, and Postgres holds no aya text. The app must work offline.

## Decision

- The picker opens in the reader's order and has a toggle that turns it for as long as the picker is open. Settings is not touched.
- Given the database, the picker also searches:
  - the ayas whose Arabic, English or French holds the query;
  - the ayas that carry a root typed as letters or as its transliteration.
- The text is read once per database into memory and folded the way a query is folded ([aya_search.dart](../../app/lib/features/index/aya_search.dart#L23-L152)):
  - Arabic through `recitationKey`, with the waṣl alif kept as an alif.
  - Latin through `foldLatin`, which now also folds French accents.
- The root lookup reads the same `words.root_letters` as the constellation.

## Alternatives

- **Keep the order in Settings only.** One order everywhere is simpler, but finding Yā Sīn by "36" in revelation order means scrolling or a trip to Settings that moves the walk.
- **Folded columns or an FTS5 table in `corpus.db`.** Faster to open, but it needs a corpus rebuild and a version bump. FTS5 is also not guaranteed in Android's system SQLite without a new native dependency.
- **Search in Postgres.** The server has no aya text, and the search would fail offline.

## Consequences

- Opening the picker reads about 2.5 M characters once per session. On a slow phone this is the first thing to measure.
- A query of under three letters finds no ayas, and a root is looked for only when the query is two to four Arabic letters or a short transliteration.
- Words are matched as folded substrings, spaces removed, so a short English word can match inside a longer one.

## Reversibility

Cheap. The search is one class behind the picker. If opening the picker is measured slow, move the folded text into the corpus, or an FTS table, without changing the picker.
