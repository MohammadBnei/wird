# 9. The recogniser hears Qurʼanic phonemes, not language

Date: 2026-09-27. Status: accepted. Supersedes the model choice in ADR 0005.
Leaves ADR 0008 (how it is served) standing.

## Context

Voice-follow has not worked on the owner's phone for a week. Eight builds went
to it. The best of them advanced twice and stopped, and every one of the five
recorded fixtures in this repo was green while it did so.

The matcher was not the fault. It was rewritten against an architecture
interview and a doubt pass, it searches the whole set, it follows a reciter
backward, and it refuses a window that names two places. None of that helped,
because the thing being matched against was wrong.

The recogniser was a streaming zipformer transducer covering Arabic among
eight languages. A multilingual model chooses a language from the first sounds
of a stream and carries the choice in that stream's state. بِسْمِ ٱللَّهِ opens
almost every prayer and sounds enough like a Latin word to send it into
English. The owner's screen showed `BIS`, then `然后`, then Cyrillic
mid-recitation, and sherpa-onnx offers no way to pin the language on a
streaming model — `OnlineRecognizerConfig` has no such field.

Everything built to work around that is in the record because none of it
worked: a language guard, a persistence rule so a warming-up model was not
restarted three times in seven seconds, a carried-Arabic-only transcript, and
a stream-replacement path. Measured and rejected on the way: a silent lead-in
(500 ms of silence decodes as `OR`, a second as `A EMOTION`), beam search
(`Э`, and 29% slower), hotwords (which invented a threefold repeat of
ٱلرَّحْمَٰنِ ٱلرَّحِيمِ), and priming with two seconds of Arabic — which works, and
which `SOURCES.md` forbids because it means shipping a mirrored recitation.

## Decision

Wird listens with **Quran-Lab/zipformer_p-arabic-v3**: a streaming zipformer
CTC model over a 251-symbol Qurʼanic phoneme alphabet. One language, one
domain. It writes Arabic letters, the three short vowels, and marks for
gemination, madd and tajwīd.

**There is no Latin letter in that alphabet.** The failure that broke the last
eight builds is not mitigated, it is unrepresentable.

## What was measured

Both models fed the owner's own recorded prayer — the PCM the app itself
captured, not a voice memo — in 300 ms chunks with endpointing on, scored
through this repo's own `locate`:

| | Quran-Lab CTC | multilingual transducer |
| --- | --- | --- |
| ends on word | **19 / 19** | 16 / 19, and stays there 26 s |
| moves | 9 | 5 |
| ever ahead of the reciter | 0 | 0 |
| median per 300 ms chunk | **14 ms** | 24 ms |
| transcript similarity | **0.76** | 0.65 |
| on disk | **72.7 MB** | 339 MB |

Stalling three words short and never recovering is exactly the report the
owner has been making. Run again through the real Dart path rather than
Python — the same `speech.dart` config, the same `locate` — it walks to the
last word at 15 ms median, 27 ms worst.

Across all five graded fixtures, none ever runs ahead of the reciter, and
Ḥuṣarī on Al-ʿAlaq is in step for 116 of 129 windows.

## What this cost, and what it did not

**The fold had to learn a second alphabet.** `recitationKey` reduces both
sides to letters they can agree on, and it knew only the muṣḥaf's. The
recogniser writes what it hears: gemination is the letter twice, a madd is the
vowel held for as long as it is held, tajwīd rides above a letter, and the
qalqala of ٱقْرَأْ is written ءِقڇرَء — the qāf echoing, not a sound of its own.
A run of one letter now folds to that letter, the marks fall away with the
harakāt, and the two nasalisations fold to the letters the muṣḥaf writes.

**The waṣl alif is dropped, on both sides.** The muṣḥaf writes it and
connected recitation skips it, which is precisely what the sign over it says:
ٱلرَّحْمَـٰنِ comes back as رَحمَاانِ. It costs the alif of a word that opens an
utterance — ٱقْرَأْ is said *iqraʾ* — and that is one letter of a window.

**The corpus's own transliteration was tried for this and is not used.** It
answers the waṣl question word by word and correctly most of the time
(`al-yawma` at the head of an aya, `l-yawma` elsewhere). Wiring it in was
measured and is worse: the same transliteration romanises ٱلَّذِى as `alladhī`
wherever it stands, including the mid-aya رَببِكَللَذِۦۦ where the reciter runs it
on, and Ḥuṣarī's in-step windows fell from 116 of 129 to 109. Recorded so the
idea is not had twice.

**`quran_text2phoneme.json`, shipped beside the weights, is not used and is
not a dictionary.** 9112 entries, median eleven words, in Imlaei script; the
whole of al-Fātiḥa is absent. It is a training artifact. Nothing here needs
it — the model's output folds into the muṣḥaf's letters directly.

**Deleted, not mitigated:** `inAnotherTongue`, `_foreignSince`, `_startedOver`,
`heardStuckFor`, `heardStartOver`, `Recogniser.forget`, and the empty-window
stream-replacement path in the isolate. Roughly seventy lines whose only
purpose was to argue with a model that had picked the wrong language.

## Licence, and what it obliges

**Quran-Lab No-Profit License 1.2**, on
`https://huggingface.co/Quran-Lab/zipformer_p-arabic-v3`, gated. Three
conditions, from the access prompt:

1. Never charge for the model, for access to it, or for any feature it powers.
   What is earned from one's own teaching, services or labour is one's own.
2. Never present its output as an authoritative religious ruling on anyone's
   recitation.
3. **State clearly, in any application built on it, that automatic tajwīd
   feedback can be wrong and does not replace a qualified teacher.**

The third is addressed to the person holding the phone, so it is met on the
Sources screen and pinned by a named test, the same way the Quranic Arabic
Corpus's conditions are. The first bears on any future where Wird is charged
for: the model would have to come out.

**Two things are open and are the owner's, not settled here.** The `LICENSE`
file itself is inside the gate and nobody has read it, so whether it permits
*redistribution* is unknown — and the weights are now served from Garage
behind a route that is unauthenticated by design. The terms above are the
access prompt, which is not the licence text. Reading it is cheap today and
impossible to reconstruct later.

The first condition binds the store as much as this repo, and is recorded
where the store is configured: `docs/secrets.md` in infra-bootstrap names the
model and its licence on the `WIRD_MODELS_S3` row and says these objects may
never sit behind anything paid (infra-bootstrap#263). That row also records
why superseded prefixes are not pruned — one prefix per model generation, and
an old one outlives the phones still resuming against it.

## Consequences

- A reader who already downloaded the old model downloads this one too. It is
  72.7 MB against 339, so this is the cheapest migration this feature will
  ever have; `ar-stream/2f361dc0c2c2/` stays published until the owner says
  otherwise, because phones on the current build resume against it.
- `voiceModelParts` is two files rather than four, so an encoder and a joiner
  can no longer disagree.
- The weights are gated, so `scripts/voice-model.py` no longer fetches: it
  takes a directory a person downloaded and stages it. Access is granted to a
  person, not to a script.
- **The model is phoneme-level and marks tajwīd.** Wird uses it only to locate
  the reciter. Colouring recitation by tajwīd is now possible for the first
  time — the corpus has no such annotation and this alphabet does — and is
  deliberately not done here. Condition 2 above is why it would need care.
- Nothing about ADR 0008 changes. The files are served from `wird.bnei.dev`
  under a new prefix; the version key is still the digest of the file digests.
