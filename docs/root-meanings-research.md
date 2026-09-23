# Root meanings — the research question, before any plan

Status: not started. This note exists so the framing is not lost, because the
framing is the valuable part.

## The wrong framing, and why it cost days

The first approach treated this as an ACQUISITION problem: find a licensed
lexicon, bundle it. That ran into Perseus's CC BY-SA 3.0, which has no path
into an AGPL-3.0 binary, and then into OCR as a workaround.

It was the wrong problem. Knowing what an Arabic root means is not scarce
knowledge — it is common, ancient, and free. What is scarce is a *machine-
readable dataset of 1,642 root senses with a clean licence chain*, which is a
different thing, and chasing it is what produced the OCR plan.

## The right framing, from the owner

Two observations, both of which make the meaning DERIVABLE and CHECKABLE rather
than generated and hoped-for.

### 1. Arabic is structured: root + pattern → meaning, by rule

A root carries a core sense; a wazn transforms it predictably. Form II is
causative or intensive, V its reflexive, VII mediopassive, VIII reflexive, X
requestive, and so on. So a root's core sense plus a known form PREDICTS what a
word should mean.

**That inverts the problem.** Rather than generating a sense and asking whether
it looks right, propose a sense and test whether it predicts the glosses the
corpus already carries for that root's attested words, across every form.

We hold everything required, licensed, already bundled: 77,429 words, each with
its root (`words.root_letters`), its morphological form (`words.form`,
`words.morphology`) and an English gloss (`words.gloss_en`).

Worked example — a proposed sense for ص ب ر must generate:

| Word | Form | Attested gloss |
| --- | --- | --- |
| صَابِرِينَ | active participle | the steadfast |
| فَاصْبِرْ | I, imperative | so hold fast |
| وَاصْطَبِرْ | VIII, imperative | and persevere |
| صَبَّارٍ | faʿʿāl intensive | deeply enduring |

"To bind fast; to hold a thing to its place" generates all four. "To be sad"
generates none. The test is mechanical and runs over every root at once.

This is FALSIFICATION, not coherence — strictly stronger than checking that a
sense merely does not contradict its family.

### 2. The Qur'an is the most translated book in existence

Where many independent translators render a word alike, that agreement is
evidence no single model's opinion outweighs. Where they diverge, the divergence
IS the signal: the word is contested, and the app should say so rather than pick
a side.

This also gives the French half a route. French translations of the Qur'an are
numerous and old enough that some are public domain — so French need not be a
translation of our English guess; it can be constrained by the same evidence.

## What the research has to answer

1. Which morphological rules are reliable enough to predict a gloss, and which
   are too loose to test against. Form IV and Form II overlap in practice.
2. What counts as a prediction succeeding. Glosses are short English phrases,
   not formal semantics; the match is fuzzy and the threshold needs measuring,
   not choosing.
3. The 399 roots occurring exactly once. One word means one form means no
   cross-form prediction. These need a different treatment or an honest absence.
4. Which translation sets are licensed for this use — for *evidence*, which may
   be a weaker requirement than for redistribution, since a statistic derived
   from many translations is not any of them.
5. Where the poetic register comes from once the plain sense is pinned. It is
   authored voice, and the guardrail stands: a claim about the WORD, never about
   a verse.

## The guardrail, unchanged

The poetic register is lexicography with a voice. Never tafsir. Never a claim
about what a verse means. Nothing invented is ever presented as sourced — the
defect this project already deleted once, where invented prose shipped under
Ibn Fāris's and Lane's names.
