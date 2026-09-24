# 6. A passage is read; a set is answered for

Date: 2026-09-24. Status: accepted. Amends ADR 0003.

## Context

The owner walked the app and wrote:

> when reading a surat or selecting one, being required to see only one aya is
> not understandable. Being able to go directly to one on a long surat maybe,
> but only showing one prevents me from reading the Qur'an

He is right, and it is a hole in the design rather than a defect in the code.
`ayaSet` was `WHERE a.id = ?`, one row. ADR 0003 decided that a visit is one
aya — which settled what a visit *means* without noticing that it left the app
with exactly two things: the five-aya set the walk proposes, and one lonely
aya. There was no third thing, and reciting is the third thing. An app named
for a daily portion of recitation had no way to recite.

The cause is in the project's own history: the design was drawn around
Al-ʿAsr, three short ayas, and every assumption downstream inherited that
scale. The set abstraction is right for prayer and wrong for reading.

## Decision

**The screen renders a passage. What varies is where the passage came from.**

- The walk proposes a **set** — five ayas, a prayer, "Pray this set".
- The index names a **place** — the sūra, opened at the aya chosen, read on.

That is two concepts in place of "a set, or one lonely aya", and one of them
can now read the Qur'an.

**Reading is not acting.** `StudySet` keeps `ayas` — what is marked, prayed,
named in the header and pinned on disk — and gains `reading`, what is drawn
around it. On the walk they are the same list. Off it, `ayas` is still the one
aya the reader asked for and `reading` is its whole sūra. Everything ADR 0002
and `nextSet` depend on therefore did not move:

- The set id is still `uuidv5(ns, "order:start:end")` over `ayas`, so a visited
  aya derives the same single-aya id it always did and the checked-in vectors
  still hold.
- Marking writes `ayas` and nothing else. Scrolling through 286 ayas of
  Al-Baqarah writes nothing at all, so the walk's derived position is
  untouched — it still starts at the first aya not understood and still stops
  before the next one that is.
- `pathsToKeep` pins `ayas`. Off the walk that is one aya, exactly as ADR 0003
  decided; widening it to the sūra would have tried to download 286
  recitations to satisfy a cache cap of a few dozen files.

Widening `ayas` to the sūra instead of adding `reading` would have marked,
prayed, pinned and derived an id over 286 ayas at a stroke. The two lists are
the whole decision.

**The index's rows open sūras.** A sūra row answers with that sūra's first
aya, because choosing a sūra means reading it. The grid of aya numbers is
still there for the reader who wants a particular aya of a long one; it is a
second, rarer intent, so it moves off the row and behind a chevron.

## The engineering, which is the long sūra

Al-Baqarah is 286 ayas and 6116 words. `_ayas` built a `Column` of every word
in the set — correct for five ayas, ruinous for 286.

**The list is lazy in both directions.** The passage is a `CustomScrollView`
whose `center` is the aya the reader opened on: the slivers before it grow
upward, the slivers after it grow downward, and neither builds an aya until it
is near the viewport. So 2:255 opens at 2:255 without laying out the 254 ayas
above it, and the reader can still move up into them, because a sūra is
continuous. This is Flutter's own mechanism; no package was added for it.

**The query does not read a sūra to draw a screenful.** `ayaSet` reads 286 aya
rows with a word *count* each, and the words of the opened aya alone.
`wordsFor` then reads the rest a chunk at a time — four ayas back and twelve
ahead of whatever the list is building, in one query per chunk, because a
query per aya would be 286 of them.

Measured on the shipped corpus, opening Al-Baqarah at 2:255 on a 402×874
phone:

| | eager `Column` | lazy passage |
| --- | --- | --- |
| open | 1875 ms | 137 ms |
| one frame after it | 0.16 ms | 0.25 ms |
| a 900 px scroll | 404 ms | 42 ms |
| word tiles alive | 6116 | 74 |
| heap over the test's own baseline | — | +3.8 MB |

`ayaSet` itself is 19.8 ms for 286 aya rows and 50 word rows. The same sūra's
words read in one go is 18.3 ms for 6116 rows; a chunk of seventeen ayas is
5.6 ms for 544.

## Consequences

- The recitation still carries `ayas`, so while a sūra is being read the
  player holds the aya it was opened at. That is forced rather than chosen:
  only what is pinned is on disk, and ADR 0003 pins one aya off the walk.
  Tapping a word further down the sūra shows its transliteration and plays
  nothing, which is the same honest answer the screen already gives for an
  undownloaded aya. Recitation that follows the reader down a sūra needs the
  pin rule reopened, and is not decided here.
- The recitation bar sits where the acted set ends: under the last aya on the
  walk, under the visited aya while a sūra is read. It is a boundary marker as
  much as a transport, and a reader may take it for the end of the text. If
  that is confirmed by use, it belongs pinned under the list rather than in it.
- ADR 0003's "1a shows the visited aya, with no second mode" still holds — the
  visited aya is still what the screen is *about*. What changed is that it is
  no longer all the screen *shows*.
- The set-width handle is still unreachable while visiting, for the reason ADR
  0003 gave: a width is remembered against the aya a set starts at.

## Open: what the prayer tiles on screen 1d count

Recorded 2026-09-25, undecided.

The prayer write falls through the split this ADR drew. `recordSetPrayed`
writes `set.ayas`, and off the walk that is the one aya the reader went to
see — so "Pray this set" on a visited aya lands a `set_prayers` row against a
set id the walk will never derive and the reader will never be asked to mark.
That is not a defect: praying a passage you chose is what the app is for, and
the button is drawn while visiting on purpose.

Screen 1d then read those rows twice over. "Sets understood" is replayed from
the walk; "prayers on them" was `COUNT(*) FROM set_prayers` with no predicate;
"prayers per set" divided the second by the first. Two populations, one
division. Two finished sets and thirty prayers on visited ayas read "prayers
per set 15.0" where the walk's own figure was 0.0. Before addressability the
two could already disagree — a set prayed twice and never marked has always
counted — but that gap closed: a walk set is eventually marked and rejoins the
denominator, and a visited aya never is. The drift only went one way.

What shipped is the small half: the tile is called **prayers recorded**, which
is what the query counts, and nothing divides by the walk any more. No
plausible-looking number that nobody computed.

The recommendation is to scope the numerator instead of deleting the ratio:
count only prayers on sets the walk has finished, and "prayers per set" is
honest again. It costs no second walk — `setsUnderstood` already replays the
walk aya by aya and can emit each finished set's id as it goes, which is
exactly the predicate the count needs.

It is left open because it is a decision about what the tile is for, not about
arithmetic. Scoping the numerator means a reader who prays a chosen passage
every evening sees no trace of it on this screen, which reads as the app not
noticing. The third reading — two prayer tiles, one for the walk and one for
everything else — says the true thing twice and costs a tile. The owner picks.
