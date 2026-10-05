# 32. Home says where the reader stands, and the root constellation is gone

Date: 2026-10-05. Status: accepted.

## Context

Home was written as "the way in, not a second progress screen". It named the waiting set and nothing else, so a reader could not tell where in the Qur'an the walk had reached without opening the passage screen (1d). A fresh install also opened on "SET 1 · WAITING" with no word on what a set is.

The default walk is the order of revelation. It opens on Al-ʿAlaq, which sits in juz 30. A juz number on home would tell a newcomer they are at the last juz of thirty.

Screen 1c drew a root's family as a constellation: a star chart of up to five forms around the root. It only showed on panes at least 500 points wide, so phones never saw it. It said nothing the spine under the ring does not, and readers did not use it.

## Decision

- Home shows a short welcome until the reader has understood an aya or recorded a prayer. This is derived from `ayah_understood` and `set_prayers` and is never stored as a flag. Opening a sūra does not count as starting.
- The waiting set sits on a card with its Arabic text. A set is at most 25 words, so the whole set fits.
- Under the card, one line and one strip say where the walk stands ([dashboard_screen.dart#L283](../../app/lib/features/dashboard/dashboard_screen.dart#L283)):
  - The line gives the sūra's place among the 114, counted in the order the reader walks.
  - The juz is named only in the muṣḥaf's order.
  - The strip has one tick per sūra, in the walk's order. Each tick is lit by how much of that sūra is understood, and the current sūra stands taller.
- The passage screen names the next aya and lists the sūras opened outside the walk. Tapping one answers that word down to home or the drawer, which open the reader on it.
- The constellation is removed. Screen 1c always draws the ring with the spine under it. The button that opens 1c is now called "Deep dive".

## Alternatives

- **A juz strip on home.** The ring on 1d already has one. Under the order of revelation it lights cells scattered across the strip and points at juz 30 first.
- **Leave position on 1d only.** That keeps home narrow, but the question readers ask first ("where am I?") would stay two taps away.
- **Remove the whole deep dive with the drawing.** Rejected because "Keep this aya" lives there and nowhere else.

## Consequences

- Home now carries two derived figures: the sūra's place in the walk, and the count of ayas understood once it is above zero. Both are read at draw time, like everything on 1d.
- Home reloads only when it is uncovered. A sync that lands while home is on top shows the welcome until the next uncover.
- Anything that pushes the passage screen must accept an `AtWord` as well as an aya id.

## Reversibility

Cheap. The strip and the welcome are self-contained widgets in one file. The constellation can be restored from git history. Undo the strip if readers mistake it for a progress bar of the whole Qur'an.
