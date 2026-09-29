# 5. Voice-follow locates the reciter with a Qur'an model on the phone

Date: 2026-09-24. Status: accepted. **Amended 2026-09-25: the model is a
streaming transducer, not whisper. Amended again 2026-09-27 by ADR 0009: the
model is an Arabic-only phoneme CTC model, not a multilingual transducer.**
The reasoning below stands — the job is
locating rather than transcribing, the model stays on the phone, the tap
remains the fallback — but the engine chosen to do it could not, and the
reason is at [The engine changed](#the-engine-changed-and-why). Read that
first; the whisper numbers in *Measured* are kept because they are what the
decision was made on, and they were not wrong, they were the wrong question.

## Context

Screen 1b advances on a tap. The design reads "nothing to tap" and says
"Following your voice", and ADR 0001 left the ASR engine open as the one
genuinely two-way decision in the stack.

The screen it runs on has a contract that decides everything below. Nothing may
appear in front of someone praying: no permission dialog, no download prompt,
no spinner, no error, no snackbar. A wrong advance is worse than no advance —
the reader looks up and the app has moved them somewhere they are not, mid
prayer, with no good way to recover. And the recitation is worship, so it does
not leave the phone.

The insight that makes this tractable: **the app is not transcribing, it is
locating.** `PrayerCursor.follow(position)` wants "where is the reciter now",
and the app already holds the text. A noisy hypothesis matched against the next
few expected words is a far smaller question than open transcription, and it
degrades into standing still rather than into nonsense.

## Decision

**Engine: `sherpa_onnx` (1.13.8, pub.dev, Android + iOS), running Whisper
offline on the device.**

**Model: `tarteel-ai/whisper-base-ar-quran`**, fine-tuned on `everyayah` — the
same corpus the app's own reference recitation comes from — converted to
openai-whisper format, exported to ONNX with sherpa's `export-onnx.py`, int8
quantised. 160 MB in three files.

**The model is never bundled and never fetched on its own.** The APK is 27 MB.
The download is offered in Settings with its size printed, is resumable and
cancellable, and can be removed. A reader who never turns voice-follow on pays
nothing.

**There is no voice-follow switch.** Downloading the model is the yes and
Remove is the no. A preference on top of two explicit opt-ins is a third thing
to keep consistent with the other two.

**Permission is settled in Settings and nowhere else.** `askForMic` raises the
system prompt through `record`, which is in the build for the microphone stream
anyway, and stores the answer. The prayer screen reads the stored answer and
asks the recorder `hasPermission(request: false)` — it can decline to listen,
never prompt.

**The matcher refuses rather than guesses, and it matches letters, not words.**
It normalises both the muṣḥaf's Uthmani and the recogniser's plain Arabic to the
letters they agree on, and compares the last two dozen letters heard against the
set read as one run of letters, at every word end from the cursor forward to a
handful of words on.

It compared word against word until the owner recited al-Fātiḥa into it and the
prayer advanced once in twenty-three windows. Two things were wrong and both
were assumptions rather than constants. A window ends where the clock says, not
where the reciter draws breath, so its last word is usually a stump — and the
old scoring put its heaviest weight there, which made a window that ended
mid-word arithmetically incapable of clearing the threshold: 0.5047 at best
against a bar of 0.62, however well every other word agreed. And word
boundaries are not a coordinate system the two sides share. Tajwīd reshapes
words and the recogniser cuts them where it hears them, so مَالِكِ comes back as
`فلا ك` and إِيَّاكَ as `يا ك`; one re-cut word misaligned everything after it,
and a window whose last word matched the muṣḥaf exactly still scored 0.54.
Letters are what both sides do share, and an accent, a slip or a reshaped word
arrive as a few letters out of two dozen — a percentage rather than a verdict.

**What a window must clear is how much better it fits here than anywhere else,
not an absolute score.** A fine reciter agrees with the muṣḥaf more closely
everywhere, so a bar set on one shuts out a reader with an accent — whose best
match may score 0.55 where a studio reciter's scores 0.85. What does not depend
on the voice is whether one place fits better than the rest, so the best
agreement must beat the best agreement elsewhere by a margin proportional to
itself. A short window is asked for more besides: a handful of letters finds
agreement almost anywhere in a run of them, so what a window lacks of the full
tail it adds to the bar it must clear. Ties go to the nearer position, because a reciter is more likely at
the first of two places that sound alike. The forward reach is a distance and
not the end of the reading: the count runs straight through repetitions, so a
reciter carrying on into the next reading is one position away and still
followed, while a cursor standing ahead of the reciter — which is where a tap on
the go-on zone leaves it — cannot be dragged a whole reading on by the word
just recited coming round again. A reciter who does run on into the next reading
arrives at its first word, never its seventh: anything further in is the same
phrase found again a reading on, since every word of the set repeats there, and
taking it costs the reader the whole reading they were in. The constants are bounds rather than fits —
see what the measurement below does not establish.

## Measured

Ḥuṣarī reciting Al-ʿAlaq 1-5, the same everyayah files the app plays, cut into
4-second windows every 750 ms and put through the model. Graded against the
per-word timings in `corpus.db`, so "where the reciter actually was" is read off
the recording. The fixture and the grading are
`app/test/features/prayer/voice_follow_test.dart`, which fails the gate if a
change to the matcher lets it advance onto a word the reciter has not reached.

| | whisper-base-ar-quran | whisper-tiny-ar-quran |
| --- | --- | --- |
| Windows | 52 | 52 |
| Advances | 16 | 17 |
| **Wrong advances** | **0** | **1** |
| Stood still | 36 | 35 |
| In step (within a word) | 50 of 52 | 49 of 52 |
| Worst lag | 2 words | 2 words |
| Download, int8 ONNX | 160 MB | 104 MB |

The cursor walked all 20 words and arrived on the last one. It was never ahead
of the reciter. The two lags of two words both closed on the next window.

Base over tiny: 57 MB is a real cost, and one wrong advance in 52 windows is a
worse one. Under the rule that a wrong advance is worse than no advance, the
smaller model does not qualify.

**What this measurement does not establish.** It discriminates against a bad
matcher — one that advances a word per window scores 52 wrong out of 52, and
dropping the threshold, the per-word similarity floor and the context window
together puts 4 wrong advances into 52 — but it does not pin any single
constant. Removing any one guard on its own still measures zero wrong
advances, and the threshold sweeps from 0.10 to 0.80 with no wrong advance at
any setting. One clean recording of one reciter is not enough to tune against;
the constants are conservative bounds, and the honest next measurement is a
phone in a room with a reader who hesitates.

**That measurement was taken, and this section was right to warn.** The owner
recited al-Fātiḥa into his own phone and the prayer advanced once in
twenty-three windows — he read the whole sūra to a screen sitting on word 4 of
29. The table above was perfect at the same moment, on the same code: a matcher
can follow Ḥuṣarī through Al-ʿAlaq without a single error and be useless to the
reader it was built for, and nothing in a studio recording says so. What the
grade measures is a matcher against a reciter, not a matcher.

The fixtures are now five recitations of two sūras — Ḥuṣarī, Alafasy, Abdul
Basit, Minshawy, and the owner in a room — built by `scripts/voice-fixture.py`,
graded in `voice_follow_test.dart` and `voices_test.dart`. The three studio
reciters all pass against the *old* word matcher; only the owner's recording
fails it. A fixture set of professionals would not have caught this and would
not catch the next one of its kind.

Still not established, and the reason the constants stay conservative: one
non-studio voice is one voice. The plateau where all five are followed with no
wrong advance is about one step wide in the margin, which is what thin evidence
looks like. The next measurement is other people's voices — the friends and
family this is being handed to, who are the population the feature is for and
who are, unlike a reciter with an ijāza, the ones it keeps failing.

**Cost per window**, base int8, twenty 4-second windows on an M4 at
`num_threads=2`: median 346 ms, worst 456 ms. At one thread, 504 ms median.

## The engine changed, and why

Whisper answers once per window. That is the whole of it: the longer the
window the better it hears, and the longer the reader waits. Those are not two
knobs, they are one knob turned in opposite directions, and no amount of work
on the matcher moves either.

What that cost, measured on the owner's own phone over 282 windows of a real
prayer: a median of **1576 ms** to decode a six-second window and as much as
**6491 ms**. With the 1.2 s floor between asks, the screen could follow him no
closer than **2.8 s on average and 7.7 s at worst** — and only when a window
also matched. He read two ayas to a screen sitting on word 4.

The accuracy side of the same knob, on his own recitation: a four-second
window tracked 8 of 16 words, six seconds tracked 16 of 16. He needed the long
window to be heard and the short window to be followed, and could have neither.

Two other things about whisper that only show up in a room. It pads every input
to thirty seconds, so a window of speech and twenty-odd seconds of silence is
what it is asked about, and its known failure on that is to repeat itself —
`وما يغيظ`, `والمؤمنين`, over and over, words that are not in al-Fātiḥa at all.
And it re-decodes overlapping audio every hop, so the same seconds are heard
again and can be heard differently.

**A streaming transducer has no window.** Context lives in hidden state, so it
has heard everything and still answers every chunk. Audio goes in once, in the
order it arrived, and the answer grows. Nothing is re-heard, silence adds
nothing, and the cost is a flat **21 ms per 300 ms chunk** on an M-series
laptop at two threads — a realtime factor of **0.07**.

`sherpa-onnx-streaming-zipformer-ar_en_id_ja_ru_th_vi_zh-2025-02-10`, int8,
339 MB against whisper's 160 MB. It is general Arabic rather than Qur'an-tuned
and it spells recitation worse than the fine-tuned whisper did — and it does
not matter, because the matcher was already built to survive bad spelling, and
being told late is the one thing it cannot survive.

### What it measures, on five recitations of two sūras

| | whisper, 6 s windows | streaming transducer |
| --- | --- | --- |
| The owner, his own phone's microphone | 2 advances, stuck on word 4 of 17 | 7 advances, **16 of 16** |
| Ḥuṣarī, Al-ʿAlaq 1-5 | 14 advances, 0 wrong | 19 advances, **0 wrong**, ends 19/19 |
| Alafasy, al-Fātiḥa | — | 16 advances, 0 wrong, 28/28 |
| Abdul Basit, al-Fātiḥa | — | 22 advances, 0 wrong, 28/28 |
| Minshawy, al-Fātiḥa | — | 25 advances, 0 wrong, 28/28 |
| Answer arrives after | 1576 ms median, 6491 ms worst | ~300 ms |

**No wrong advance in any of the five.** The rule that a wrong advance is worse
than no advance is unchanged and still met.

### Tracking, and a search when tracking is lost

Alafasy exposed a hole that the whisper fixtures never could. His opening came
back as `سم`, so the cursor never took its first step — and `followReach`
measures from the cursor, so a reciter who walks past it while the screen
stands on word 0 can never be found again. Sixteen advances became zero.

The reach assumes the screen is roughly where the reciter is. That is true once
following has started and false before it ever does. So after
[`followLostAfter`](../../app/lib/features/prayer/voice_follow.dart) answers
that find nothing, the search widens to the whole set. Widening gives up the
guard that stops a repeated phrase pulling the prayer forward, which is why it
is what happens when tracking has already failed rather than how tracking
works.

## The two assumptions that were false about prayer

Everything above was written on the belief that **the tap is the fallback** —
the phrase appears in this ADR, in `prayer_voice.dart` and in `PrayerCursor`.
It is not. During ṣalāh the phone lies on the floor and the reader cannot move
until the prayer ends. There is no hand coming.

So *"a wrong advance is worse than no advance"* is false as stated: both are
unrecoverable, and the reader lives with whichever they got for the rest of
the prayer. What is true is narrower — **a wrong place is worse than a late
one** — because lateness fixes itself as the reciter carries on.

And **a reciter goes backward on purpose.** Repeating an aya, or a phrase, or
beginning the set again for the next rakʿa, is ordinary prayer. `PrayerCursor`
was *"advance or freeze, never rewind"*, so the app was structurally unable to
follow any of it. `locate` enforced the same thing a second time by never
proposing a place behind the cursor, which is why changing one of them alone
did nothing.

The owner found this by using it: eight builds, and the best of them advanced
twice and stopped on word 4 of 17.

### What replaced them

`alignment.dart`. The search covers **the whole set** — no band measured from
a cursor that may already be stranded — and the cursor takes any place it is
given. What stops a wrong move is no longer a bound on distance but a bound on
**evidence**: one place must fit the last two dozen letters better than every
other place by [`followMargin`], or nothing moves. Refusing costs a window of
lag; the next window is unambiguous and the screen catches up.

Two constants earned their keep unchanged through the rewrite, and one guard
turned out to be doing all the work:

- `heardTailLetters = 24` — and it must stay short, see below.
- `followThreshold = 0.44` — the floor under a voice.
- `followMargin = 0.32` — **the whole of the safety.** It is what tells the two
  copies of a repeated phrase apart, by refusing both. It also catches phrases
  that merely resemble each other: Al-ʿAlaq says ٱلَّذِى خَلَقَ and ٱلَّذِى عَلَّمَ,
  seven letters differing in two, scoring 0.71 against one another, and a
  window holding one of them cannot honestly say which.

### The design this rejected, so it is not proposed again

Aligning a **long** window of the transcript against the set — a Sellers DP,
on the reasoning that more context distinguishes two copies of a phrase. It
does. It cannot be had, and a doubt-driven pass established that by building
it and running it on this repo's own fixtures:

- **A linear alignment cannot represent a repeat.** The set's letters are spent
  once, so a repeated phrase aligns *forward* through the text just repeated.
  Measured: repeating al-Fātiḥa's third aya moved the reader 9 → 11 → 13, into
  the two ayas after it — the exact failure this feature exists to avoid.
- **The transcript never resets** (one stream per screen, `enableEndpoint:
  false`). A window longer than the set is minimised by matching the longest
  span, which pins the answer to the last word — measured at word 16 of 17 for
  the whole of a second rakʿa.

Long context and following a repeat are in direct tension. The repeat wins.

### The opening of a prayer comes back wrong, and it costs nothing

A streaming transducer starts with no left context — this one is built for 128
frames of it — and a multilingual one has also to settle on a language. So the
first second or two of a prayer decodes badly: the owner's own بِسْمِ ٱللَّهِ
arrives as `هي`.

Three fixes were tried against his recorded prayer and all three are worse:

| | first words | at 26 s |
| --- | --- | --- |
| greedy, as shipped | `هي` | tracks correctly |
| 500 ms of silence first | `OR` | never recovers |
| 1 s of silence first | `A` | `A EMOTION الحمد لله…` |
| `modified_beam_search` | `Э` | tracks, 29% slower |
| beam + the set as hotwords, score 5 | `Э` | emits ٱلرَّحْمَٰنِ ٱلرَّحِيمِ **three times** |

The last is the worst of them: contextual biasing on a set we know exactly
sounds like the obvious win, and what it actually does is invent a repetition
the reciter never made — which is precisely the input this matcher is least
able to survive.

**It costs nothing, and the reason is worth stating.** The screen starts on
word 0, which is where the reciter starts, so there is nowhere to be carried
from; and the margin refuses the nonsense rather than acting on it. Traced on
his prayer: the cursor sits on word 0 for 6.3 s while he recites the basmala,
then moves to word 5 and tracks. Late, never wrong.

### Why not an Arabic model, or a Qur'an one

There is no Arabic-only **streaming** model in sherpa-onnx's ecosystem;
searched four ways, the multilingual zipformer is the only one. The
Qur'an-specific models that exist — `wav2vec2-base-word-by-word-quran-asr`,
`whisper-small-quran-asr` and others — are all **non-streaming**, which is the
architecture measured at 1576 ms median on the owner's phone and rejected
above. A Qur'an-tuned streaming model would have to be fine-tuned from this
zipformer on Qur'an audio: a project, not a configuration, and worth doing
only if the general-Arabic spelling turns out to cost a reader something the
margin cannot absorb.

## Battery and heat

A prayer runs for many minutes and continuous inference is real. Two bounds are
in the code rather than in an estimate:

- Inference runs on an isolate of its own, so it cannot freeze the screen. The
  tap is the fallback for every window the matcher is unsure about, and a
  frozen screen would take the fallback away.
- The hop is not a fixed number. It waits at least `heardHop` (1.2 s) and at
  least as long again as the last window actually took, so the recogniser is
  busy less than half the time on any phone, however slow it turns out to be.
  A phone that spends a second on a window is asked half as often rather than
  run flat out.

This is a ceiling, not a measurement: nothing here has run on a phone yet. What
is measured is the desktop cost above and the shape of the bound.

## Alternatives considered

| Option | Why rejected |
| --- | --- |
| Vosk, Arabic | The small model is 158 MB of Tunisian dialect; MSA is 318 MB at 16.4% WER on broadcast news. Bigger and wrong-domain: Qur'anic recitation is classical, fully vowelled, and carries tajwīd — madd, ghunna, idghām — which is not acoustically MSA. |
| Generic Whisper (`openai/whisper-base`, multilingual) | Same size, no Qur'anic fine-tune, and the fine-tune is free — `everyayah` is the corpus we already fetch from. |
| `whisper-tiny-ar-quran` | Measured above. One wrong advance in 52 windows. |
| **parakeet-rs / NVIDIA Nemotron 3.5 ASR** | Arabic **is** supported — `ar-AR` is in the transcription-ready tier at 12.03% WER, which corrects the common claim that Parakeet is 25 European languages only (that is `parakeet-tdt-v3`; the Arabic is in Nemotron 3.5). It is still the wrong tool here: 600M parameters against whisper-base's 74M, a Rust crate that a Flutter app reaches only through `flutter_rust_bridge` and a cross-compile for four ABIs, generic multilingual MSA rather than vowelled classical recitation, and sherpa-onnx does not support its `prompt_index` input yet (k2-fsa/sherpa-onnx#3664). Revisit if it ever ships Qur'anic fine-tunes at base size. |
| Platform recognisers (`SFSpeechRecognizer`, Android `SpeechRecognizer`) | Two engines to tune, neither offline-guaranteed for Arabic, and Android's routes audio through Google servers on most devices — which is contract 3 broken by the platform. |
| Cloud streaming ASR | Streams worship off the device, and needs signal in a room that usually has none. |
| Forced alignment against the reference recitation | Aligns the reciter to Ḥuṣarī's tempo, not to their own. A reader who pauses to think is lost immediately. |

## The export, because the weights do not drop in

Recorded here because two steps are not obvious and one of them fails silently:

1. `tarteel-ai/whisper-base-ar-quran` is a HuggingFace checkpoint.
   `sherpa-onnx/scripts/whisper/export-onnx.py` wants openai-whisper format. The
   state dict converts with a flat name mapping — `model.` stripped,
   `encoder.layers` to `encoder.blocks`, `self_attn.q_proj` to `attn.query`, and
   so on — and loads with zero missing and zero unexpected keys.
2. **The export must use the legacy exporter.** torch 2.14's default dynamo
   export produces a graph sherpa-onnx 1.13.8 loads and then fails on, with
   `Reshape node 'node_view': input shape {1,4,512}, requested shape {512}`
   swallowed into an empty result — the recogniser returns `''` for every
   window rather than erroring. Passing `dynamo=False` to `torch.onnx.export`
   fixes it. Verified by decoding 96:1 to `اقْرَأْ بِاسْمِ رَبِّكَ الَّذِي خَلَقَ`.
3. int8 on `MatMul` only. Adding `Gather` to quantise the token embedding makes
   the decoder *larger* (157 MB against 131 MB), not smaller.

The exported files are not yet hosted. `defaultVoiceModelOrigin` is a bundled
default the server can override, the way `defaultAudioOrigin` is, so the model
can move host without a release.

## Consequences

- Two dependencies: `sherpa_onnx` and `record`. `permission_handler` was not
  added — `record.hasPermission()` raises the same system prompt and `record`
  is in the build regardless.
- Publishing the exported model, and a script in `scripts/` that reproduces the
  export, are release-pipeline work this ADR does not do.
- iOS needs `NSMicrophoneUsageDescription` in `Info.plist` or the app
  terminates when it asks. It is not there yet.
- None of the on-device path has run on a phone. The matcher is measured; the
  engine is verified on a desktop through the same runtime the plugin wraps;
  the plugin glue between them is typed and unrun.

## Reversibility

Two-way, and cheaply. The matcher takes a string and knows nothing about where
it came from; `Recogniser` is thirty lines behind an isolate. Swapping the
engine or the model changes `speech.dart` and the ADR, and leaves
`voice_follow.dart`, its fixture and its measurement standing — they grade
whatever hypotheses are handed to them.
