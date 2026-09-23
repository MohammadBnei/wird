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

---

# The answer, 2026-09-24

The question the owner asked three times — why is a root's meaning so hard —
has a settled answer now, and the answer is not "it is hard to look up". It is
that **a root's meaning is a claim, and a claim needs a bar**.

## What was shipped, twice, and what went wrong the first time

The first attempt shipped 493 senses and was reverted whole. The defect that
caught it: غير went out as "to change; to alter" when 154 of its occurrences in
the corpus are glossed *other than* (59), *than* (58) and *without* (49), and
only 4 are *change*. Every reader tapping غير in Al-Fātiḥa 1:7 — the aya every
Muslim recites seventeen times a day — would have been told the wrong thing.

Nothing in the build could see it, because the sense was checked against the
lexicon it came from rather than against the words the Qur'an actually uses.

## The bar, as it now stands

Six independent terms, each fitted to the gap between two populations of
fixtures rather than chosen:

| term | rejects | value |
| --- | --- | --- |
| score | a sense the root's own glosses do not bear out | 0.208 |
| coverage | a sense explaining a minority of its root's occurrences | 0.500 |
| dispersion | a word the root never shows and the corpus reserves for others | 11 |
| branch | a branch over 20.4% of the root that the sense is silent about | 0.204 |
| lead | a first clause explaining less than a later one | unconditional |
| specificity | prose that fits more roots than its own | 1 |

Plus one refusal that is not a term: **two roots handed the same words** are
both refused, because nothing says which one the prose belongs to.

Battery: 72 fixtures. **15/15 right senses pass, 57/57 wrong senses rejected.**
The wrong ones are not strawmen — they are the four ways this actually fails:
doctrinal elaboration ("to fast **from dawn to sunset in Ramadan**"), an
invented clause riding on an attested one, a minority branch left unnamed, and
a sense that leads with the minority.

## What ships

**523 roots, reaching 31,478 of 49,967 glossed word occurrences — 63.0%.**

Each one carries its own evidence: the actual words and glosses it was derived
from, bucketed by morphological shape. A reader can check it. Attribution is
Wird's own wording, and that is stated rather than implied — it is not quoted
from, attributed to, or derived from any lexicon or scholar.

The roots the gate named all read correctly now:

- غير — "other than, without; to change"
- نفق — "to spend; a hypocrite, hypocrisy"
- ملأ — "the chiefs, the assembly; to fill; full"
- سجد — "a masjid, a place of prostration; to prostrate"
- حجج — "to argue; the Hajj; to dispute"

And عود, جمع, كثر, طوي **ship nothing at all** rather than ship something
wrong. An absence is a sense a reader can trust.

## The two closest calls, recorded rather than buried

1. **رحم passes at branch 0.168 against a 0.204 ceiling.** It ships "to be
   merciful; to show mercy" while *gracious* — Ar-Raḥmān — is glossed 57 times
   and goes unnamed. It is the nearest thing to a miss in the shipped set, and
   it is a measured near-miss rather than an unexamined one.
2. **سجد leads with "a masjid, a place of prostration"** for a root whose verb
   forms outnumber the noun 59 to 26. The clause passes because it names both
   branches at once — *a place of prostration* is what a masjid is. Defensible,
   and worth knowing it is the clause doing double duty that carries it.

## Why 63% and not 100%

The 1,119 roots that ship nothing fail for reasons that are recorded per root,
not swept up: 226 are simply not borne out by their own words, and the rest fail
a named term. 399 roots occur exactly once in the whole Qur'an — one word, one
form, no cross-form prediction possible. For those, an honest absence is the
only correct output, and the machinery is built so that absence is what happens
by default rather than by exception.
