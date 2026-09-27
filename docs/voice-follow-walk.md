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

## 2026-09-27, walk two — on the Mac, with Part 1 merged

Same reader, `fvm flutter run -d macos` against the merged branch. The trail is at
`app/test/fixtures/fatiha_macos_trail.txt`, committed because it is the first
recording of this failure and every number below is measured off it.

### What the first walk's findings look like now

Findings 1 and 2 are closed, and the trail says so in its first four lines:

```
0.3s  microphone  listening, 250ms after the prayer opened
1.0s  recogniser  loaded, 994ms after the prayer opened
1.0s  still here  1 batches of room, peak 0.010 to 0.010
2.6s  heard  بِسمِللَ | MOVE to word 0 at 0.75
```

The microphone now opens before the model rather than 4.5 s after it, and the
opening of the recitation is matched at 2.6 s instead of the cursor sitting on
word 0 until 18.1 s and then jumping to word 7. The carry clears on a silent
endpoint: at 39.1 s `utterance ended (nothing)`, and the next window at 41.0 s is
`ل` alone rather than the previous aya with a fragment glued to it.

One measurement worth keeping, because it settles an argument the first walk
started: `MOVE to word 7 at 0.81` arrives at **peak 0.01**, half the `heardQuiet`
floor of 0.02. Genuine recitation is quieter than the gate. Re-arming the level
gate at each endpoint — which the first walk's write-up proposed — would have
thrown that word away.

### 9. The margin rule pins the cursor on any set that says a phrase twice

Reported as the screen not following, and the reader repeating al-Fātiḥa's second
aya three times to make it move. The trail shows the cursor on **word 1 from 3.6 s
to 36 s** while the whole basmala and the opening of al-Ḥamd are recited
correctly.

The cause is not the microphone and not the recogniser. al-Fātiḥa says
ٱلرَّحْمَـٰنِ ٱلرَّحِيمِ twice inside one seventeen-word set:

```
set index 2,3   ٱلرَّحْمَـٰنِ ٱلرَّحِيمِ   inside the basmala, aya 1
set index 8,9   ٱلرَّحْمَـٰنِ ٱلرَّحِيمِ   on its own, aya 3
```

`locate` (`alignment.dart:124-130`) refuses when `score - rival < followMargin`,
with `followMargin = 0.32`, and `rival` counts any candidate two or more words
from the best — six words apart qualifies. So every window the basmala produces
names two places and is refused. Run the trail's own 48 windows back through
`explain` against the real set:

```
windows 48 | moved 12 | refused by MARGIN 27 | refused by the bar 7 | too short 2

refused margins   min 0.000   median 0.158   max 0.313   against followMargin 0.32
sweep             0.10 releases 19 of 27      0.20 releases 12 of 27
                  0.15 releases 14 of 27      0.25 releases  7 of 27
```

**A lower threshold cannot be the whole answer.** Three of the 27 sit at margin
exactly 0.000 — the two places fit equally well and refusing both is correct.
`alignment.dart` calls the margin "the guard that does the real work: it is what
tells the two copies of a repeated phrase apart, by refusing both", and that
reasoning still holds. What is wrong is applying it to the whole set when only one
span of the set is ambiguous.

**It is not al-Fātiḥa-specific.** Folding every sūra of sixty words or fewer — the
size a prayer set actually is — and looking for a two-word phrase repeated at
least two words away:

```
short suras                                            22
carrying such a repeat                                 11   half of them
sura 109 al-Kāfirūn   4 repeats      sura 99  az-Zalzalah  3
sura 101 al-Qāriʿah   3 repeats      sura 1   al-Fātiḥa    1  (words 2 and 8)
```

al-Kāfirūn is built on repetition and is worse than al-Fātiḥa. These are the
sūras most recited in prayer, so this is the common case rather than an edge.

**The owner's direction, recorded as the direction and not yet designed:** a
dedicated algorithm per chosen set, rather than one global constant. The set's
repeat structure is knowable before a word is said, and `Recitation` is already
built once per prayer for exactly this kind of reason — its own comment says
rebuilding per window turns a cheap search into a slow one. So a set can know
which of its spans are ambiguous, and the margin can be demanded only there
instead of everywhere. What it must not break: the graded fixtures, above all
`voice_follow_test.dart`'s assertion that the cursor is never ahead of the
reciter, which is the number that decides whether this may be on by default.

### 10. رحم ships a sense that leaves out the womb

Reported by the reader from the root panel: *"on the root r h m, I read somewhere
that it means matrice, uterus"*. Correct, and the corpus bears it out. The shipped
sense is `to be merciful; to show mercy` / `être miséricordieux ; faire
miséricorde`, and it says nothing of eleven occurrences:

