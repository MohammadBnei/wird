# Visual testing in the gate — standing rule

Every QA gate from 2026-09-23 onward must LOOK at the screens, not only assert
that tests pass.

## Why this exists

A golden catches DRIFT, not WRONGNESS. A golden captured from a bad screen is
green forever, and the gate that runs it reports a pass. That is not a
hypothetical:

- 1c's constellation golden was captured, committed and green for days while
  the screen was an unreadable squeezed drawing at phone width. Three gates
  passed it.
- The sūra index shipped in an APK the owner was holding when he wrote "we
  cruelly lack a sourat chooser". Every test that touched it passed.
- 1a's settings panel accumulated preferences, navigation and the act of
  starting a prayer. No assertion could object, because each item worked.

Each of those is a screen that behaved correctly and was wrong to look at.

## The rule

1. **Render, then LOOK.** The gate opens the rendered PNGs and describes what it
   sees, in a reader's terms: is it legible, is the hierarchy right, can the
   reader tell what to do next, is anything cramped, clipped, or lost. An agent
   can read an image; use that rather than trusting a byte comparison.

2. **At 402x874.** The phone is the primary device. A desktop window hides
   every failure listed above. Tablet checks happen at 1194x834 separately and
   never instead.

3. **Against the design.** `docs/design/prayer-app-screens.html` is vendored and
   renders in a browser. Put the design and the build side by side and name the
   differences — then say which are deliberate and which are drift. The Chrome
   DevTools MCP can render the design; Flutter renders the build.

4. **A golden that moved must be SEEN before it is accepted.** Not "the diff is
   small" — open the new image and the old one and say what changed and why it
   is right. A refreshed golden nobody looked at is worse than a failing test,
   because it launders a regression into the baseline.

5. **Arabic is checked by eye.** Diacritics, RTL order, and shaping are where
   text stacks diverge, and no assertion catches a mangled harakat. Render a
   vowelled aya and look at it.

6. **Say what a reader would say.** The gate's visual verdict is written in the
   language of somebody using the app — "the constellation is too small to read
   and nothing on it responds" — not in the language of the widget tree.

## What this does not replace

Behaviour tests, the falsification discipline (remove the fix, watch the test
redden), and the doctrine audit all stand. Visual testing is a fifth thing the
gate does, not a substitute for the four it already did.
