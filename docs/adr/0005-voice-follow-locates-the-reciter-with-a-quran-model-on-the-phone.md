# 5. Voice-follow locates the reciter with a Qur'an model on the phone

Date: 2026-09-24. Status: accepted.

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

**The matcher refuses rather than guesses.** It normalises both the muṣḥaf's
Uthmani and the recogniser's plain Arabic to the letters they agree on, scores
the last four heard words against every position from the cursor forward to one
reading on, weights the most recent word heaviest, and moves only above a
measured threshold. Ties go to the nearer position, because a reciter is more
likely at the first of two places that sound alike.

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

**Cost per window**, base int8, twenty 4-second windows on an M4 at
`num_threads=2`: median 346 ms, worst 456 ms. At one thread, 504 ms median.

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
