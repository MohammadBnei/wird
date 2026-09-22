# Design source

Vendored verbatim from the Claude Design project
`claude.ai/design/p/51636c3a-7f67-4731-bfc4-bcc5f323416e`. Nothing here is
hand-edited, so a diff against the design project stays meaningful. Fetch a
fresh copy the same way rather than patching these files by hand.

| File | What it is |
| --- | --- |
| `prayer-app-screens.html` | The seven screens. Authoritative visual spec for phases 4 and 8–10. |
| `ios-frame.jsx` | The iOS device bezel, status bar and keyboard the screens render inside. Presentation chrome only — not part of the app spec. |
| `support.js` | Generated runtime that renders the `.dc.html` document in a browser. Needed only to open the screens file locally. |
| `nocturne-styles.css` | The Nocturne design system stylesheet: every color, font, space and radius token the screens use. |
| `nocturne-readme.md` | The Nocturne guide — how the tokens and component classes are meant to be used. |

`prayer-app-screens.html` loads `./support.js`, and its head points the
stylesheet at `_ds/nocturne-f1420674-3c74-41e9-8af5-2fa684fcd021/styles.css` —
that is `nocturne-styles.css` here, under the design project's own path. The
`_ds_bundle.js` beside it is not vendored, so opening the file locally renders
approximately. Read the markup as the spec, not the rendering.

## Which screen lives where

Each screen is a `div[data-screen-label]` inside an option block whose `id` is
the screen id. Grep for either:

    grep -n 'data-screen-label' prayer-app-screens.html

| Id | `data-screen-label` | Screen |
| --- | --- | --- |
| `1a` | Study | Study the set, before the prayer, phone |
| `1b` | In prayer | In the prayer, no touch |
| `3a` | Root | Root word with the dial |
| `2b` | Root spine | Alternate root view, no dial, for roots with many derivatives |
| `1c` | Deep dive | Tablet, sources side by side |
| `1d` | Progress | Progress across the whole Qur'an |
| `1e` | Notes | Kept: bookmarks and notes |

## What the content is, and is not

The Arabic throughout is Al-ʿAsr (103:1–3) — the same three ayas in every
screen, so anything that looks like a set boundary or a selection rule is
layout, not data.

The tafsir and lexicon entries are placeholder text written to fill the
layout. They are not sourced material and must not be shipped, quoted, or used
as a fixture expectation. The same goes for the attributions beside them
(Al-Rāzī and the rest) and for counts such as "103 occurrences".
