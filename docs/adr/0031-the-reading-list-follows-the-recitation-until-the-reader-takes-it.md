# 31. The reading list follows the recitation until the reader takes it

Date: 2026-10-04. Status: accepted.

## Context

The reading screen scrolls its sūra list for three reasons: the reader taps a word, the reader steps to the next word, and the recitation moves on. PR #33 stopped centring a tapped word the reader could already see. In use, centring was what the reader wanted back, and the recitation did not follow at all.

A first answer made each a reader-facing switch in Settings: "centre a tapped word" and "follow the recitation". The next step would have been an enum per switch, after the playback knobs of ADR 0030. Neither decided what happens when the reader and the recitation pull the list in opposite directions, and every new value doubled what had to be tested.

An adversarial review of the design below found 14 problems. Most came from treating the recitation's word (`currentWordId`) as the only signal, and from the lazy list: an aya far from where the list hangs is not built, so it cannot be scrolled to.

## Decision

One rule: the list moves to show the reader what they asked to see, never away from what they are looking at. The list has two owners, the reader and the recitation, and the reader's hand always wins.

- A tapped word, and a sūra opened on an aya, are centred. A step centres the open word only once it has walked out of view.
- Pressing play, in any form, makes the list follow the recitation. It follows only the sūra or an aya playing, never a word heard alone.
- Following turns the page: once the recited word passes two thirds of the way down the list, it is scrolled to a third from the top. The list moves about once a third of a screen, not with each word, and a turn that cannot move the list (at the sūra's end) does nothing.
- Anything the reader does to the list releases it: a scroll the screen did not start (drag, fling, wheel, scrollbar, screen reader), a finger put down while the screen scrolls, a tap on a word, a step, expanding the sheet, opening another aya. The screen marks its own scrolls so they are not mistaken for the reader's.
- While the recitation plays and the list does not follow, a "Back to recitation" chip sits over the list. It, or play, takes the list back to the recitation.
- A recited word whose aya is not built rebuilds the list hung from that aya, as "Read from here" does.
- While following, the reading position moves with the recited word, so a reader who read along comes back where the recitation was.

There are no settings for any of this.

## Alternatives

- **Two on/off switches in Settings** — every reader has to decide something the design should decide, and neither switch says who wins when the reader and the recitation disagree.
- **An enum per switch, as the playback knobs** — the combinations grow faster than they can be tested, and the clash between hand and recitation is still not decided.
- **No following** — the recitation runs off the screen.
- **Following with no release** — the list pulls itself away from the reader's thumb with every word.
- **Keep the recited word in the middle** — the list moves at every line, and a tap during a scroll only stops the scroll.

## Consequences

- The Settings switches added on the way (`centre_tapped`, `follow_recitation`) never reached `main`, so no stored choice is stranded.
- Future behaviours that interact are designed the same way: who owns the interaction, one sentence that covers every case, a pattern readers already know, and no setting unless the default cannot serve a reader.
- A tap during the screen's own scroll only stops the scroll; the reader taps again. Turning the page rather than centring keeps those scrolls rare.
- After a jump to an aya that was not built, the ayas above it get their real height as their words are read, so the turn after can nudge the list once.
- The prayer screen's own following, and the playback knobs of ADR 0030, are not changed here.

## Reversibility

Cheap. The behaviour lives in the reading screen and stores nothing. If readers fight the list during a recitation, the signal is reports from the reading screen about the list moving on its own; the first lever is the turn point, then a build-only knob to try variants.
