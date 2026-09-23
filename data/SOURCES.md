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
data/raw/quran-align-data-2016-11-24.zip        the released timing package, as published
data/raw/timings/NAME.json                      one recitation's word timings, out of the zip
data/raw/timings/{LICENSE,README}               the grant those timings arrive under
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
  is what the fold costs: 135 of the 1,642 roots carry a hamza, and in two of them
  the fold leaves Arabic that is simply wrong — لؤلؤ comes back as لألأ, and هات as
  هأت. `jidhr` keys its own roots the same way, but a join between the two should
  fold rather than assume, and the fold a join needs is now measured rather than
  guessed at: see *Lane's Lexicon* below and `docs/lane-lexicon.md`.
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
| `word_segments` | [`cpfair/quran-align`](https://github.com/cpfair/quran-align), release `release-2016-11-24`, file `Husary_Muallim_128kbps.json` | **CC BY 4.0** — attribution, and nothing else | **Yes** — see *The word timings* |
| `ayah_audio.rel_path` | derived from the sura and aya number; nothing is fetched to build it | not a licensable fact | **Yes** — it is a file name, not content |
| the MP3s themselves | `everyayah.com/data/Husary_Muallim_128kbps/`, fetched by the device at playback | everyayah publishes no terms of any kind | **No, and Wird does not** — see *The recitation audio* |

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
until proven otherwise. Re-run the reconciliation before switching; do not assume,
and note the measurement below — a plain space-split of Tanzil's text disagrees
with quran.com's word numbering on 116 ayas, so moving the text without applying
the same joins would break the numbering the timings and the morphology both key
against.

The timings are no longer on this rule. They come from quran-align now, under a
licence that grants bundling outright.

## The word timings: cpfair/quran-align

**Settled 2026-09-23.** Until then `word_segments` came from
`api.quran.com/api/v4/recitations/12/by_chapter`, and could not ship: per-word
timings appear in no Content Sync resource — the `recitations` group covers ayah
audio files, not the `segments` arrays — so no exception applied to the one-week
rule and an immutable `corpus.db` was storage without end.

They now come from [`cpfair/quran-align`](https://github.com/cpfair/quran-align),
whose released data package grants them. The README inside
`quran-align-data-2016-11-24.zip` says, verbatim and in full:

```
License
-------

These data files are licensed under a [Creative Commons Attribution 4.0
International License](https://creativecommons.org/licenses/by/4.0/). Please
consider emailing me if you use this data, so I can let you know when new &
revised timing data is available.
```

The package also ships the full CC BY 4.0 legal code as `LICENSE`, headed
`Copyright (c) 2016 Collin Fair`. Both files are pulled out of the zip and
checksummed in `data/manifest.json` beside the timings themselves, because the
grant is part of the package and not a claim about it.

**The repository's own top-level `LICENSE` is MIT and covers the aligner, a C++
program. It is not the data's licence.** Citing it would be the morphology
fork's mistake in a second place.

| Condition | What satisfies it |
| --- | --- |
| CC BY 4.0 §3(a)(1)(A): the creator, a copyright notice, a notice referring to the licence, a notice referring to its disclaimer of warranties, and a link to the material | All five are in `corpus_meta.notice`, which ships inside `corpus.db`. `server/cmd/etl` refuses to build a database whose notice does not name quran-align, Collin Fair and the licence URI. **The app's Sources and licences screen does not carry it yet** — it is a hand-written list, not a read of the notice — so this condition is met in the data and not yet met where a user can see it. Open item 4, and it blocks a release. |
| §3(a)(1)(B): indicate if you modified the material | The notice says so, and says how: the timings are reindexed onto this database's word ids, one row per word. |
| §3(a)(1)(C) and §3(a)(2): name the licence, by text or by URI | The notice carries `https://creativecommons.org/licenses/by/4.0/`. §3(a)(2) permits a URI in place of the legal code: "You may satisfy the conditions in Section 3(a)(1) in any reasonable manner based on the medium... For example, it may be reasonable to satisfy the conditions by providing a URI or hyperlink to a resource that includes the required information." |
| §4: database rights | §4(a) is explicit that the licence "grants You the right to extract, reuse, reproduce, and Share all or a substantial portion of the contents of the database", on the §3(a) condition. `corpus.db` is exactly that case. |

The quoted sentence is a quote, not a paraphrase, and `server/cmd/ingest`
re-reads it: a release package whose README no longer carries *Creative Commons
Attribution 4.0* is refused, because at that point `corpus_meta.notice` would be
asserting a permission nobody had checked.

### The numbers did not change; the terms did

quran.com's recitation 12 and quran-align's `Husary_Muallim_128kbps.json` are
the same timings. All 6,236 ayas compare tuple for tuple: 6,236 identical, 0
different, 0 absent. quran.com credits quran-align for the segmentation, and the
comparison bears that out. So the switch costs one URL and buys the right to
bundle. The README's request — "Please consider emailing me if you use this
data" — is a courtesy and not a condition of CC BY 4.0.

### The two sources do not number words the same way, in five ayas

This is the part that had to be redone rather than copied, and the part that
would have mis-highlighted silently.

quran-align's indices run over its own reference text, and agree with quran.com's
word numbering in 6,231 of 6,236 ayas of this recitation. The exception is the
muqaṭṭaʿāt: the recogniser's language model treats the opening letters as several
words — `ا ل م` where the text writes `الم` — so those ayas carry one index too
many, and every index after the split names the word *before* the one it looks
like. 12:1, 13:1, 14:1, 27:1 and 37:130.

`server/internal/timings` reconciles it, and is the only reader of these tuples:
both the ingest's manifest counts and the ETL's rows come through it, so the two
cannot drift apart the way they did before. The reconciliation is one rule. An
aya whose index space is one larger than its word count has had a word split; the
extra index is the one nothing aligned, or — when the aligner timed them all —
the last one, which belongs to the last word. Two indices too many is a different
tokenisation of the whole text, and is refused rather than guessed at.

Before this, 13:1 shipped with `تِلْكَ` untimed and `ءَايَـٰتُ` carrying
`تِلْكَ`'s 610 ms, and every word after it one place late. It now reads
`تِلْكَ 12600–13210`.

## The recitation audio

**Settled 2026-09-23, and the answer is that nothing may be redistributed.**

There is no complete, per-aya Arabic recitation of the Qur'an that Wird may
bundle or mirror. Every candidate is granted for personal use only, published
with no terms at all, or carries an open-licence tag applied by somebody who does
not hold the master — a licence from a non-rightsholder is not a licence. So the
plan's intent to mirror the MP3s onto Wird's own origin is dropped, not deferred.

Two different acts have to stay apart here:

- **(a) redistributing audio** — bundling it, or serving it from Wird's origin.
  Needs a licence that permits redistribution. Nobody grants one.
- **(b) the device fetching audio from a third-party origin at playback**, the
  way a browser loads an image. Wird neither copies nor hosts; the third party
  serves a public URL to the user who asked for it.

Wird does (b), and (b) is the design rather than a workaround. Two things keep it
honest, and `app/lib/data/audio.dart` is where both live: the cache stays bounded
and evictable, so what is on disk is a performance artifact of playing the files
and not a copy of the recitation assembled on the user's device; and the origin
stays config with a bundled default, so a host that stops serving costs a config
change.

### Quran Foundation's terms are the ones that say the most

They are also the only ones in this space written down at all, so they are quoted
even though Wird does not currently fetch audio from QF. From the
[Developer Terms](https://api-docs.quran.foundation/legal/developer-terms/),
verbatim:

> In these Terms, "redistribution" means offering QF Content or raw API data to
> others as data—for example, through the Developer's own API, dataset, data
> feed, download, content package, or similar service.

Mirroring MP3s onto Wird's own origin is that, exactly. §3.1 also names the
signed-deal route out:

> A Developer must obtain a signed commercial license before selling,
> sublicensing, or redistributing QF Content or raw API data—for example, as a
> dataset, data feed, API, content package, or other separately distributed
> product.

And the bundling permission §3.1 does grant reaches fonts and images, not audio:

> A Developer may cache or bundle font files and Mushaf images obtained through
> QF APIs or documented CDN URLs for use in an Application if the Developer
> maintains an active account in the Developer Console and credits Quran
> Foundation in a reasonably accessible place in the Application or its
> associated credits. The files may be distributed only as an integrated part of
> the Application. They may not be offered separately to others—for example,
> through the Developer's own API, asset package, or standalone download.

**One earlier reading here was wrong and is corrected: ayah audio *is* in the
Content Sync list.** The
[Content Sync documentation](https://api-docs.quran.foundation/docs/tutorials/content-sync/getting-started/)
says, verbatim: "Content Sync supports these resource groups after the Quran core
rollout: quran_core, mushafs, translations, word_by_word_translations,
word_by_word_transliterations, tafsirs, recitations, chapter_recitations, and
articles", and the `recitations` row reads "Ayah audio files and compatible
chapter audio files for the legacy ayah recitation." Paired with the §3.1
exception —

> Cache or store QF Content longer than 1 week, except where (a) QF has expressly
> permitted longer storage, or (b) the QF Content is available through the
> Content Sync APIs listed under Content Available for Offline Sync. If you rely
> on exception (b), you must perform a next sync at least every 7 days and apply
> all available changes.

— that is a real route for audio with an actual grant: device-fetch from QF's
CDN, cached indefinitely, on a permanent seven-day re-sync and a Developer
Console account. It is not taken, because taking it is a decision about what Wird
signs up to rather than a decision about code, and it would make the audio cache
a thing that can never be frozen. It is open question 3.

### everyayah.com publishes no terms, and that is the honest description

`everyayah.com` is the de facto archive every Qur'an app points at, and Wird's
default origin points there because it serves the exact recording quran-align
measured — so the bundled timings belong to those files rather than to a
re-encode of them. CORS is open (`access-control-allow-origin: *`) and Range
requests work.

It publishes **no terms of use, no licence page, and no copyright statement.**
The only licence-bearing file on the site is
`data/timings_files/000_disclaimer.txt`, which covers the *timing files* and not
the audio. Verbatim, in full:

```
Disclaimer:

(C) VerseByVerseQuran.com
You must link back to our site from your product and web-site to use these timings.
Full License at http://versebyversequran.com/site/license

These timing files are provided as-is.
IMPORTANT: Many of our mp3s have been fixed manually after splitting these files, so this will not provide 100% accurate results.
```

That licence URL was fetched on 2026-09-23 over both http and https and returns
**404 — File Not Found**. Wird uses none of those timing files, so the clause
does not reach it; it is recorded because the reading of a source has to include
what the source does not say.

This is unstated permission, not a grant. It is enough for (b) and it is not
enough for anything else. Note also that `Husary_Muallim_128kbps` serves but is
absent from the site's own `recitations.js` manifest — a load-bearing URL that is
not advertised. `archive.org/details/quran-every-ayah` mirrors the same folder and
is the documented second origin if it stops.

### The sources that were checked and rejected

- **quranicaudio.com**, where the MP3s used to come from. Its
  [about page](https://quranicaudio.com/about) says, verbatim: "Mp3s on this site
  may be downloaded and used for personal use free of charge. However, you may
  not use these files for commercial purposes as many of these files have rules
  and regulations that prevent their sale except by the publishing companies.
  Files on QuranicAudio.com come from many different sources. Many of them are
  hand ripped from cds." That is a statement that it does not hold the rights it
  would need to sublicense. Its files are also surah-level, not per-aya.
- **audio-cdn.tarteel.ai / QUL**, the previous default origin. The QUL resource
  page for the exact recording, `qul.tarteel.ai/resources/recitation/112`, carries
  **no licence of any kind**, and QUL's FAQ defers to one: "The resources
  available on QUL vary in their copyright status... We recommend reviewing the
  licensing information provided by each resource's author before use." A
  distribution platform is not a grant.
- **KFGQPC**, whom quran.com credits for the recordings. The permissive KFGQPC
  text everyone cites is a **font** licence — "Permission is granted free of cost
  to any person obtaining a copy of the Font" — and no published licence covering
  KFGQPC *recordings* was found. The word "Font" is doing all the work.
- **Archive.org CC-BY and public-domain-marked Qur'an audio.** The tags are real,
  but on Archive.org the licence tag is applied by the uploader, and in every item
  found the uploader is a radio site or app developer, not the reciter and not the
  master's owner. All are surah-level besides, so they could not carry per-word
  timings anyway.
- **Purpose-recorded open-licensed recitation.** Wikimedia Commons holds only
  scattered single suras; no complete per-aya recitation released by its
  rightsholder was found.

## Lane's Lexicon: read on 2026-09-23, and the answer is no

The working, every quotation's URL, and the script behind every number are in
`docs/lane-lexicon.md`. What it settles:

**Perseus publishes Lane under CC BY-SA 3.0 United States.** Its page for the
text (`perseus.tufts.edu/hopper/text?doc=Perseus:text:2002.02.0015`, read live
and in Wayback captures of 2024-02-26 and 2026-04-13) says, verbatim:

> This work is licensed under a Creative Commons Attribution-ShareAlike 3.0
> United States License.
>
> An XML version of this text is available for download, with the additional
> restriction that you offer Perseus any modifications you make. Perseus
> provides credit for all accepted changes, storing new additions in a
> versioning system.

The licence link resolves to `https://creativecommons.org/licenses/by-sa/3.0/us/`.
Not 4.0, and the difference is the whole question.

**CC BY-SA 3.0 has no path to AGPL-3.0.** §4(b) of the 3.0 US legal code,
verbatim:

> You may distribute, publicly display, publicly perform, or publicly digitally
> perform a Derivative Work only under: (i) the terms of this License; (ii) a
> later version of this License with the same License Elements as this License;
> (iii) either the Creative Commons (Unported) license or a Creative Commons
> jurisdiction license (either this or a later license version) that contains the
> same License Elements as this License (e.g. Attribution-ShareAlike 3.0
> (Unported)); (iv) a Creative Commons Compatible License.

Route (iv) is the only one that could reach the GPL family, and Creative Commons's
own compatibility page says, verbatim, **"Currently, no non-CC licenses have been
designated as compatible with BY-SA 3.0."** The one-way route to GPLv3 exists
only from 4.0: **"declared a 'BY-SA–Compatible License' for version 4.0 on 8
October 2015"**. So `corpus.db` cannot carry Lane's sense text into an AGPL-3.0
binary. `PerseusDL/lexica` *is* CC BY-SA 4.0 — its `license.md` is the full 4.0
legal code — but that repository holds Greek and Latin only. Lane is in no
PerseusDL repository at all.

**A second bar, independent of the first: "you offer Perseus any modifications
you make."** That term is in no Creative Commons licence; it is bolted on. AGPL-3.0
§7 — `LICENSE` line 451 of this repository — says verbatim: *"You may not impose
any further restrictions on the exercise of the rights granted or affirmed under
this License."* A recipient of Wird's source who edited bundled Lane text would
inherit an obligation to send it to Tufts. Even under a hypothetical 4.0 the Lane
text would have to sit outside the AGPL-covered work as a separately licensed
asset, not inside it.

**The XML file says something narrower than the page does, and this is what
`SOURCES.md` had already read.** Every one of the 36 files carries the same
`<availability>` block, byte-identical:

```xml
<availability status="free">
   <p>This text may be freely distributed, subject to the following
      restrictions:</p>
   <list>
      <item>You credit Perseus, as follows, whenever you use the document:
         <quote>Text provided by Perseus Digital Library, with funding from The
         U.S. Department of Education and The Max Planck Society.</quote>
      </item>
      <item>You leave this availability statement intact.</item>
      <item>You offer Perseus any modifications you make.</item>
   </list>
</availability>
```

Credit, keep the notice, offer modifications back — and **no ShareAlike, no
NonCommercial, no Creative Commons licence named**. The earlier reading here was
a correct reading of this block. The draft that claimed Perseus permits "closed
or open redistribution with attribution" was reading a term that is in none of
the three instruments.

**Three instruments disagree, and that stays recorded as unresolved.** The file
grants free distribution on three conditions; the per-text page says CC BY-SA 3.0
US; the site-wide copyright page says, verbatim, *"Any commercial use or
publication without authorization is strictly prohibited. Materials within the
Perseus DL have varying copyright status: please contact the project for more
information about a specific component or object."* Nobody has contacted them.
Until somebody does, the conservative reading applies: **CC BY-SA 3.0 US plus the
offer-back term, which is not bundleable.** Lane's Lexicon itself (1863–1893) is
public domain; Perseus's claim runs only to the digitisation, and a faithful
transcription of a public-domain text carries no new US copyright. That is a real
argument and it is not one to bet a binary on.

**Use the `originals` branch if it is ever used at all.**
`github.com/laneslexicon/lexicon_xml` has two branches and no `LICENSE` file.
Its README says, verbatim: *"This repository contains the updated XML files. The
original Perseus XML files are in the 'originals' branch. The master branch has
all the fixes."* So `originals` is Perseus's, under whichever instrument governs,
and `master`'s amendments carry no stated grant from anybody. Choosing
`originals` costs almost nothing: 34 of 36 files differ, but the whole of
`master`'s work is 25 more root divisions and 37,262 more characters out of
26.4 million — 0.14%.

### The join was measured anyway, and the join is not the problem

`server/cmd/etl/load.go:282-289` folds every hamza onto Buckwalter `A`, so our
root keys are lossy before any join starts. Four folds are needed, not one:
hamza seats onto أ and ى onto ي; a geminate `r1r2r2` onto Lane's biliteral
(**153 roots, 4,624 occurrences** — ربب, أيي, كلل among them, which join to
nothing without it); a reduplicated quadriliteral onto its biliteral (13 roots);
a final-weak triliteral onto its biliteral (13 roots).

A stub is calibrated, not picked: of 5,062 root divisions, 31 consist of nothing
but a cross-reference and the longest of those is 146 characters, so **a stub is
under 200 characters of article prose**.

| | |
| --- | --- |
| our roots | 1,642, carrying 49,967 occurrences |
| reach a Lane division after the fold | 1,611 (98.1%) |
| **have a non-stub article after the fold** | **1,582 (96.3%), covering 49,563 occurrences (99.2%)** |
| article of 2,000 characters or more | 1,379 (84.0%), covering 45,435 occurrences (90.9%) |
| no Lane text at any key | 13 roots, 29 occurrences |

**Coverage is not the obstacle; depth is.** Lane reached ق before he died in 1876
and volumes six to eight are Stanley Lane-Poole's edit of unfinished notes. The
seam is visible in the data: median article 9,681 characters for the 1,147 roots
before ق, 5,547 under ق, **2,987 for the 415 after it**. 495 of our roots (30.1%)
sit at ق or past it, and 33 of the hundred we meet most often are there, carrying
34.4% of that hundred's occurrences — قول among them (1,722 occurrences, 3,221
characters of article) and كون (1,390 occurrences, 1,755 characters), against
صبر's 25,723.

**One trap for whoever implements this: `div2/@n` is not a root index.** دبر has
no division of its own — its article sits inside the one keyed `dbx` (دبخ), which
measures 44,503 characters because it is two roots merged. نوم is filed under
`nAm`, the vocalised past tense. 81 keys are ranges written `X &amp;c.` standing
for several roots at once. Of the 31 roots reaching no division, 18 have their
headword inside another division — including our mangled هأت, whose article is
Lane's هيت. Resolve headwords, not division keys.

## What is still open

1. Who wrote the word-by-word English gloss and transliteration served by
   quran.com. Nothing on [quran.com/about-us](https://quran.com/about-us) or in
   the API documentation names an author, and the QF terms defer to "any
   source-specific license requirements" without saying which. Someone has to ask.
2. Whether the app takes on a seven-day content sync, or moves the text to Tanzil.
   The timings half of this question is answered: they come from quran-align and
   carry their own grant.
3. Whether Wird registers a Quran Foundation Developer Console account and takes
   the Content Sync route for the audio. It is the only ayah-audio permission in
   this space that is written down, and it costs a permanent seven-day re-sync
   and a published privacy policy and terms of use (§3.2). Until then the device
   fetches from everyayah.com, which publishes no terms at all. **The MP3s are
   never mirrored either way** — that is the one act named and forbidden in
   writing.
4. Tafsir, lexicon and iʿrāb prose still have no source chosen. The works are
   centuries old and public domain — Ibn Fāris's Maqāyīs, Lane's Lexicon, Lisān
   al-ʿArab — and their DIGITISATIONS are where the care goes. Two of the three
   are now answered and both answers are no: **Lane via Perseus TEI is CC BY-SA
   3.0 US plus an offer-back term and cannot be bundled in an AGPL-3.0 binary**
   (see *Lane's Lexicon* above; the earlier note here read the XML's availability
   block correctly but did not know Perseus's own page adds ShareAlike), and
   OpenITI's Maqāyīs and Lisān are CC BY-NC-SA, whose NonCommercial term rules
   them out of anything sold and whose share-alike term is a further restriction
   AGPL-3.0 §7 forbids on a covered work either way. What remains open is which
   route replaces them. Ranked by how cleanly the licence lands: prose written
   here with Lane and Ibn Fāris as consulted references rather than copied text,
   which is what the existing `root_notes` / `RootReading.coreSense` path was
   built for; a non-Perseus digitisation of Lane, whose underlying book is public
   domain and whose OCR is the expensive part; Wiktionary's Arabic root entries,
   **CC BY-SA 4.0** and therefore the one candidate with a real one-way route
   into the GPL family, coverage unmeasured; Penrice's 1873 Qur'anic glossary,
   public domain, digitisations unexamined. And somebody should email Perseus:
   three of their own instruments say three different things about this text, and
   one email settles all three.

## What the data actually is

Corrections that cost a day each to find, kept here so they are not re-found.

- **A segment tuple is `[word_start_index, word_end_index, start_ms, end_ms]`** —
  zero-based, end exclusive. QUL documents a three-tuple
  `[segment_index, start_ms, end_ms]`; reading that shape puts a word index into a
  timestamp. Reading element 1 as a one-based word position is the subtler
  mistake: it agrees with the real shape for every segment covering exactly one
  word, which is 77,320 of 77,347 of them, and silently drops the other 27. The
  ETL did exactly that until 2026-09-23, which is why its untimed-word count read
  87 where the manifest read 26 and nothing compared the two. Both readers now go
  through `server/internal/timings`, and both say 22.
- **The indices are not over quran.com's word numbering.** They are over
  quran-align's own reference text, which agrees in 6,231 of 6,236 ayas and adds
  one index in the five muqaṭṭaʿāt ayas. That is reconciled, not assumed — see
  *The two sources do not number words the same way*. QUL resource 112 is a third
  numbering again, splitting words the text keeps whole (12 segments against 11
  words in 2:21), and is not used.
- **The corpus morphology agrees with quran.com's word numbering** for all 6,236
  ayas, exactly as the fork did. `ingest` re-checks it on every run, because a
  third segmentation entering the pipeline is what mis-assigns roots.
- **`revelation_order` is quran.com's field.** `ingest` asserts it is a
  permutation of 1..114; it matches the Egyptian standard at the points the plan
  names (96→1, 68→2, 1→5, 2→87). Nobody has checked all 114 against a printed
  muṣḥaf.
- **Audio paths are relative** (`husary-muallim/001001.mp3`), and derived from the
  sura and aya number rather than fetched. The origin is config with a bundled
  default, so a host that moves does not cost an App Store release — and because
  the audio is fetched at playback rather than redistributed, that default is the
  only place the origin exists.
- **`ayah_audio` has no duration column.** It had one, from quran.com's audio-file
  rows. Wird neither hosts nor indexes the recordings, so their length is not
  Wird's to state, and a duration derived from the last word's timing would be a
  number invented to fill a column nothing reads.

## Reconciliation, from `data/manifest.json`

| Number | Value | What a wrong value would mean |
| --- | --- | --- |
| ayas where word numbering disagrees | **0** | a word's timing or root belongs to another word |
| ayas where the aligner numbers one written word as two | 5 | the muqaṭṭaʿāt, reconciled: unreconciled, every word after the split highlights one place late |
| multi-word spans / words they time | 27 / 61 | words the aligner could not split, dropped by a one-word-per-segment parser |
| words with no timing | 22 across 12 ayas | the highlight freezes for those words |
| overlapping segment pairs | 0 | — |
| segments ending before they start | 8 | the ETL clamps them |

Built from these sources, `corpus.db` is 114 suras, 6,236 ayas, 77,429 words,
1,642 roots and 77,408 word segments, at 22.95 MB against a 60 MB budget.
