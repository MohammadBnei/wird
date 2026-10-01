# 12. The French under each word comes from The Last Dialogue, matched by its Arabic

Date: 2026-09-30. Status: accepted.

## Context

A reader who picks French reads the aya in French (Rashid Maash) and the sense
of a root in French, but the meaning under each word was English. quran.com
serves no French word-by-word: `language=fr` answers English and labels it
English (`data/SOURCES.md`, measured 2026-09-27). corpus.quran.com is English
only too, with the same glosses.

The Last Dialogue publishes a complete French word-by-word as web pages: 114
sura pages, and 28 section pages for the seven long suras. Each word is a card
holding a part-of-speech label, the Arabic, the French and a transliteration.
The site reserves all rights and marks the work as beta. The Last Dialogue
granted Wird its use by email on 2026-09-30, with no attribution required.

Their cards do not line up one-to-one with Wird's words. Measured on the
2026-09-30 pages: 6,143 of 6,236 ayas match word for word; 86 ayas are missing
one to four cards; 3 cards carry the wrong Arabic (39:37, 50:34, 53:50); 4 spell
إِلَّآ as إِلَّا.

## Decision

- `ingest` saves the pages under `data/raw/tld/`. The ETL
  ([glosses_fr.go](../../server/cmd/etl/glosses_fr.go)) reads the cards and writes
  the French into a new column, `words.gloss_fr`. The corpus version goes to 5.
- A card is matched to a word by its Arabic, reduced to base letters, along a
  longest common subsequence per aya. Never by position. A word with no
  matching card keeps its English gloss: 128 of 77,429 words.
- `Corpus.Check` refuses a corpus in which any aya has no French word at all.
  That is the shape of a missing page or a parser that stopped reading one.
- The app shows `gloss_fr` to a reader in French and falls back to `gloss_en`.
  An install from before corpus 5 gets an empty `gloss_fr` column at open and
  stays English (`_ensureFrenchGlossColumn` in `app/lib/data/db.dart`).

## Alternatives

- **Draft French glosses with a model**, the way `rootdraft` drafts senses. No
  licence question, but 34,000 distinct word–gloss pairs a person would have to
  review, and a machine gloss dressed as a reference one.
- **Keep the glosses English** and say so. That was the state before this ADR,
  and it is what the owner asked to end.
- **Pair cards by position.** Simpler, and wrong in 89 ayas: every word after a
  skipped card would read its neighbour's meaning.

## Consequences

- A French reader reads French under nearly every word. A few words in 89 ayas
  read English among French ones. The About screen says so.
- The glosses are a third party's beta work. A correction on their site reaches
  Wird only by re-ingest and rebuild.
- Installs from before corpus 5 do not get the French until the app can replace
  its corpus tables on a version change while keeping the reader's own tables.

## Reversibility

Cheap. Drop the column from the ETL schema and the two app queries, and the app
falls back to English everywhere. Undo if the grant is withdrawn or the pages'
quality turns out to be worse than the English they replace.
