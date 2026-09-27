# Voice-follow, walked on the owner's phone

What a reader found by praying with the app, on the device, with the trail
pulled off it afterwards. One entry per finding: what was seen, the trail that
shows it, where it comes from in the code, and what would fix it. Nothing here
is fixed yet — these are collected so they can be fixed in one pass.

The phone is a 23117RA68G on Android 16, running the debug build. The trail is
`/data/data/dev.bnei.wird/databases/prayer-trail.log`, read with
`adb shell run-as dev.bnei.wird cat`.

Walking it, from the repo root:

```sh
# Release APK for the walk. The flag drops the per-ABI version-code offset, so
# this APK carries versionCode 1 and a later `flutter run` installs over it
# instead of uninstalling and taking the 72.7 MB of weights with it (finding 4).
cd app && fvm flutter build apk --release --split-per-abi \
  -P force-version-code-ignoring-abi=true

# Check what the APK actually claims, before handing it to the phone.
# aapt2 lives in the SDK: $(sed -n 's/^sdk.dir=//p' android/local.properties)/build-tools/<ver>/
aapt2 dump badging build/app/outputs/flutter-apk/app-arm64-v8a-release.apk \
  | grep versionCode        # expect 1, not 2001

# -d once: the phone still carries the 2001 of an earlier split build, so
# even a versionCode-1 APK goes on as a downgrade the first time.
adb install -r -d build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
fvm flutter run -d qse6wk6h7pmza6kr          # nothing should be uninstalled
adb shell run-as dev.bnei.wird cat \
  /data/data/dev.bnei.wird/databases/prayer-trail.log > trail.log
```

Development only: the Play Store requires a distinct version code per split
APK, which is why the offsets exist. See the comment in
`app/android/app/build.gradle.kts`.

## 2026-09-27, first walk on Quran-Lab/zipformer_p-arabic-v3

The recogniser itself is doing its job. Both findings are about what surrounds
it: what audio reaches it, and when it starts. ADR 0009 is not in question.

### 1. A bystander keeps the recogniser fed after the reader has stopped

Reported from a room with people speaking English a metre away: the recitation
is followed, and then words keep arriving after the reader has finished.

```
35.4s  heard  ااوَلحَمدُلِللَااهِرَببِلعَاالَمِۦۦن | MOVE to word 7 at 0.78 | on 9 | peak 0.03
38.2s  utterance ended  (nothing)
42.1s  heard  ... صَد | stay: word 7 at 0.60 ... | peak 0.04
42.6s  heard  ... صَدۥۥنحَااذَ | MOVE to word 8 at 0.58 | on 7 | peak 0.05
```

It is not cosmetic. At 42.6s the cursor moved to word 8 on a phrase nobody
praying had said.

The level gate is `prayer_voice.dart`:

```dart
if (peak < heardQuiet && !_speaking) continue;
```

`_speaking` is latched true at the reader's first syllable and is never set
false again, so from that moment every 300 ms batch reaches the recogniser
whatever its level. The gate guards only the quiet before the prayer begins.
A phoneme alphabet cannot write English, so a bystander is not refused — it is
transcribed as the nearest Arabic and handed to the matcher.

The levels separate cleanly, from that same trail: the reader's own words peak
0.10 to 0.17, the room a metre away peaks 0.03 to 0.05, and `heardQuiet` is a
fixed 0.02. One constant cannot tell them apart; a ratio against the reader's
own loudness can, with room to spare.

Two fixes, quietest first:

- Re-arm the gate when an utterance ends, so `said.ended` puts the batch level
  back in charge instead of leaving it latched open for the rest of the prayer.
  One line.
- Gate on the reciter's own level rather than a constant: keep a decaying peak
  of the loudest speaker over the last several seconds and pass a batch only
  within some ratio of it, so the floor rises in a loud room and falls in a
  quiet one.

Written down at `heardQuiet` in `lib/data/speech.dart`.

### 2. The microphone does not open until the model has loaded

Reported as lag at the start of a prayer, with the reader's guess that the
model's load time is not accounted for. The trail agrees.

```
0.0s  trail  2026-09-27T09:51:06.352356
0.0s  set  17 words, 5 ayas
4.5s  voice  the reader began, at 0.11
5.2s  heard  ظَااهِ | too little heard | on 0 | peak 0.04
...
18.1s  heard  ...  | MOVE to word 7 at 0.75 | on 0 | peak 0.02
```

Four and a half seconds pass before any audio is handed over, the first answer
is a fragment of a word the reader was already halfway through, and the cursor
sits on word 0 until 18.1s — at which point it jumps to word 7, because the
opening was never heard and the first thing the matcher could place was the
seventh word.

