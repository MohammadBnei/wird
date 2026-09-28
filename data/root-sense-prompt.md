<!--
The prompt `server/cmd/rootdraft` sends, one root at a time. THIS FILE IS THE
KNOB. Edit it, re-run a few roots with -dry to read the assembled prompt, then
run for real. Every drafted row records the SHA of this file, so you can always
tell which prompt wrote which sense.

Placeholders the command substitutes:
  {{ROOT}}        the root, in Arabic letters
  {{OCCURRENCES}} how many times a word of this root occurs in the Qur'an
  {{GLOSSES}}     the distinct English glosses the corpus carries for its words
  {{LANE}}        Lane's article for this root, or the words NO LANE ARTICLE
-->

You are writing the entry for one Arabic root in a Qur'an reading app.

Root: {{ROOT}}
It occurs {{OCCURRENCES}} times in the Qur'an.

The glosses the app's own corpus carries for this root's words:
{{GLOSSES}}

Lane's Lexicon on this root:
{{LANE}}

## What to write

Four fields. Two registers, two languages.

**The plain sense** is the root's range, not the range the Qur'an happens to use.
A root carries several senses at once, and holding them together is what makes
Arabic readable: a reader who knows the root behind patience also means binding
fast reads patience differently.

**Between two and six clauses**, separated by `; `, concrete sense first where one
plainly yields another. Never repeat a clause, and never continue past the sixth —
a list that runs on is worse than a short one, because a reader stops reading it.

Choose the branches that **share the root's underlying idea**. Lane's noun entries
also record incidental things a word of the root can denote — a particular bird, a
kind of bread, a sort of cloud, a skin complaint. Those are attested and they are
still not senses of the root: they are things one of its words happens to name.
Leave them out.

The test is whether the thing says the idea. A mountain and a ship's ballast both
say *holds fast under load*, so they earn a place beside patience. A red-bellied
bird says nothing about the idea and does not, however faithfully Lane records it.
When a branch only passes because Lane mentions it, that is not passing.

Write each clause as a sense, not as a thing: *to be firm, as a mountain is* over
*to be a mountain*. A list of "to be a X; to be a Y" is a list of denotations,
which is the mistake above wearing a verb.

**The poetic line** names the connection the plain list can only enumerate. One
sentence, and the register that says *why* these senses are one word — not
decoration, and not a summary of the plain sense.

Its shape, illustrated on a root that is NOT the one you are writing: for a root
meaning both *to pour out* and *to be generous*, "What is poured cannot be
counted back: the open hand and the spilt jar." **Write your own. Do not reuse
those words, that image, or that sentence pattern.**

## Rules

- **Your own wording.** Lane is consulted, never quoted. Do not reproduce his
  sentences; write the sense as you understand it.
- **A claim about the word, never about a verse.** Name no sūra, cite no verse,
  and do not explain what a passage means. That is the line between lexicography
  and tafsir, and it is not yours to cross.
- **French is written, not translated.** Write the French as French lexicography.
  Its clauses may differ in number and order from the English if that is how
  French says it. Do not calque.
- **Contradiction, not coverage.** The corpus glosses above are a check: nothing
  you write may contradict them. They are not a ceiling — a sense Lane attests
  and the Qur'an never uses still belongs.
- **Where Lane is absent** the entry says NO LANE ARTICLE. Write from what you
  know of the root and keep it to what you are sure of.

## Answer

A single JSON object and nothing else. No prose before or after, no code fence.

Each of the four strings is a finished sentence or a finished list: no trailing
`;`, no trailing comma, nothing left hanging at the end.

{"sense_en": "...", "sense_fr": "...", "poetic_en": "...", "poetic_fr": "..."}
