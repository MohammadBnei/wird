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

**One clause per sense the root carries**, separated by `; `, concrete sense first
where one plainly yields another. Never repeat a clause.

Write no number of them. Any figure here becomes a target — a range was tried and
the drafts piled up on its highest value, and naming a typical length pulled them
down to that instead. A narrow root is short and a wide one is long, and the only
question for each clause is whether the root carries that sense.

One clause per sense, and not one per example of it. Heat, effort, wind and rain
being violent are one sense written four times, not four senses. If two clauses
would be glossed the same way, they are one clause.

**The heaviest sense opens the list**, whatever its place in the root's development.
The counts below decide this. A reader who taps a word meets the sense they were
reading, and a root whose commonest branch sits sixth has answered someone else's
question — write the concrete origin, but do not lead with it when the reader's
sense is elsewhere.

Choose the branches that **share the root's underlying idea**. Lane's noun entries
also record incidental things a word of the root can denote — a particular bird, a
kind of bread, a sort of cloud, a skin complaint. Those are attested and they are
still not senses of the root: they are things one of its words happens to name.
Leave them out.

Writing one as a verb does not make it a sense. "To be a swift and excellent
horse", "to be the palm of the hand", "to be of one unmixed colour" are a bird and
a bread and a cloud with `to be` in front. Ask what idea the clause carries, not
what grammatical shape it wears: if the answer is a particular thing rather than
something the root does or means, it does not belong.

The test is whether the thing says the idea. A mountain and a ship's ballast both
say *holds fast under load*, so they earn a place beside patience. A red-bellied
bird says nothing about the idea and does not, however faithfully Lane records it.
When a branch only passes because Lane mentions it, that is not passing.

Each clause names what the root **does**, not what one of its words **is**. A run
of "to be a X; to be a Y" is the denotation list above wearing a verb.

Do not adopt one sentence pattern for every clause. Clauses that all share a
shape read as a template rather than as a reading, and the shape starts standing
in for the sense.

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

  It is crossed by naming doctrine as well as by citing chapter and line. "A
  bridge, narrow and perilous, over an abyss" is the sense; "the bridge over
  Hell" is a doctrinal claim about a named thing and does not belong, however
  standard it is. Where a word has become a term of religion, give the sense the
  term was built on and stop there.
- **French is written, not translated.** Write the French as French lexicography.
  Its clauses may differ in number and order from the English if that is how
  French says it. Do not calque.
- **The counts say what a reader meets, and that decides the ORDER.** A branch
  carrying a hundred occurrences belongs in the sense and belongs early; one
  carrying three belongs if Lane attests it, but not first. Lead with the concrete
  sense where one plainly yields another, and otherwise with weight.

- **Do not paste a gloss in as a clause.** The glosses are word-in-context
  translations, not senses: "the Most Merciful ×72" tells you mercy is the heavy
  branch, and the clause you write for it is still yours. A sense assembled out of
  glosses is the corpus talking, which is the thing this is not.

- **Contradiction, not coverage.** Nothing you write may contradict the glosses.
  They are not a ceiling either — a sense Lane attests and the Qur'an never uses
  still belongs, and a root whose occurrences are nearly all one proper name will
  leave most of its count unaccounted for however complete the sense is.
- **Where Lane is absent** the entry says NO LANE ARTICLE. Write from what you
  know of the root and keep it to what you are sure of.

## Answer

A single JSON object and nothing else. No prose before or after, no code fence.

Each of the four strings is a finished sentence or a finished list: no trailing
`;`, no trailing comma, nothing left hanging at the end.

{"sense_en": "...", "sense_fr": "...", "poetic_en": "...", "poetic_fr": "..."}