```
2:228 أَرْحَامِهِنَّ their wombs   3:6 ٱلْأَرْحَامِ the wombs   4:1 وَٱلْأَرْحَامَ and the wombs
6:143, 6:144 أَرْحَامُ (the) wombs        8:75 ٱلْأَرْحَامِ (of) blood relationship
13:8 ٱلْأَرْحَامُ the womb   22:5, 31:34 ٱلْأَرْحَامِ the wombs
33:6 ٱلْأَرْحَامِ (of) relationships      47:22 أَرْحَامَكُمْ your ties of kinship
```

4:1 puts ٱلْأَرْحَامَ beside ٱللَّه in a single oath, and the womb is the concrete
sense the moral one is derived from, so this is not a minor branch.

`docs/root-meanings-research.md:148-152` already records رحم as one of the two
closest calls — but for a **different** unnamed branch, *gracious* (Ar-Raḥmān, 34
occurrences). Nobody had recorded the womb branch, and a reader found it in one
sitting. Eleven of roughly 340 occurrences is under the branch ceiling, so the
gate passed the sense; رحم clears that term at 0.168 against a 0.204 ceiling. The
question this raises is about the ceiling, not only this row, and it belongs with
the calibration work rather than here.

### 11. Tafsir's notice reads as a bug rather than a refusal

Reported as "Tafsir is not present". That is the intended behaviour — nothing is
licensed, nothing is ingested, and `_tafsirPending` says the section is fetched
per aya and nothing has been fetched. But the reader read it as something broken,
which means the wording fails at the one job it has. The notice exists to make a
refusal visible; if it reads as an absence, it is not doing that. Worth rewording
rather than rebuilding.

## What happened to the eight, as of the merge

Part 1 of the plan is merged (`voice-follow-walk`, four lanes, all gates green:
`flutter analyze` clean, 386 Dart tests, `go build`/`vet`/`test` clean,
`scripts/qa.sh` 21 passed / 0 failed / 3 skipped). Per finding:

1. **Closed, and not the way this doc proposed.** The fix is one line — `_carried`
   clears when an utterance ends with nothing decoded. The second half this doc
   asked for, re-arming the level gate at each endpoint, was **rejected with
   reasons**: a gated batch never reaches `acceptWaveform`, so re-arming removes
   the only thing that makes an empty endpoint fire and cancels the fix; and
   sherpa's rule 3 ends an utterance at 20 s of speech, so re-arming discards
   genuine recitation mid-aya. Walk two's trail confirms both halves of that — a
   `MOVE` lands at peak 0.01, half the floor.
2. **Closed.** The microphone opens before the model: 250 ms rather than 4.5 s.
   `Recogniser.open`'s `return null` became a throw, or a truncated model left a
   live microphone and an unbounded `List<double>` for the whole prayer. The
   catch-up is drained in `heardChunk` slices from a single snapshot, so the
   backlog stays self-limiting; `stop()` is total and idempotent; and a
   `listening` callback closes the window where a reader leaves the screen while
   the model is still loading.
3. **Closed by being the thing that measured 1 and 2.** The two trail lines are
   committed and are what the numbers above are read off.
4. **Closed, and this doc's own proposal was wrong.** 2001 is not an outside
   number: `--split-per-abi` makes Flutter's plugin mint `abi * 1000 + build
   number`. No `versionCode` is set anywhere; the fix is
   `-P force-version-code-ignoring-abi=true` on a walk build, plus the comment
   that says so. A Gradle override would have been clobbered in `afterEvaluate`.
   The pre-existing claim that the split "keeps a 32-bit phone buildable" was also
   false and is corrected.
5. **Half built, half deliberately not.** Iʿrāb is real, from
   `words.morphology` which was already in the bundle: an `irab` table plus a
   142-row `irab_roles` lookup, English and French, with the provenance line drawn
   inside `IrabSection` so all three mounts carry it. The lexicon section is
   deleted — `CoreSense` answers what it stood in for, and `docs/lane-lexicon.md`
   had already ruled Lane out. **Tafsir keeps its notice**, and walk two's finding
   11 says that notice's wording is failing.
6. **Closed, and there were three Keep controls rather than two.** The third was
   `RootChrome`'s bookmark, which would have stayed latched beside a working
   toggle. All three now toggle, `_busy` restores the in-flight guard that
   `_kept ? null : _keep` was silently providing, and `keepAya`/`forgetAya` match
   the root path's dedupe. Chrome for the Kept screen's swipe stays out of scope
   by the owner's call.
7. **Closed.** Play/pause is in the pinned footer. `Not downloaded` stayed with
   the button it disables — moving it to Settings with the reciter's name would
   have left a dead control with nothing saying why. `lastBeforeBar` was kept: it
   is the only mark of where the recited span ends, which matters more once the
   button no longer sits at that boundary.
8. **Closed.** `CoreSense` is in the word panel, unguarded, so the refusal notice
   appears there as it does in the other three views. It needed
   `import '../root/root_sections.dart' show CoreSense` — `DashedRule` is declared
   in both files and a plain import does not compile. The panel's body scrolls
   with `Mark set understood` pinned outside it, because the first attempt at the
   landscape problem put the screen's only way forward inside the scroll.
