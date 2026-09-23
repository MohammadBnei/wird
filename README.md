# Wird

A Muslim reads a small set of ayas before a prayer, recites that set inside the
prayer while the app follows along, and can open any word's Arabic root to read
as deeply as they want — derivatives, lexicon, tafsir, iʿrāb. Progress is
counted in ayas understood, not pages turned.

The corpus is bundled and the sets are generated on the device, so the whole
loop works with the radio off. A Go backend keeps user state and the root
engine (`jidhr`) answers word → root for anyone who asks.

```
app/       Flutter client (iOS, Android, tablet)
server/    wird-api — user state, tafsir, iʿrāb
jidhr/     the Arabic root engine, a product in its own right
data/      ingest provenance; data/SOURCES.md is the per-table licence record
scripts/   qa.sh is the gate — its exit code is the verdict
```

## Licence

Copyright (C) 2026 Mohammad Bnei.

Wird is free software under the **GNU Affero General Public License, version 3
or later**. The full text is in [`LICENSE`](LICENSE).

AGPL rather than plain GPL because Wird has a server component. A GPL backend
that users only ever reach over HTTP triggers no obligation to release source;
AGPL §13 closes that, so anyone running Wird as a service owes its users the
source of what they are running. That is the whole point of picking a copyleft
licence here, and GPL alone would have made it hollow.

Wird is AGPL because its data is copyleft. The morphology below is GPL, and a
closed binary could not have bundled it at all. Open source is not a footnote
to that decision — it is the decision.

## Attribution

Wird is built on other people's work. Each source below is named with what it
provides and the terms it is used under. `data/SOURCES.md` carries the same
record per database table, with the endpoint each row was fetched from.

The app itself carries this list on its **Sources and licences** screen,
reachable from the settings panel on the study screen — a licence file in a git
repository does not reach someone using the app, and several of these terms ask
to be shown to users rather than to readers of the source.

### Quranic Arabic Corpus — morphology, roots, word forms

Version 0.4, Copyright (C) 2011 Kais Dukes. **GNU General Public License.**

<http://corpus.quran.com>

Every root a word opens into, every form label, and `words.morphology` come
from here. Its terms of use, verbatim from
<https://corpus.quran.com/download/>:

> - Permission is granted to copy and distribute verbatim copies of this file,
>   but CHANGING IT IS NOT ALLOWED.
>
> - This annotation can be used in any website or application, provided its
>   source (the Quranic Arabic Corpus) is clearly indicated, and a link is made
>   to http://corpus.quran.com to enable users to keep track of changes.
>
> - This copyright notice shall be included in all verbatim copies of the text,
>   and shall be reproduced appropriately in all works derived from or
>   containing substantial portion of this file.

Three conditions, each met somewhere a person will actually see it: the source
is named here and on the in-app screen, the link is here and tappable in the
app, and the copyright notice above is reproduced in both. The GPL condition is
met by Wird itself being AGPL-3.0.

Kais Dukes died in March 2024. There is no relicensing conversation to be had;
the terms are final and are simply met.

### Tanzil Project — the Qur'anic text

<https://tanzil.net>

`ayahs.text_uthmani` and `words.text_ar` are Tanzil's verified Uthmani text.
The Quranic Arabic Corpus builds on the same text. Tanzil's terms:

> Permission is granted to copy and distribute verbatim copies of the Quran
> text provided here, but changing the text is not allowed. The text can be
> used in any website or application, provided that its source (Tanzil Project)
> is clearly indicated, and a link is made to tanzil.net to enable users to
> keep track of changes.

Same shape as the corpus, same answer: unmodified, named, linked.

### Quran Foundation — word-by-word gloss and transliteration

<https://quran.foundation>

