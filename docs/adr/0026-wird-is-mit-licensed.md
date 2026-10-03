# 26. Wird's own code is MIT licensed

Date: 2026-10-03. Status: accepted.

## Context

Wird was AGPL-3.0 because its data was copyleft. The Quranic Arabic Corpus morphology is GPL, and a closed binary could not have bundled it. The Quran Foundation rows (`words.gloss_en`, `words.translit`, the Rashid Maash French) sat under a one-week storage rule and were marked "could not determine" in `data/SOURCES.md`.

Shipping through the App Store and Google Play makes copyleft a problem. The FSF holds that the App Store's usage rules conflict with the GPL family, and a rights holder's complaint can get an app pulled.

Both data owners then granted Wird free use in writing. The quotes are in `data/SOURCES.md`, and the owner keeps the emails. The project owner is the only contributor to the code, so the code can be relicensed without asking anyone.

## Decision

Wird's own code moves from AGPL-3.0 to MIT. `LICENSE`, the README, the in-app About card and the public page say so.

The data keeps its own terms, which are recorded per table in `data/SOURCES.md`. The corpus notice still ships in `corpus_meta.notice`, and every source is still named in the app, because the grants make that optional and Wird names its sources anyway.

## Alternatives

- **Keep AGPL-3.0 and add an app store exception (§7)** — this works for the code, but it keeps a licence chosen for a constraint that no longer exists.
- **Apache-2.0** — it adds a patent grant that a reading app does not need, and its text is ten times longer.
- **MPL-2.0** — file-level copyleft. The owner wanted no copyleft at all.

## Consequences

- The app can go to both stores with no licence conflict and no custom EULA.
- Anyone may make a closed fork, including of the server. That is accepted.
- Releases up to v0.0.7 stay AGPL-3.0. Only later commits are MIT.
- A future bundled source must be checked for copyleft on its own. MIT no longer absorbs a GPL source by accident.

## Reversibility

Relicensing back to a copyleft licence is cheap while the owner is the only contributor. Once other people's MIT contributions arrive, each of them would have to agree. The signal to reverse is a closed fork that takes Wird's work away from its readers.
