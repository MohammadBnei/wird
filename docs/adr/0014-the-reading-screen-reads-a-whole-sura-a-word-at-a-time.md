# 14. The reading screen reads a whole sūra, a word at a time

Date: 2026-10-01. Status: accepted. Amends ADR 0006 and ADR 0013.

## Context

Screen 1a was a set reader. It served the walk's next set of about five ayas, a footer stepped from set to set, "Mark set understood" recorded the set and moved on, and a header and a root panel folded away. ADR 0006 made the passage around the set readable, and ADR 0013 let the root panel step word by word.

A new design, "Wird Reader", turns the screen around the roots instead. The sūra fills the top half. A sheet under it holds the open word's root: its senses, what the word does in this aya, how often the root and the word's form are read, the root's forms on a ring, and the other ayas it is read in. A sideways swipe on the sheet moves to the next word, and scrolling the sheet shrinks the sūra to one line.

The design's content is placeholder. The corpus holds the words, their glosses, roots, verb forms and parsing, and the counts. It does not hold a numbered list of senses with the one used in each verse, a note on what a form adds, a sentence on what the word means in this verse, related roots, or noun patterns. Those are new authored content, at the scale of 50,000 rooted words.

## Decision

Screen 1a becomes the design's whole-sūra reader, on the data Wird has.

- The set stepper, "Mark set understood", the header fold and the root panel fold leave the screen.
- A reader marks an aya understood by tapping its number. The op and everything that reads it (index marks, progress, offline audio, the dashboard) are unchanged.
- Where the reader stands in each sūra is kept and synced (ADR 0015). The screen opens there, else on the walk's next aya, else on 1:1.
- A drag to the right moves to the next word, because Arabic runs leftward and the next word comes in from the left. The hint row's two ends are buttons with screen-reader labels and do the same, so the walk never depends on a drag. A drag that starts within 24px of the screen's edge is left to the drawer and the back gesture.
- A tap on any word opens it, particles included; a long press sounds it. The open word sits on a filled chip, and the other words of its root are tinted.
- The play button and a Pray action move to the app bar. Both act on the ayas around the open word, the reading width wide, which is what a prayer took before.
- Sections with no data are not drawn: no HERE mark on a sense, no form note, no meaning-in-this-verse sentence, no outer ring of related roots. The "In this verse" card carries the gloss and the corpus's parsing, with its attribution.

## Alternatives

- **Wait for the content before building the screen.** The authored content is months of work, and the layout does not depend on it.
- **Draft the missing content with the model now.** `data/root-sense-prompt.md` forbids claims about a verse, on purpose. Lifting that rule is its own decision.
- **Hand-write Al-Fātiḥa's content as a pilot.** One sūra would read as the design and 113 would not.
- **A second route for the sūra reader beside the set reader.** Two readers to keep in step, and the set reader was what the design replaces.
- **Drop "understood" for the position alone.** The index marks, the width setting, offline audio and "Pray this set" all read it and would have frozen.

## Consequences

The reader has no single act that moves through the Qur'an; the reader moves by scrolling and swiping, and marks what they understood aya by aya.

ADR 0013's chevrons pointed left for the word before. They now point the way the text runs: "‹" is the next word.

The prayer screen is unchanged and still takes a set; how prayer is entered is due its own redesign.

## Reversibility

The screen is two-way: the old screen is in git and its data is untouched. The signal to revisit is readers losing their place in the Qur'an without the set stepper, or not finding how to mark an aya.
