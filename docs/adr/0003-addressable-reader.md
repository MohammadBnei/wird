# 3. Screen 1a is addressable, and it changes in place

Date: 2026-09-23. Status: accepted.

## Context

The app was a walk and only a walk. It hands the reader the next set of ayas
not yet understood, and that was the one way into the text. Aya references were
printed all over it — kin in the root panel, nodes in the constellation, the
captions on 3a — and none of them led anywhere, because nobody had answered
what happens to the walk when a reader visits an aya it did not choose. There
was no sūra list either, so a reader who wanted Al-Fātiḥa, or the aya they were
thinking about, could not ask for it.

## Decision

**1a shows the visited aya, with no second mode.** The walk's position is
derived — the next aya not yet understood, in the chosen order — so visiting
costs nothing. Marking a visited aya understood counts like any other mark, and
the walk recomputes around it: it still starts at the first aya not yet
understood and still stops before the next one that is, so a visit leaves a hole
rather than moving the reader.

A visit is **one aya**, not a set the walk proposed. The set-width handle is not
drawn while visiting: the width is remembered against the aya a set starts at,
and a set pulled wider while merely visiting would change what the walk proposes
when it arrives there months later.

**The jump happens in place, and never as a push.** `Routes.study` is the
initial route. Pushing a second 1a onto it would leave two live `AudioPlayer`s,
the lower one disposed only when the upper is popped, behind a reader who
believes they went forward. So there is one 1a and it changes what it shows; a
screen above it names the aya the reader chose by **popping the id down** to it.
1d passes the index's answer on the same way. `StudyScreen.target` exists for
the same reason in reverse: it is how the screen is *built* on an aya, which is
what a pop-with-result and any future deep link need.

**What is downloaded depends on where the reader is.** On the walk, 1a keeps the
set being studied and the set after it, because the second is what the reader is
handed next. An aya the reader asked for has no set after it — `nextSet` does not
know the reader went anywhere and answers with the *walk's* next set — so off the
walk, only the visited aya is kept. Two further rules fall out of a screen that
now loads many times rather than once per set:

- The cache sweeps only when a file was actually written. It is synchronous file
  I/O over every file on disk, and it deletes everything the current pin list
  does not name — so a jump to an aya already downloaded would have cost a scan
  of hundreds of files *and* thrown away the set the reader was walking.
- A prefetch that has been overtaken stops. A download outlives the screen state
  that asked for it, and the pins it set are no longer what is on screen.

**`rootReading` is authoritative about what a kin is.** The study panel used to
run a second query that grouped words by their raw text, which keeps the pause
mark the corpus stores on the word it follows — so one derivative counted as
two, and the panel and the root screen disagreed about the same root while both
looked right. The panel now takes its four from the same list the root screen
reads, and that list already carries an aya.

A kin leads to where that form is **first met in the muṣḥaf**. A form occurring
eighty times has no single aya, and the first is the only one that can be named
without inventing a rule the reader cannot see.

## Consequences

- 1d's "All 114" finally points at 114 sūras rather than at the kept list.
- The root panel carries one primary action, "Mark set understood". The
  constellation was a full-width button beside it and is now a ghost link inside
  the panel: one of the two moves the reader through the Qur'an and the other is
  an occasional detour.
- A visit is not recorded anywhere. Contract 3 holds: nothing about the reader's
  position is stored, so the reading order stays switchable.
- The set-width handle is unreachable while visiting, which means a reader
  cannot pray a visited aya together with its neighbours. Praying one aya is
  still possible; a wider portion means going back to the walk.
