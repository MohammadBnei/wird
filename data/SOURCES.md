# Corpus sources

`server/cmd/ingest` downloads the bytes, `server/cmd/etl` turns them into
`app/assets/corpus.db`:

```
go run ./server/cmd/ingest                      # -suras 1,2,103,112 for a partial run
go run ./server/cmd/etl -in ./data/raw/ -out ./app/assets/corpus.db
```

```
data/raw/chapters.json        surah metadata
data/raw/verses/NNN.json      one file per surah: ayas and their words
data/raw/segments/NNN.json    one file per surah: audio url, duration, word timings
data/raw/morphology.txt       one line per morphological segment
```

`data/raw/` is gitignored. `data/manifest.json` is what git holds instead: the
endpoints, a SHA-256 per file, the row counts, and the reconciliation numbers
below. A re-run of `ingest` skips files already on disk, so recovering from a
broken run costs the files it did not finish, not 38 MB.

## Provenance and licence

Every "reached how" below is an unauthenticated public endpoint. Terms were read
on 2026-09-22; the URL of each is given so the reading can be checked rather than
believed.

| Table | Source | Licence I read | Redistributable inside a closed app bundle? |
| --- | --- | --- | --- |
| `surahs` (incl. `revelation_order`) | `api.quran.com/api/v4/chapters` | [Quran Foundation Developer Terms](https://api-docs.quran.foundation/legal/developer-terms/) §2.2, §3.1 | **Yes, conditionally** — see *The one-week rule* |
| `ayahs.text_uthmani`, `words.text_ar` | `api.quran.com/api/v4/verses/by_chapter` | the text is [Tanzil](https://tanzil.net/download/)'s, which quran.com credits; delivery is governed by the QF terms | **Yes** for the text, unmodified and attributed; the delivery path carries the QF conditions |
| `words.gloss_en`, `words.translit` | same endpoint | QF terms treat it as QF Content; **no upstream author is named anywhere I could find** | **Could not determine** — conditionally yes under the QF terms, with an unnamed source underneath |
| `words.root_letters`, `words.form`, `words.morphology`, `roots` | [`mustafa0x/quran-morphology`](https://github.com/mustafa0x/quran-morphology), a modified fork of Quranic Arabic Corpus 0.4 | the fork states **none**; upstream is [GPL](https://corpus.quran.com/license.jsp) plus a no-modification clause on the [download](https://corpus.quran.com/download/) | **No, twice over** — see *The morphology is the blocker* |
| `ayah_audio`, `word_segments` | `api.quran.com/api/v4/recitations/12/by_chapter` | QF terms §3.1, and the timings are **not** in the Content Sync list | **No, as it stands** — see *Timings are not syncable* |
| the MP3s themselves (not mirrored yet) | `mirrors.quranicaudio.com/everyayah/Husary_Muallim_128kbps/` | [quranicaudio.com](https://quranicaudio.com/about): "may be downloaded and used for personal use free of charge", "you may not use these files for commercial purposes" | **No, as it stands** — personal use is not distribution |

### The one-week rule

This is the clause that decides most of the table, and it was unread until now.
QF Developer Terms §3.1 forbids a developer to

> Cache or store QF Content longer than **1 week**, except where (a) QF has
> expressly permitted longer storage, or (b) the QF Content is available through
> the Content Sync APIs listed under Content Available for Offline Sync. If you
> rely on exception (b), you must perform a next sync at least every **7 days**
> and apply all available changes.

and §2.2 permits display inside an application provided "QF Content and raw API
data are not sold, sublicensed, or redistributed", where redistribution means
"offering QF Content or raw API data to others **as data**".

A shipped `corpus.db` is storage without end, so exception (b) is the only route:
an active account in the Developer Console, credit to Quran Foundation in the
app, and a re-sync at least every seven days. The
[Content Sync resources](https://api-docs.quran.foundation/docs/content_apis_versioned/4.0.0/resources-sync/)
are `quran_core` (Uthmani verse text and surah metadata), `mushafs`,
`translations`, `tafsirs`, `recitations`, `chapter_recitations`,
`word_by_word_translations`, `word_by_word_transliterations` and `articles`.

So the surah metadata, the verse text and the word-by-word rows *can* be bundled
— but only by an app that syncs weekly. **That is a product decision the
architecture has not made**: the plan ships `corpus.db` as an immutable asset and
negotiates a `corpus_version`, which is not a seven-day sync. Either the app
grows the sync, or the text comes from Tanzil directly (below), where no such
condition exists.

### The text has an unconditional source

Tanzil's [terms of use](https://tanzil.net/download/), verbatim:

> Permission is granted to copy and distribute verbatim copies of the Quran text
> provided here, but changing the text is not allowed. The text can be used in
> any website or application, provided that its source (Tanzil Project) is
> clearly indicated, and a link is made to tanzil.net to enable users to keep
> track of changes.

That permits exactly what this app does, with attribution and a link, and no
weekly obligation. quran.com credits Tanzil for its Uthmani text, so taking the
text from tanzil.net removes the API terms from the text row entirely. The cost
is the one this repo already knows about: a different source is a different
tokenisation until proven otherwise, and the segment timings are numbered against
quran.com's words. Re-run the reconciliation before switching, do not assume.

### Timings are not syncable

Per-word audio timings appear in no Content Sync resource — `recitations` covers
ayah audio files, not the `segments` arrays. No exception applies, so the
one-week limit stands and `word_segments` cannot ship inside the bundle on these
terms.

The named alternative is [`cpfair/quran-align`](https://github.com/cpfair/quran-align),
which quran.com itself credits for the segmentation: its released timing data is
**CC BY 4.0**, which permits bundling with attribution. Its indices are over a
space-split of Tanzil's text, which is not quran.com's word numbering, so a switch
needs the reconciliation below redone, not copied.

### The morphology is the blocker

Unchanged in substance from the previous reading, and worse in detail:

- The Quranic Arabic Corpus is published under the **GNU GPL**
  ([licence](https://corpus.quran.com/license.jsp)), and its
  [download](https://corpus.quran.com/download/) adds "Permission is granted to
  copy and distribute verbatim copies of this file … CHANGING IT IS NOT ALLOWED",
  with attribution and a link to corpus.quran.com. Copyleft against a closed
  binary is the case the GPL exists to catch.
- The fork we actually download **carries no licence file at all**, and its
  README documents substantial edits to the data — which the upstream
  no-modification clause forbids on its face.

Two independent obstacles, either of which is enough. This is a release blocker
for a human, not a coding task: it needs a decision about the app's licence, a
differently-licensed morphology source, or written permission.

## What is still open

1. Who wrote the word-by-word English gloss and transliteration served by
   quran.com. Nothing on
   [quran.com/about-us](https://quran.com/about-us) or in the API documentation
   names an author, and the QF terms defer to "any source-specific license
   requirements" without saying which. Someone has to ask.
2. Whether the app takes on a seven-day content sync, or moves the text to
   Tanzil and the timings to quran-align.
3. Where the MP3s come from once they are mirrored. quranicaudio.com grants
   personal use only. quran.com credits the
   [King Fahd Glorious Qur'an Printing Complex](https://qurancomplex.gov.sa/) for
   recordings; its terms were not read for this pass.

## What the data actually is

Corrections that cost a day each to find, kept here so they are not re-found.

- **A segment tuple is `[word_start_index, word_end_index, start_ms, end_ms]`** —
  zero-based, end exclusive, over the same word numbering the verses endpoint
  uses. QUL documents a three-tuple `[segment_index, start_ms, end_ms]`; reading
  that shape puts a word index into a timestamp. Reading element 1 as a one-based
  word position is the subtler mistake: it agrees with the real shape for every
  segment covering exactly one word, which is 77,320 of 77,347 of them, and
  silently drops the other 27. `ingest` asserts the shape; `etl` still reads the
  one-based position, which is why its untimed-word count is 87 and the
  manifest's is 26.
- **Segments come from quran.com's recitation 12, not QUL resource 112**, though
  both are al-Ḥuṣarī Muallim. QUL's word numbering splits words the text keeps
  whole — 12 segments against 11 words in 2:21 — and word text and timings must
  come from one segmentation or every highlight after the split lands on the
  wrong word.
- **`revelation_order` is quran.com's field.** `ingest` asserts it is a
  permutation of 1..114; it matches the Egyptian standard at the points the plan
  names (96→1, 68→2, 1→5, 2→87). Nobody has checked all 114 against a printed
  muṣḥaf.
- **Audio paths are relative** (`husary-muallim/001001.mp3`). The origin is
  config with a bundled default, so a host that moves does not cost an App Store
  release.

## Reconciliation, from `data/manifest.json`

| Number | Value | What a wrong value would mean |
| --- | --- | --- |
| ayas where word numbering disagrees | **0** | a word's timing belongs to another word |
| ayas with a segment past the last word | 5 | the muqaṭṭaʿāt: the reciter splits a word the text keeps whole |
| multi-word spans / words they time | 27 / 61 | words the aligner could not split, dropped by a one-word-per-segment parser |
| words with no timing | 26 across 16 ayas | the highlight freezes for those words |
| overlapping segment pairs | 0 | — |
| segments ending before they start | 8 | the ETL clamps them |
