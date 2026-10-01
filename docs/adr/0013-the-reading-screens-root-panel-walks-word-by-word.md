# 13. The reading screen's root panel walks word by word, where the corpus attribution stood

Date: 2026-09-30. Status: accepted, amended by ADR 0014.

## Context

Screen 1a opened a root only when the reader tapped a word. Reading a passage for its roots therefore meant hunting for the next word to press, and a word with no root could not be opened at all.

The root panel is capped at two fifths of the window ([study_screen.dart#L477-L481](../../app/lib/features/study/study_screen.dart#L477-L481)), so a row added to it is a row taken from somewhere. The row spent was the corpus attribution: `root.sources.join(', ')`, which drew the string `quranic-corpus-morphology` under the kin tags. The Quranic Arabic Corpus asks that its source be indicated and that a link reach corpus.quran.com. Both are answered by About > Sources, which carries the name, the version, the copyright notice and the link, and whose own comment says "This list is where that happens" ([about_screen.dart#L44-L57](../../app/lib/features/about/about_screen.dart#L44-L57)). The Iʿrāb section repeats it on screens 3a, 2b and 1c ([root_sections.dart#L479-L482](../../app/lib/features/root/root_sections.dart#L479-L482)).

## Decision

Two arrows in the root panel move it to the previous and next word of the passage. They flank "Mark set understood", so they cost the panel no height and never scroll away. The attribution line is deleted from 1a.

The walk covers every word, including particles and proper nouns, which carry no root: the panel then shows the word and says it has no root. It reaches every word of the passage drawn on screen, not only the ayas of the acted set, because on a visit the set is one aya and the sūra around it is what the reader is looking at.

The arrows are chevrons, left for the word before and right for the word after.

## Alternatives

- **Up and down arrows, as the footer uses.** The footer's set stepper points up and down because a left arrow beside right-to-left Arabic says two things at once ([reading_nav.dart#L23-L25](https://github.com/MohammadBnei/wird/blob/f5935526eb5ae6c3ffe5427a901b8c4c7fa93f85/app/lib/features/study/reading_nav.dart#L23-L25)). That rule stands for the footer, where the arrows move the page and earlier is above. These arrows move a cursor along a list, which is what the root dial's chevrons already do inside a root panel ([root_dial.dart#L143-L163](../../app/lib/features/root/root_dial.dart#L143-L163)), and each one carries its own screen-reader label, so the direction is not what carries the meaning.
- **Keep the attribution and give the arrows their own band.** Tried: the band took 48px from the scrolling body and pushed the kin tags off the bottom of the panel on the phone the design is drawn for.
- **Walk only the rooted words.** Skipping particles would make the arrows jump, and the reader would have no way to ask what a particle is doing there.

## Consequences

About > Sources and the Iʿrāb section are now the only places in the app naming the Quranic Arabic Corpus, and must keep naming it.

Screen 1a carries two steppers, one for the word and one for the set, a band apart. Their labels have to stay distinct.

A word can now be open without a root, which was impossible before. The rule under a word means "there is a root here" and is drawn only under rooted words ([word_row.dart#L253-L260](../../app/lib/features/study/word_row.dart#L253-L260)).

## Reversibility

Cheap. The arrows are one row and two callbacks; putting the attribution line back is four lines. The signal to undo would be readers pressing the arrows by mistake while reciting, or the corpus asking for its name on every screen that uses it.