`PrayerVoice.start` opens the recogniser first and the microphone second:
`Recogniser.open` spawns the isolate and waits for a 72.7 MB int8 model to load
inside it (its own timeout is 20 s), and only when that returns is
`AudioRecorder()` constructed and `_listen()` called. `_waiting`'s promise that
nothing is dropped begins when the stream does. Everything recited before that
is not buffered, not late — it was never captured.

The fix is an ordering one: start the microphone first and let `_waiting`
collect while the model loads, then open the recogniser and hand it what has
piled up. The failure paths need care — the existing handler closes whichever
of the two it opened — but nothing else about the class changes.

### 3. The trail could not say how long the load took

Finding 2 was visible only as a 4.5 s hole with nothing in it, and that hole
also contains the reader walking to the mat. The trail had no line between
opening the prayer and the first sound.

Two lines were added for this, and are on the phone now: `recogniser  loaded,
Nms after the prayer opened` and `microphone  listening, Nms after the prayer
opened`. They record, they change no behaviour, and they are what makes the
next walk's numbers readable.

### 4. A debug install evicts the model

Installing the debug build over the release build fails and forces an
uninstall:

```
INSTALL_FAILED_VERSION_DOWNGRADE: Downgrade detected: Update version code 1 is older than current 2001
```

`flutter run` handles it by uninstalling, which takes the app's data with it —
so every walk that follows a release build starts by downloading 72.7 MB of
weights again over whatever connection the reader has.

**Corrected: 2001 is not an outside number and no versionCode needs setting.**
`--split-per-abi` makes Flutter's own Gradle plugin mint
`abi * 1000 + pubspec build number` per APK — arm64 is 2, the pubspec is
1.0.0+1, so 2001 — because Play refuses two split APKs with the same code.
Overriding it in `build.gradle.kts` would not work: the plugin's override runs
in `afterEvaluate` through the legacy `applicationVariants` API, after
`androidComponents.onVariants`, so a block written there is clobbered on the
split build. The fix is the build flag above,
`-P force-version-code-ignoring-abi=true`, which skips the ABI offset and keeps
the split. Release then carries versionCode 1, the same as debug, and equal
codes install over each other. It is a development flag: releasing to Play
means dropping it and bumping the pubspec build number past the last release's
offset code, or `adb install -d`.

### 5. Iʿrāb, lexicon and tafsir are placeholders end to end

Reported from the deep dive: no iʿrāb, no lexicon, no tafsir. That is what the
build does today, and the reader is told so rather than shown an empty box —
`_irabPending`, `_lexiconPending` and `_tafsirPending` in
`app/lib/features/root/root_sections.dart` each say the section is fetched per
aya and nothing has been fetched.

How far the three actually exist:

- The API has all three routes: `GET /v1/ayahs/{surah}/{ayah}/tafsir`,
  `.../irab`, and `GET /v1/roots/{letters}/lexicon`, with `Store.Tafsir`,
  `Store.Irab` and `Store.Lexicon` behind them.
- The tables exist, from `server/migrations/00002_content.sql`.
- **The app never calls any of them.** There is no client for these three
  routes anywhere in `app/lib`; the phone does not ask, so the placeholders are
  not a failed fetch, they are the absence of one.
- **The tables hold only the design's mockup rows, every one flagged
  `is_placeholder = true`**: two lexicon lines under صبر, one tafsir row and one
  iʿrāb row, both on ayah 103003. `server/cmd/ingest` never writes these three
  tables — the only `INSERT`s are in that migration.

So this is not one missing fetch, it is three unbuilt features with their
plumbing already laid. Wiring the app to the API today would replace three
honest notices with placeholder rows for صبر and al-ʿAṣr 3 and nothing at all
elsewhere, which is worse.

What each needs before it can be built, and the order they are worth doing in:

- **Iʿrāb** has a source already in the repo. `data/SOURCES.md` records
  `quranic-corpus-morphology-0.4.txt`, the Quranic Arabic Corpus's own
  syntactic and morphological annotation, put there by hand. Whether it carries
  enough to write a per-aya parsing needs checking, but this is the one of the
  three whose data may already be on disk and whose licence is already
  understood.
- **Lexicon** has no source chosen. `_lexiconPending` says as much: neither the
  fetch nor the choice of lexicon is settled. The mockup names Ibn Fāris's
  *Maqāyīs al-Lugha* and Lane; both are the kind of decision ADR 0009's licence
  section is about, and neither is settled here.
- **Tafsir** is the largest and the least settled. `tafsirSources` names
  Al-Ṭabarī, Ibn Kathīr and Al-Rāzī, and the comment above it is careful that
  naming them is not a claim about what they say. Nothing is licensed, nothing
  is ingested, and a tafsir shown beside someone's recitation is the place
  where being wrong costs the most.

