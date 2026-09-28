# 10. The server owns the roots and their senses

Date: 2026-09-28. Status: accepted. Leaves ADR 0008 (how the recogniser is
served) standing, and deliberately does not copy it.

Numbering: the next free integer, one ADR per file. 0002 and 0005 each carry
two documents because a decision and its contract vectors were numbered alike,
and because two decisions were taken the same week. Neither is a convention.

## Context

Every sense a reader can see is frozen into the app binary. 1,642 of them are
now drafted and not one can reach a phone without a release, and the app ships
a button that asks the reader whether a sense is right — so corrections arrive
continuously and the way to publish them takes weeks.

Senses also already exist twice, derived from one source by two paths:

```
app/assets/corpus.db  root_notes            SQLite rows, read by the app
jidhr/testdata/quran.json  Meaning{Plain,Poetic}   JSON in memory, read by rootd
```

Rebuild one without the other and rootd answers with the old sense while the
app draws the new one. No test catches it, because each side tests its own
copy.

Two measurements decided the shape of the answer. The first is that the thing
which changes is almost none of what ships: of 21.5 MB of measured table
content, `root_notes` is 0.2 MB and `irab_roles` is smaller again. The rest is
the Qurʼan, Dukes's morphology, the word timings and a licensed translation,
and none of it moves when a sense is corrected.

The second is in `app/lib/data/db.dart:13-17`: the reader's own tables are
created **inside** the same SQLite file as the corpus, because progress and
kept items are read by joining them against corpus rows and ATTACH DATABASE is
fragile across platforms. So a content update cannot be a file swap. It would
take the reader's data with it.

## Decision

The Go server owns roots and their senses. Senses live in its Postgres as the
single source of truth. `server` takes `jidhr` as a library rather than
growing a second root engine beside it, and `server/cmd/jidhrcorpus` becomes an
export **from** the database instead of a second derivation from a TSV.

The app fetches senses over HTTP and applies them as rows into the `wird.db` it
already has — `DELETE` and `INSERT` inside one transaction, no second file, no
ATTACH, no swap, and the reader's twelve tables untouched.

The line between what ships in the binary and what comes from the server is
authorship: **what Wird wrote is served, what came from an upstream source is
bundled.** Senses and the iʿrāb role names are Wird's. The Qurʼan, the
morphology, the timings and the French translation are not.

First launch therefore has a whole Qurʼan and no senses, which is a state the
app was already built for: `CoreSense` draws a refusal notice for a root that
has none. A reader can install, open, and pray with no network and no account.

## Alternatives Considered

### Serve the whole corpus.db, presigned and 302'd like the voice model
- **Pros**: one artefact, one version, one code path; reuses a route that works.
- **Cons**: 99% of those 30 MB never change; a one-word sense fix costs every
  reader a full re-download; an initialisation screen stands between installing
  Wird and reading the Qurʼan.
- **Why not**: that route exists because 160 MB of weights through a pod sized
  for JSON is an outage. 0.3 MB of rows is an ordinary API response. Copying
  the machinery would be copying the reason for it, which does not apply.

### A second SQLite file, ATTACHed
- **Pros**: keeps the two artefacts cleanly separate; no row-level merge.
- **Cons**: every query that joins reader rows against corpus rows changes.
- **Why not**: already rejected in `db.dart:17` on portability, and nothing has
  changed about that.

### The server grows its own roots and senses tables beside jidhr
- **Pros**: no cross-module dependency; `server` stays self-contained.
- **Cons**: three holders of the same prose instead of two.
- **Why not**: the divergence this ADR exists to end would get worse.

### rootd reads Postgres
- **Pros**: one store, no export step, nothing can go stale.
- **Cons**: rootd's stated pitch is no database, no network, no key — the
  corpus is a file read into memory at startup.
- **Why not**: it would stop being the thing its README describes. It keeps
  consuming an exported file; the export simply gains one author instead of two.

### Senses behind the bearer token
- **Pros**: rate-limiting by identity; all 1,642 in one open call is a scrape
  in a single request.
- **Cons**: the app works with no account today, and voice-follow is
  deliberately reachable without signing in.
- **Why not**: requiring sign-in to learn what a root means makes the verdict
  loop unreachable for the readers likeliest to need it. Rate-limit the route
  instead, which is what `/models/` already does.

### Silent background updates
- **Why not**: the reader picks when bytes move. The app asks.

### A human signs every sense before any of it ships
- **Deferred rather than rejected.** The drafts seed Postgres as they are and
  the reader's thumb is the review. This is the design, not a shortcut: the
  verdict button exists because no threshold found *womb* in ر ح م and a reader
  did.

## Consequences

### Positive
- A sense correction reaches readers in minutes rather than a release cycle.
- Three holders of the same prose collapse to one, and the silent-divergence
  class dies rather than gaining another gate.
- The senses become consumable by anything else that asks, which is the durable
  win and the reason this beats a smaller fix.
- The binary keeps its 30 MB and the app still opens and prays offline.

### Negative
- Senses become a network-dependent surface in an app that is otherwise
  entirely offline. A reader who never connects sees the refusal notice on every
  root, so that notice has to say **why** it is empty. Today it does not
  distinguish "no sense was written" from "no sense has been fetched", and those
  are different sentences.
- The app gains a content-version check, an update prompt, and a transactional
  row-replace path — three things that can fail on a phone.

### Risks
- **Shipping unsigned drafts under signed prose.** `data/root_senses.json`
  still reads "kept only because their glosses bear it out. Not quoted from any
  lexicon." Both halves are false for an LLM draft consulted against Lane, and
  that sentence is drawn one tap from every sense under "Whose reading this is."
  The provenance prose is rewritten before anything ships. This is the deleted
  defect with the name changed, and it is the one risk here that reaches a
  reader as a false claim rather than as a missing feature.
- **Reversibility.** Two-way today — the app is unreleased and there is no
  installed base, so this costs a rebuild. One-way the moment it ships, because
  it changes the cold-start contract for every reader. That asymmetry is the
  argument for deciding it now.

## Out of scope

The human signing workflow. `ayah_translations` — upstream by the authorship
rule and therefore bundled, even though the choice of Rashid Maash 779 over
Hamidullah 31 and Montada 136 was editorial and may change. The poetic
register, which is gated separately and has its own battery to write. Tafsir,
which keeps its honest notice because nothing is licensed. Delta updates
between content versions: a full replace of 0.3 MB is cheap enough that
diffing is unearned.
