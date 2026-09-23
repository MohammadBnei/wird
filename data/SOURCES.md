# Corpus sources

`server/cmd/ingest` downloads the bytes, `server/cmd/etl` turns them into
`app/assets/corpus.db`:

```
go run ./server/cmd/ingest                      # -suras 1,2,103,112 for a partial run
go run ./server/cmd/etl -in ./data/raw/ -out ./app/assets/corpus.db
```

```
data/raw/chapters.json                          surah metadata
data/raw/verses/NNN.json                        one file per surah: ayas and their words
data/raw/segments/NNN.json                      one file per surah: audio url, duration, word timings
data/raw/quranic-corpus-morphology-0.4.txt      put there by hand; see below
```

`data/raw/` is gitignored. `data/manifest.json` is what git holds instead: the
endpoints, a SHA-256 per file, the row counts, and the reconciliation numbers
below. A re-run of `ingest` skips files already on disk.

**The morphology is not downloaded.** <https://corpus.quran.com/download/> serves
a form, not the file: it asks for an email address and for the terms of use to be
accepted before it hands over `quranic-corpus-morphology-0.4.txt`. Accepting the
terms is a person taking the licence, so the ingest does not work around it — it
looks for the file, and if it is not there it prints the URL, says an email
address is asked for, names the path, and exits non-zero.

## The morphology: Quranic Arabic Corpus 0.4

