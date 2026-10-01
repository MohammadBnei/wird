# 21. The matcher's margin is asked per pair of places, and a repeated phrase is settled by order

Date: 2026-10-01. Status: accepted. Amends ADR 0020 (the unseen basmala).

## Context

The matcher scores the last few words heard against every word end of the rakʿah and moves only when one place clearly wins. Until now "clearly" was one number for every pair: the best place had to beat any place two or more words away by 0.32.

That rule pinned the cursor on any set that says a phrase twice. Al-Fātiḥa says ٱلرَّحْمَٰنِ ٱلرَّحِيمِ in 1:1 and again in 1:3, and every rakʿah now opens with Al-Fātiḥa. The rakʿah also carries the unseen basmala before the passage, a third copy of 1:1. In the second field walk the cursor stood on word 1 from 3.6 s to 36 s. Replayed, 27 of the trail's 48 windows were refused by the margin ([finding 9](../journal/voice-follow-walk.md#9-the-margin-rule-pins-the-cursor-on-any-set-that-says-a-phrase-twice)). Three of them sat at a margin of exactly 0: the two places fit equally well, so a lower global margin cannot be the answer.

The rule the matcher lives under is unchanged: a wrong place is worse than a late one. The phone is on the floor during the prayer and a wrong jump cannot be fixed by hand.

The owner's decisions shaped the answer. The margin is decided per set, from the set's own text. Between the copies of a repeated phrase, "the closest to the actual position, moving forward, should win". Al-Fātiḥa is never offered as the passage, since it would put every word in two places.

Prior art was surveyed. No Dart library does this.

- NurraLLC/quran-reader (MIT) precomputes the ayas that share a 4-word phrase and waits on a collision.
- The Mutashabihat census (arXiv 2609.14967) finds that 16.5% of ayas share a 4-word opening with another aya. Repeats are the normal case, not an edge.
- Live Gurbani tracking (arXiv 2607.13457) allows backward moves only behind a switching margin.
- Nakamura et al. (arXiv 1512.07748) follow a score with an HMM that allows arbitrary repeats and skips.

## Decision

`explain` in [alignment.dart](../../app/lib/features/prayer/alignment.dart#L289-L379) decides in five steps, and every number it uses is a field of `FollowTuning` ([alignment.dart:47](../../app/lib/features/prayer/alignment.dart#L47-L130)).

1. **Score** every word end against the heard tail (24 letters), reading 6 letters of slack so dropped letters do not push the start out of reach.
2. **Best** is the top score, or the earliest place within 0.05 of it.
3. **Repeats** are places whose own text is at least 0.7 alike to the best place's (`Recitation.sameText`) and that score within the margin asked of them. Audio cannot tell them apart. With the cursor known, the nearest repeat at or after it, within 12 words, is taken. A reciter is at or past the cursor, so that copy is never ahead of them.
4. **Rival** is the closest other place that is not a repeat. The margin asked of that pair is `max(0.15, 0.32 × (1 − sameText))`: places the set itself makes alike are asked for less, never below the floor.
5. **Verdict** is one of `tooLittle`, `lowFit`, `unclear`, `repeatNotAhead` or `move`. The prayer trail, the Settings check and the bench all print it.

Each number was argued from the bench, [follow_bench_test.dart](../../app/test/features/prayer/follow_bench_test.dart#L1-L27). It replays studio reciters, the owner's own recordings, two Mac trails, synthetic rakʿahs of five short sūras (perfect and three noisy seeds each), a repeated aya, a dropped word, another sūra and the bowing praise. It grades five requirements: never a wrong place, reach where the reciter got, a ratchet on windows ahead, non-set speech never moves, and a ratchet on windows behind. `SWEEP=1` prints a per-knob table. The sweep results sit beside each field.

The measured effect: on the walk-two Mac trail the old matcher moved in 8 of 49 windows and the new one in 21. On al-Kāfirūn with noise, windows behind the reciter fell from 29 to 3. No condition has a wrong place.

## Alternatives

- **Lower the global margin.** It cannot refuse a true tie, and three refused windows were true ties.
- **A general prior towards the nearer place.** Tried once and removed. It moved the prayer on evidence that named two places equally well, and a wrong place is worse than a late one.
- **Match inside the current aya first.** A position prior under another name, with the same failure.
- **An HMM filter now.** More knobs than the bench can yet argue. Kept as the next step if the bench shows pins the per-pair margin cannot clear.

## Consequences

- Where the screen stands is now an input to the matcher, but only to choose between copies of one phrase. Places that merely sound alike are still told apart by the margin alone.
- The unseen basmala before the passage is a repeat of 1:1, settled by order, rather than refused. ADR 0020's "the margin refuses both" no longer holds.
- A cursor that ran ahead of the reciter, by the pace or a reader going back, can take a copy that is ahead of them too. `repeatReach` bounds that guess to about one aya.
- A change to any number goes through the bench. The real trails carry no position truth, so the bench cannot see every wrong jump. The floor of 0.15 is pinned by a test of its own for that reason.
- Every caller shares one `explain`, so the trail, the Settings check and the prayer cannot disagree about why the screen stayed.

## Reversibility

Cheap. The matcher is one file and `FollowTuning` keeps the old rule close at hand: `marginFloor` equal to `margin` and `repeat` above 1 restore a fixed margin with no repeats. That is not the old matcher exactly — the slack and the free-start scoring stay — so a full revert is the file at the commit before this ADR. Signals to revisit: a wrong place in a field walk, a bench condition that only an HMM clears, or a trail with position truth that shows the floor costing more than it saves.
