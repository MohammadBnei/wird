# 34. A reader starts with a short setup, then a home of few doors

Date: 2026-10-19. Status: accepted. Supersedes in part ADR 0033: the welcome and the place-in-the-walk strip leave home. Amends ADR 0010 and ADR 0026: the verdict on a root's senses leaves the first view of the reading screen's sheet.

## Context

A first-touch walk of a fresh install, at 402x874, found the way in heavy:

- Home had no single first action. "Pray this set" and "Read it first" weighed the same, with Pray on top. Under them sat a welcome paragraph, a 114-tick strip, and four doors that repeated the drawer. That was 115 words and 8 tappables before the reader had done anything.
- "Read it first" opened the reading screen with the root sheet already up: seven senses, the grammar, the provenance and the verdict thumbs. That was 34 tappables and 15 font sizes.
- "Pray this set" opened the full preparation: five prayer chips, a rakʿah stepper, the plan cards, two checkboxes for voice and pace, a microphone button and an explainer.

The owner walked through what a reader should meet, in an interview, and confirmed the result. The plan was then put through two adversarial reviews against the code.

## Decision

- **Setup, once.** A new install opens on one screen with the language, the walk's order and the reciter, each already answered, and Start ([setup_screen.dart](../../app/lib/features/setup/setup_screen.dart)). It is pushed over home, so Start or the system's back lands on home. `setup_done` records it. The language is written only if the reader changes it, so leaving it alone still follows the phone.
- **Old installs skip it.** `openWirdAt` checks, before creating any table, whether `ayah_understood` exists without `setup_done`. Such an install predates setup. It is marked done, and its root panel keeps the open default it always had.
- **Home has few doors.**
  - The set card, where Read is the primary button and comes first, and Pray sits under it as a quiet one.
  - One "Continue <sūra> · <aya>" line for the sūra last read outside the walk. A sūra understood to its end is skipped.
  - Two doors: any sūra, and a prayer of one's own.
  - Where the walk stands, the passage and what is kept are in the drawer.
- **The root sheet starts folded on a new install**, and a word tap unfolds it. The sheet leads with the word and its first two senses, with the rest one tap away in place. The dictionaries, the verdict thumbs and the grammar move below the fold, with the counts.
- **The preparation is lighter.**
  - The prayer and its rakʿahs share one card.
  - The plan is one line per rakʿah. Only rakʿahs 1 and 2 open the chooser.
  - How the text moves is one choice of three: Voice (with the pace as its fallback), Steady, or Tap.
  - A saved voice-alone choice reads as Voice and gets the pace with it, so a phone without the recogniser never leaves the reader tapping word by word.

## Alternatives

- **Pray first.** Rejected: the set is understood before it is prayed, so reading leads.
- **The first action follows the clock or the progress.** Rejected: a screen that changes its main button is harder to learn than one that does not.
- **Pray goes straight into the prayer, with an Adjust link.** Rejected by the owner: the preparation stays, made lighter.
- **Hide the preparation's controls behind More.** Rejected: the prayer, the rakʿahs, the plan and how the text moves all stay in view.
- **A three-step setup, an intro screen, or a setup card on home.** One prefilled screen asks least: Start alone is a complete answer.
- **No setup, as ADR 0033 had it.** The reader never chose an order or a voice, and learned about either only by finding Settings.
- **A "Continue at aya N" state on the set card.** The reading position is kept per sūra (ADR 0015), not per set, so the card could not tell a set begun from one about to begin.
- **A filled primary button.** Nocturne draws the primary as an accent outline, never a fill. Order and the quiet variant carry the hierarchy instead.

## Consequences

- **Setup is a stored flag.** The welcome was derived, never stored; setup cannot be, because what it asks has defaults that look like answers.
- **Where the reader stands leaves home.** That is the question ADR 0033 put there, and it is now one tap away in the drawer. ADR 0033's link to `dashboard_screen.dart#L283` now lands on other code; the ADR is not edited.
- **The senses' review signal weakens.** A reader now votes from below the fold, and may vote having seen two senses of seven. ADR 0010 relies on that thumb as the review of senses no one signed.
- **The tests' corpus seeds an open root panel**, as an existing reader has it. The fold is tested by deleting that row.
- **The reciter sample needs the network once.** A fresh install that is offline hears nothing when it presses a sample.

## Reversibility

Moderate. The setup screen and its flag can be dropped, leaving the flag table empty. Home's removed parts are in git history. Undo the fold if readers stop opening words, and the senses' clamp if most readers open the rest. Restore the strip if readers keep asking where they are.