`words.gloss_en` and `words.translit` are served by the quran.com API under the
[Quran Foundation Developer Terms](https://api-docs.quran.foundation/legal/developer-terms/).
§3.1 forbids storing their content longer than a week unless it is re-synced
every seven days through the Content Sync APIs. A bundled `corpus.db` is
storage without end, so this row is **not yet settled** — see *Open questions*.

### Nocturne — the design system

Every colour, space, radius and shadow in the app comes from the Nocturne
design system, transcribed into `app/lib/theme/nocturne.dart` from
`docs/design/nocturne-styles.css`. Dark only; there is no light mode. Nocturne
was authored for this project.

### Fonts

- **Scheherazade New** — SIL International. [SIL Open Font License 1.1](https://openfontlicense.org).
  Bundled because platform Arabic faces mangle Qur'anic diacritics.
- **Inter** — Rasmus Andersson. [SIL Open Font License 1.1](https://openfontlicense.org).

The OFL permits bundling and redistribution inside an application. Neither face
is renamed or modified.

### cpfair/quran-align — the per-word timings

Copyright (c) 2016 Collin Fair. **CC BY 4.0.**

<https://github.com/cpfair/quran-align>

`word_segments` — which word is being recited at which millisecond — comes from
the `Husary_Muallim_128kbps.json` file in quran-align's released data package.
Its README grants, verbatim:

> These data files are licensed under a [Creative Commons Attribution 4.0
> International License](https://creativecommons.org/licenses/by/4.0/). Please
> consider emailing me if you use this data, so I can let you know when new &
> revised timing data is available.

CC BY 4.0 permits redistribution, so these timings ship inside `corpus.db`.
Section 4(a) settles the database case in as many words: the licence "grants You
the right to extract, reuse, reproduce, and Share all or a substantial portion of
the contents of the database". Section 3(a)(1) is the one condition, and all six
of its items are in `corpus_meta.notice`: the creator, the copyright notice, the licence by URI, its
disclaimer of warranties, a link to the material, and the indication that Wird
modified it by reindexing the timings onto its own word ids. The ETL refuses to
build a database whose notice is missing any of it.

The **Sources and licences** screen does not yet render that notice — it is a
hand-written list — so the condition is met in the data and not yet met where a
reader of the app can see it. That is open question 4 and it blocks a release.

Wird took the same numbers from the quran.com API until 2026-09-23. They are the
same numbers — all 6,236 ayas compare byte for byte — but the terms they arrived
under were not the same, and the one-week rule made them unshippable. Taking them
from the publisher who granted them makes them shippable, and costs a URL.

### Recitation audio — Maḥmūd Khalīl al-Ḥuṣarī, muʿallim

Fetched by the device from [everyayah.com](https://everyayah.com/) at playback
time. **Not redistributed, not mirrored, not bundled.**

There is no Qur'an recitation Wird may redistribute. Every complete per-aya
Arabic recording is granted for personal use only, published with no terms at
all, or carries an open-licence tag applied by somebody who does not hold the
master. So Wird does not ship the audio and does not host it: the device asks a
third party for a public URL, the way a browser loads an image, and keeps a
bounded cache of what it played. `app/lib/data/audio.dart` holds the origin and
the cap; `ayah_audio.rel_path` is relative so the origin is config, not an App
Store release.

Mirroring these files onto Wird's own host is the act this rules out. Under the
only terms in this space that are actually written down, Quran Foundation's, it
is named and forbidden: redistribution "means offering QF Content or raw API data
to others as data—for example, through the Developer's own API, dataset, data
feed, download, content package, or similar service." `data/SOURCES.md` carries
the full reading, including the one route that does grant ayah audio for offline
use — QF's Content Sync — and what taking it would cost.

### Open questions

Tracked in `data/SOURCES.md`, repeated here because they are attribution
questions and not implementation ones:

1. Who authored the word-by-word English gloss and transliteration that the
   quran.com API serves. Nobody is named in its documentation.
2. Which tafsir translations permit redistribution inside the bundle. v1 ships
   public-domain summaries.
3. Whether Wird registers a Quran Foundation Developer Console account. It is
   what would let the audio be fetched from QF's own CDN under a written grant
   rather than from an origin that publishes no terms — at the price of a
   permanent seven-day re-sync and a published privacy policy. Settled by the
   project, not by the code.
4. **Blocking.** The Sources and licences screen still credits neither
   quran-align nor Collin Fair, and still describes the recitation as "personal
   use only — not cleared" with a link to quranicaudio.com. Neither is true any
   more, and the first is a licence condition rather than a nicety.

## Building

```bash
./scripts/qa.sh                 # the gate; its exit code is the verdict

cd app && fvm flutter pub get
fvm flutter analyze && fvm flutter test

go work sync
go build ./server/... ./jidhr/... && go test -p 1 ./server/... ./jidhr/...
```

`CONTRIBUTING.md` carries the conventions — including what a `ponytail:`
comment means and why a test's name has to state the failure it prevents.
