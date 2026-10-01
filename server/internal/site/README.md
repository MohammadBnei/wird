# The public page

What `https://wird.bnei.dev/` serves. Every file under `static/` is embedded in wird-api ([site.go](site.go)) and served as it is. [ADR 0018](../../../docs/adr/0018-the-public-site-is-served-by-the-api.md) records why the page lives here, and [the API doc](../../../docs/architecture/api.md#the-public-page) shows how it is routed.

## Where each file comes from

The source is the Claude Design project `65806714-5bf1-4ef1-942f-4cdfdd82bf30`, fetched on 2026-10-01.

| File | Kind | Notes |
| --- | --- | --- |
| `support.js` | verbatim | The design runtime. It loads React, ReactDOM and Babel from unpkg and fetches each demo as `./<name>.dc.html`. Identical to `docs/design/support.js`. |
| `android-frame.jsx` | verbatim | The phone bezel around both demos. |
| `_ds/nocturne-…/styles.css`, `_ds_bundle.js` | verbatim | Nocturne. The stylesheet matches `docs/design/nocturne-styles.css`, and a test fails if they drift apart. |
| `wird-icon.svg` | verbatim | The icon, with the و outlined so it renders without the font. |
| `index.html` | **adapted** from `Wird Site.dc.html` | Adds a title, description and favicon, and loads `site-data.js`. The Download links point to `/download/android`. The About text is written. Demo phones are zoomed down on screens narrower than 460px. The language choice is kept in a `wird_lang` cookie and passed to both demos as `lang`. Download first asks `HEAD /download/android` and shows a notice instead of leaving the page when no build is published. |
| `Wird Reader.dc.html` | **adapted** | Reads `window.WIRD_SITE.reader` instead of the mockup's own tables. The parts Wird has no source for are removed: which sense applies here, form labels and notes, the verse note, and related roots. The verse card shows the aya's translation. With the page in French, glosses, senses and translations come from the corpus's French. The ring shows up to 8 real lemmas. `componentDidUpdate` no longer relies on a previous state the runtime never passes. |
| `Wird Prayer.dc.html` | **adapted** | The Qur'an text and glosses come from `window.WIRD_SITE.prayer`, in French when the page is. Nothing else changed. |
| `site-data.js` | generated | See below. Never edit it by hand. |

To refresh a verbatim file, fetch it again from the design project and replace it whole. Refreshing an adapted file means reapplying the changes listed here. A fresh copy of either demo brings back the invented tables, and `TestADemoShipsTheMockupsInventedScholarship` fails until they are taken out again.

## The demo data

```sh
python3 scripts/site-data.py --db app/assets/corpus.db
```

It reads `corpus.db` and `data/root_senses_draft.tsv`, and writes `static/site-data.js`. Aya translations come in English (Pickthall, resource 19, per ADR 0017) and French (Rashid Maash, resource 779). If the corpus lacks one, it is left out and the demo falls back to the other.