Wird reads the file **corpus.quran.com distributes, unmodified**. Until 2026-09-23
it read [`mustafa0x/quran-morphology`](https://github.com/mustafa0x/quran-morphology),
an edited fork that ships the annotation with the copyright block removed — which
breaks the no-modification term and the attribution term at once. Using upstream
verbatim fixes both.

Its terms of use, verbatim from <https://corpus.quran.com/download/>:

```
# Quranic Arabic Corpus (Version 0.4)
# Copyright (C) 2011 Kais Dukes
# License: GNU General Public License
#
# The Quranic Arabic Corpus includes syntactic and morphological
# annotation of the Quran, and builds on the verified Arabic text
# distributed by the Tanzil project.
#
# TERMS OF USE:
#
# - Permission is granted to copy and distribute verbatim copies
#   of this file, but CHANGING IT IS NOT ALLOWED.
#
# - This annotation can be used in any website or application,
#   provided its source (the Quranic Arabic Corpus) is clearly
#   indicated, and a link is made to http://corpus.quran.com to enable
#   users to keep track of changes.
#
# - This copyright notice shall be included in all verbatim copies
#   of the text, and shall be reproduced appropriately in all works
#   derived from or containing substantial portion of this file.
```

| Condition | What satisfies it |
| --- | --- |
| verbatim copies only; changing it is not allowed | The file on disk is upstream's, byte for byte, and its SHA-256 is in `data/manifest.json`. Nothing writes to it: the ETL reads it and derives `corpus.db`, which the terms address separately as a work derived from the file. `ingest` refuses a copy whose copyright block is missing, and names the reason — that check is what stops a fork sliding back in. |
| source clearly indicated, with a link to corpus.quran.com | The copyright block, both notices in it, travels into the database: `corpus_meta.notice` carries it verbatim, so it ships inside the app rather than living in a repo file no reader ever sees. `roots.sources` names the corpus per row. The ETL refuses to build a database whose notice does not mention the corpus, Kais Dukes and corpus.quran.com. |
| the notice reproduced in derived works | Same column. The app has to surface it in the about screen too; `corpus_meta.notice` is where it reads it from. |
| GNU General Public License | **Wird is AGPL-3.0** (repo root `LICENSE`). There is no closed binary to keep copyleft out of, so the question the previous release blocker raised is answered rather than deferred. |

Kais Dukes died in March 2024. The terms are final: there is nobody to ask for
different ones, and meeting them as written is the whole of the job.

### Tanzil is underneath the corpus, not beside it

The corpus's own notice says it "builds on the verified Arabic text distributed by
the Tanzil project", and the file carries Tanzil's copyright block after its own
(Uthmani text 1.0.2, CC BY-ND 3.0, same verbatim-only and attribution terms). So
the chain for anything root-shaped is **Tanzil text → Quranic Arabic Corpus
annotation → `corpus.db`**, and both notices are in `corpus_meta.notice` because
both are in the file. The Arabic Wird actually renders comes from quran.com, which
credits Tanzil for the same Uthmani text — the same origin reached a second way,
which is why the row below names both.

### What changed when the fork was dropped

Suras, ayas, words, word numbering and timings are identical, and the morphology
still agrees with quran.com's word count for all 6,236 ayas. The annotation
differs, and every difference is an edit the fork had made:

| | fork | upstream 0.4 |
| --- | --- | --- |
| distinct roots | 1,651 | **1,642**, of which 1,636 are spelled exactly as the fork spelled them |
| roots the fork added | آدم, سبأ, قريش, برزخ, مروة, رمضان and others — proper nouns and loanwords | upstream leaves them unrooted: 374 words lose a root, 73 gain one |
| roots respelled | ندي, طمأن, and ناس under أنس | ندو, طمن, and ناس under its own root نوس (241 words) |
| words whose root letters differ | — | 767: 374 unrooted upstream, 73 newly rooted, 320 respelled |
| verb form | marked on 2,231 participles and nouns as well as verbs | marked on verbs only; 13 words the fork called IV are XII upstream |

Two decisions the ETL makes while reading the file, both recorded here because
they are readings and not copies:

- **A root radical comes back as hamza, not bare alef.** The published root field
  is written in the 28-letter Buckwalter alphabet, which folds every hamza onto
  `A`; no Arabic root has a bare alef radical, and corpus.quran.com renders those
  radicals as أ. So `qrA` becomes `قرأ`, which is also what the fork had. The seat
  is what the fold costs: لؤلؤ comes back as لألأ, and هات as هأت. Two roots of
  1,642. `jidhr` keys its own roots the same way, but a join between the two
  should fold rather than assume.
- **A verb with no form tag is Form I.** The file tags II to XII and never I.
  Taken as "no form", the label would go blank on 14,555 words. Participles of
  Form I verbs are left blank, because a participle is not itself a verb form —
  that is the 2,231-row difference above.

`words.morphology` keeps upstream's Buckwalter for forms, lemmas and tags; only
roots are decoded, because only roots are rendered. `roots.sources` carries the
file's name; the corpus is named in full, with its copyright block, in
`corpus_meta.notice`.

## Provenance and licence

Every "reached how" below other than the morphology is an unauthenticated public
endpoint. Terms were read on 2026-09-22 and re-read on 2026-09-23; the URL of each
is given so the reading can be checked rather than believed.

| Table | Source | Licence I read | Redistributable inside the app bundle? |
| --- | --- | --- | --- |
| `surahs` (incl. `revelation_order`) | `api.quran.com/api/v4/chapters` | [Quran Foundation Developer Terms](https://api-docs.quran.foundation/legal/developer-terms/) §2.2, §3.1 | **Yes, conditionally** — see *The one-week rule* |
| `ayahs.text_uthmani`, `words.text_ar` | `api.quran.com/api/v4/verses/by_chapter`; the text is [Tanzil](https://tanzil.net/download/)'s, which quran.com credits | Tanzil: verbatim copies, attribution, a link to tanzil.net. Delivery is governed by the QF terms | **Yes** for the text, unmodified and attributed; the delivery path carries the QF conditions |
| `words.gloss_en`, `words.translit` | same endpoint | QF terms treat it as QF Content; **no upstream author is named anywhere I could find** | **Could not determine** — conditionally yes under the QF terms, with an unnamed source underneath |
| `words.root_letters`, `words.form`, `words.morphology`, `roots` | [Quranic Arabic Corpus 0.4](https://corpus.quran.com/download/), the upstream file, placed by hand | GPL, verbatim copies only, attribution and a link; Tanzil underneath it | **Yes** — Wird is AGPL-3.0 and the notice ships in `corpus_meta.notice`; see above |
| `ayah_audio`, `word_segments` | `api.quran.com/api/v4/recitations/12/by_chapter` | QF terms §3.1, and the timings are **not** in the Content Sync list | **No, as it stands** — see *Timings are not syncable* |
| the MP3s themselves (not mirrored yet) | `mirrors.quranicaudio.com/everyayah/Husary_Muallim_128kbps/` | [quranicaudio.com](https://quranicaudio.com/about): personal use, no commercial use | **No, as it stands** — personal use is not distribution |

### The one-week rule

QF Developer Terms §3.1 forbids a developer to cache or store QF Content longer
than one week, except where QF has expressly permitted longer storage or the
content is available through the Content Sync APIs, in which case a next sync must
happen at least every seven days with all available changes applied. §2.2 permits
display inside an application provided QF Content and raw API data are not sold,
sublicensed, or redistributed as data.

A shipped `corpus.db` is storage without end, so the sync exception is the only
route: an active account in the Developer Console, credit to Quran Foundation in
the app, and a re-sync at least every seven days. The
[Content Sync resources](https://api-docs.quran.foundation/docs/content_apis_versioned/4.0.0/resources-sync/)
cover `quran_core` (Uthmani verse text and surah metadata), `mushafs`,
`translations`, `tafsirs`, `recitations`, `chapter_recitations`,
`word_by_word_translations`, `word_by_word_transliterations` and `articles`.

So the surah metadata, the verse text and the word-by-word rows *can* be bundled —
but only by an app that syncs weekly, which the architecture has not decided to
be. The alternative is to take the text from Tanzil directly, where the terms are
the plain verbatim-and-attribution ones and no weekly obligation exists. The cost
is the one this repo already knows: a different source is a different tokenisation
until proven otherwise, and the segment timings are numbered against quran.com's
words. Re-run the reconciliation before switching; do not assume.

### Timings are not syncable

Per-word audio timings appear in no Content Sync resource — `recitations` covers
ayah audio files, not the `segments` arrays. No exception applies, so the one-week
limit stands and `word_segments` cannot ship inside the bundle on these terms.
**Still open.**

The named alternative is [`cpfair/quran-align`](https://github.com/cpfair/quran-align),
which quran.com itself credits for the segmentation: its released timing data is
**CC BY 4.0**, which permits bundling with attribution. Its indices are over a
space-split of Tanzil's text, which is not quran.com's word numbering, so a switch
needs the reconciliation below redone, not copied.

### The MP3s are personal use only

**Still open.** quranicaudio.com grants personal use and forbids commercial use,
which is not a grant to distribute or to mirror. quran.com credits the
[King Fahd Glorious Qur'an Printing Complex](https://qurancomplex.gov.sa/) for the
recordings; its terms have not been read. Nothing is mirrored yet, so nothing has
been done under a permission we do not have.

## What is still open

1. Who wrote the word-by-word English gloss and transliteration served by
   quran.com. Nothing on [quran.com/about-us](https://quran.com/about-us) or in
   the API documentation names an author, and the QF terms defer to "any
   source-specific license requirements" without saying which. Someone has to ask.
2. Whether the app takes on a seven-day content sync, or moves the text to Tanzil
   and the timings to quran-align.
3. Where the MP3s come from once they are mirrored.
4. Where the app shows `corpus_meta.notice`. The database carries it; no screen
   reads it yet.

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
- **The corpus morphology agrees with quran.com's word numbering** for all 6,236
  ayas, exactly as the fork did. `ingest` re-checks it on every run, because a
  third segmentation entering the pipeline is what mis-assigns roots.
- **`revelation_order` is quran.com's field.** `ingest` asserts it is a
  permutation of 1..114; it matches the Egyptian standard at the points the plan
  names (96→1, 68→2, 1→5, 2→87). Nobody has checked all 114 against a printed
  muṣḥaf.
- **Audio paths are relative** (`husary-muallim/001001.mp3`). The origin is config
  with a bundled default, so a host that moves does not cost an App Store release.

## Reconciliation, from `data/manifest.json`

| Number | Value | What a wrong value would mean |
| --- | --- | --- |
| ayas where word numbering disagrees | **0** | a word's timing or root belongs to another word |
| ayas with a segment past the last word | 5 | the muqaṭṭaʿāt: the reciter splits a word the text keeps whole |
| multi-word spans / words they time | 27 / 61 | words the aligner could not split, dropped by a one-word-per-segment parser |
| words with no timing | 26 across 16 ayas | the highlight freezes for those words |
| overlapping segment pairs | 0 | — |
| segments ending before they start | 8 | the ETL clamps them |

Built from these sources, `corpus.db` is 114 suras, 6,236 ayas, 77,429 words,
1,642 roots and 77,342 word segments, at 22.96 MB against a 60 MB budget.
