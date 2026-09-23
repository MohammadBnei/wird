# Walkthrough notes

Observations from using the app, collected before building, so the gaps get
addressed as gaps rather than patched one at a time.

Status: open — being filled during a walk of the app.

## Findings

### 1. The root screen shows no sense, poetic or plain

**Where:** 3a root dial, 2b spine, 1c constellation.

**What:** a root renders as letters, transliteration and an occurrence count.
The design shows a core sense and a poetic reading beside them — "To bind
fast; to hold a thing to its place. Patience is the rope, not the mood."

**Why:** `corpus.db`'s `roots` table is `letters, display, translit,
quran_occurrences, sources` and carries no sense text at all, because it is
built from the Quranic Arabic Corpus — a grammatical annotation (root, lemma,
part of speech, form), not a dictionary. It says a word's root is ص ب ر and
never what ص ب ر means. The design's own poetic lines were authored for the
mockup. `jidhr` has the table waiting (`register IN ('plain','poetic')`, per
language) but no content, and the app never calls `jidhr` — root lookup reads
the bundled corpus so it cannot touch the network.

**Shape of the gap:** authored writing for ~1,642 roots, plus a pipeline to
carry it into the bundled corpus. Decided: draft the roots a reader actually
meets first, from public-domain lexicons, with the plain gloss as the fallback
elsewhere.

**Guardrail:** the poetic register is lexicography with a voice, not tafsir. A
claim about the word, never about the verse.

### 2. An aya reference is printed everywhere and navigable almost nowhere

**Where:** 3a kin rows, 3a detail card, 1c constellation nodes.

**What:** kin rows and constellation nodes show `2:153`, `30:60`, `THIS AYA ·
103:3` as captions. The kin rows' `onTap` only moves the dial
(`root_sections.dart:153`); the constellation nodes have no gesture at all.
The one wired control, "Read the aya" (`root_screen.dart:246`), pushes 1c —
the three-pane analysis — when a reader who taps 2:153 wants to read 2:153.

**Why it stopped there:** nobody had answered what happens to the reading walk
when a reader visits an arbitrary aya. The plan's acceptance rows never
covered it and the design draws no such screen.

**Decided:** 1a shows the visited aya with no second mode. The walk position is
derived ("the next aya not yet understood in the chosen order"), so visiting
costs nothing, marking a visited aya understood counts normally, and the walk
recomputes correctly afterwards.
