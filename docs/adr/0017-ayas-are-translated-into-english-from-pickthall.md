# 17. Ayas are translated into English from Pickthall

Date: 2026-10-01. Status: accepted.

## Context

A French reader saw each aya's translation under it, Rashid Maash's from quran.com. An English reader saw none, because no English was bundled. The owner wants the translation in both languages, and a setting to hide it.

Wird is a public AGPL repository, and every bundled text needs a licence row in `data/SOURCES.md`.

## Decision

Ingest asks quran.com for resource 19, Marmaduke Pickthall's *The Meaning of the Glorious Koran* (1930), beside the French. The ETL writes it to `ayah_translations` with `lang = 'en'`, under the same all-or-none check as the French. The reading screen shows the translation in the reader's language under each aya, and Settings turns it off.

## Alternatives

- **Sahih International.** The most read modern English, but its redistribution terms could not be found.
- **Yusuf Ali.** The 1934 text is old enough, but which edition quran.com serves was not established, and the revised editions are not free.
- **No English.** Leaves English readers with glosses only.

## Consequences

The English is archaic (thee, thou, overtaketh). Pickthall's text is free, but its delivery through quran.com still sits under the Quran Foundation's storage terms, as every other quran.com row does.

## Reversibility

A one-line change of resource id and a re-ingest. Signal to revisit: readers finding the English hard to read, or a modern translation with clear terms.
