# Corpus sources

`server/cmd/etl` reads this layout and writes `app/assets/corpus.db`:

```
data/raw/chapters.json        surah metadata
data/raw/verses/NNN.json      one file per surah: ayas and their words
data/raw/segments/NNN.json    one file per surah: audio url, duration, word timings
data/raw/morphology.txt       one line per morphological segment
```

`data/raw/` is gitignored, so this file is the record of where those bytes came from.

| Table | Source | Reached how | Licence | Redistributable inside a closed app bundle? |
| --- | --- | --- | --- | --- |
| `surahs` | `api.quran.com/api/v4/chapters` | public API, no account | not stated on the endpoint | **undetermined** |
| `ayahs.text_uthmani`, `words.text_ar` | `api.quran.com/api/v4/verses/by_chapter?words=true` | public API, no account | Uthmani text originates with Tanzil, whose licence forbids modification and restricts commercial use | **undetermined** — unmodified redistribution looks permitted, the commercial clause is unread |
| `words.gloss_en`, `words.translit` | same endpoint, `translation` and `transliteration` per word | public API, no account | not stated on the endpoint | **undetermined** |
| `words.root_letters`, `words.form`, `words.morphology`, `roots` | `mustafa0x/quran-morphology` on GitHub, a copy of the Quranic Arabic Corpus 0.4 morphology table | raw file download | the Quranic Arabic Corpus is published under the GNU GPL | **no, not as it stands** — copyleft against a closed binary is exactly the case the licence is written to catch |
| `ayah_audio`, `word_segments` | `api.quran.com/api/v4/recitations/12/by_chapter?fields=segments,duration,url` — Mahmoud Khalil Al-Husary, Muallim | public API, no account | not stated on the endpoint | **undetermined** |

Two of these are answers someone has to get before release, not before the next phase:
the morphology licence is a real obstacle, and the three "undetermined" rows are unread terms
rather than permissions.

## Deliberate departures

- **Segments come from quran.com's recitation 12, not QUL resource 112**, though both are the
  same Husary Muallim recitation. QUL's word numbering splits words the text keeps whole —
  12 segments against 11 words in 2:21 — and word text and timings have to come from one
  segmentation or every highlight after the split lands on the wrong word.
- **`revelation_order`** is quran.com's field. It is believed to be the Egyptian standard
  chronology the plan names; nobody has checked it against a printed muṣḥaf.
- **Audio paths are relative** (`husary-muallim/001001.mp3`). The origin is config with a
  bundled default, so a host that moves does not cost an App Store release. The MP3s
  themselves are not mirrored yet; the default origin still has to be pointed somewhere.