### 6. A kept aya cannot be un-kept from where it was kept

Reported from the deep dive's footer: pressing **Keep this aya** turns the
button into **Kept**, and there is no way back from that screen.

What "Kept" means: a row in `kept_items` with `kind = 'aya'`, minted with a
local id so it survives a flight and deduplicates on sync, queued to the outbox,
and listed on the Kept screen under its Ayas filter. The `revisit` tag is the
design's separate "come back to this" flag, and this button does not set it.

Un-keeping does exist — `forget` in `app/lib/data/kept_repo.dart`, a soft delete
that writes `deleted_at` and queues a `kept_delete` — but it has exactly one
caller: `onDismissed` on the `Dismissible` in `kept_screen.dart`. So the only
way to undo is to leave the aya, open Kept, find the card, and swipe it, and the
screen deliberately draws no chrome for that swipe, so nothing anywhere tells
the reader it is possible.

The deep dive's button is one-way on purpose — `onPressed: _kept ? null : _keep`
disables it once kept — and that is the whole of the problem: a disabled button
reads as "this is done and cannot be changed" when the truth is "this can be
undone, elsewhere, by a gesture you have not been shown".

The fix is a decision, not a patch, so it is left here: either the button
becomes a toggle that calls `forget` (the kept row's id is already read at load
by `ayaKept`, so it is at hand), or it stays one-way and says where to undo.
Whichever, the Kept screen's swipe needs some affordance — it is the only
delete in the app and today it is invisible.

### 7. The recitation's play button is at the end of the scroll

Reported from the reading screen: the play/pause and the line that names the
reciter sit at the end of the scroll, and all actions should be in the footer.

`_audioBar` is built inside the scrolling sliver, as the item after the last aya
of the acted set (`study_screen.dart`, the `i == set.ayas.length` branch). It
holds the only play/pause, the waveform, and the line that reads the reciter's
name or `Not downloaded`. So starting a recitation, and learning whether the
audio is even on the phone, both require scrolling past the whole set.

The footer under it is pinned and already holds two things: `SoundingNow`, which
names what is sounding and offers the stop, and `ReadingNav`. `SoundingNow`'s own
comment is about exactly this failure — a bar that scrolled away with the words,
leaving a reader with nothing to press — and it fixed the *stopping* half by
moving into the shell. The starting half stayed in the scroll.

So the footer is the right home and the precedent is already there. What has to
be decided when this is done: `SoundingNow` draws nothing when nothing is
sounding, deliberately, so that no reader who never plays anything pays for a
band of empty chrome — a play button in the footer is visible always, which is
the opposite trade. The reciter's name and `Not downloaded` also need a home;
that line is arguably Settings' business rather than the reading screen's.

### 8. The word panel names the root but never says what the root means

Reported from the reading screen's panel: selecting a word shows the root, and
then the only prose under it is the meaning of *that word in that aya*, not the
meaning of the root.

That is exactly what it does, and it is labelled honestly — the section heading
is `IN THIS AYA` and the body is `word?.gloss` (`study_chrome.dart`). The root
line above it carries the radicals, the transliteration and an occurrence count,
and nothing else.

What makes this a finding rather than a design choice is that **the panel
already holds the root's sense and drops it on the floor.** `RootDetail` is
`RootReading`, and it arrives with `coreSense`, `senseSource`, `senseBasis` and
`senseEvidence` already read — 523 of 1,642 roots carry a sense. The widget that
draws it, `CoreSense`, exists and is used by all three other views of a root:
the root screen, the spine, and the deep dive. The panel is the only one of the
four that does not ask for it.

The comment above that section explains why, and the explanation has gone stale:

```
// The design's "core sense" prose is lexicon text, which arrives
// over the network in a later phase. What the corpus itself knows
// about this word is its gloss in this aya, so that is what the
// section says it is.
```

That was true when a root's sense was going to be a lexicon quotation fetched
from a server. It is not true now: Wird writes its own sense from the root's own
words in the Qur'an, ships it in `data/root_senses.json`, and attributes it with
`senseSource`. The panel is still waiting for a fetch the rest of the app
stopped waiting for.

The fix is to add `CoreSense` to the panel, above `IN THIS AYA`, and keep both —
the root's sense and the word's gloss in this aya answer two different questions
and the reader asked for the first. `CoreSense` already handles the two roots in
three that carry no sense, with `_senseRefused` saying so rather than leaving a
gap. What has to be decided is height: the panel is the narrowest of the four
views and this adds a paragraph to a screen that also holds the reading, the
footer and the transport.
