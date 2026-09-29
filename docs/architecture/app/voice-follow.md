# Voice-follow

> The on-device recogniser that listens while you recite and lights the aya you are on, with the tap always there as the fallback. Level L2 · Parent [App](../app.md) · Children none

## Black box

Voice-follow moves the prayer screen for you. You turn it on in Settings: you grant the microphone once and download a 73 MB model once. From then on, the prayer screen listens while you recite your set and lights the aya you have reached. Your voice never leaves the phone. If anything is missing or goes wrong, the screen simply waits for your tap, as it always did.

| In | Out | Depends on |
|---|---|---|
| Your recitation, through the microphone | The aya (and, when sure, the word) you are on | Microphone permission, granted in Settings |
| The words of the set you are praying | A short echo of the words that moved the screen | The model files, fetched once from `wird.bnei.dev/models/` |
| Your taps on the prayer screen | A per-prayer log file on the phone, for reading afterwards | Nothing on the network during a prayer |

```mermaid
sequenceDiagram
  actor R as Reader
  participant S as Settings
  participant H as wird.bnei.dev/models/
  participant O as Object store
  participant P as Prayer screen
  R->>S: Turn on voice-follow
  S->>R: System microphone prompt
  R-->>S: Allow
  R->>S: Download, 73 MB
  S->>H: GET each model file
  H-->>S: 302 to a short-lived signed URL
  S->>O: GET, resumable
  O-->>S: Bytes
  Note over S: Model kept on the phone
  R->>P: Start the prayer
  loop While reciting
    R->>P: Recitation, heard on the phone only
    P-->>R: The aya you are on lights up
  end
  R->>P: Tap, when the screen is wrong
  P-->>R: Next or previous aya, at once
```

What you can count on, seen from outside:

```mermaid
flowchart LR
  heard["Recitation heard"] --> sure{"One place in the set<br/>clearly fits?"}
  sure -->|yes| move["Screen moves there"]
  sure -->|no| wait["Screen stays put<br/>late rather than wrong"]
  wait --> tap["Your tap still works"]
  missing["No permission,<br/>no model, no mic"] --> tap
```

- **Nothing appears in front of someone praying.** No dialog, no spinner, no error. A failure is silence.
- **A wrong place is worse than a late one.** The phone is on the floor during the prayer, so a wrong jump cannot be fixed by hand until the prayer ends. Voice-follow waits rather than guesses.
- **It follows you backwards too.** Repeating an aya, or starting the set again for the next rakʿa, is ordinary prayer.

## White box

```mermaid
flowchart TB
  subgraph settings["Settings, before any prayer"]
    ask["askForMic<br/>mic.dart"] --> consent[("mic_consent row")]
    fetch["VoiceModel.fetch<br/>speech.dart"] --> sweep["sweepUpAfterAnOlderModel"]
    sweep --> files[("voice/ beside wird.db<br/>model.int8.onnx + tokens.txt")]
  end
  subgraph prayer["Prayer screen"]
    start["PrayerVoice.start<br/>prayer_voice.dart"] --> micopen["Microphone stream<br/>16 kHz PCM"]
    micopen --> waiting["_waiting buffer"]
    waiting --> drain["_handOver<br/>300 ms slices + level gate"]
    drain --> iso["Recogniser isolate<br/>sherpa_onnx phoneme CTC"]
    iso --> carry["carry<br/>previous utterance + current"]
    carry --> locate["locate / explain<br/>alignment.dart"]
    locate --> cursor["PrayerCursor.moveTo"]
    cursor --> screen["PrayerScreen._onTheMove<br/>dwell, then turn the aya"]
    tap["Tap next / back"] --> cursor
    tap --> hold["PrayerVoice.hold<br/>4 s of the reader's hand"]
    drain -.-> trail[("prayer-trail.log")]
    locate -.-> trail
  end
  consent --> start
  files --> start
  files --> iso
```

### 1. The microphone is asked for in Settings, never in a prayer

The answer is stored in the database, so the prayer screen only reads it. A device with no microphone is recorded as `unavailable`, which is different from a refusal.

```dart
Future<MicPermission> askForMic(
  Database db, {
  Future<bool> Function()? ask,
}) async {
  MicPermission answer;
  try {
    answer = await (ask ?? _prompt)()
        ? MicPermission.granted
        : MicPermission.denied;
  } on Object {
    answer = MicPermission.unavailable;
  }
  await setMicPermission(db, answer);
  return answer;
}
```

[mic.dart:41](../../../app/lib/data/mic.dart#L41-L55)

### 2. The model is downloaded on request, and resumes

Two files make the model: `model.int8.onnx` and `tokens.txt`, 72.7 MB together ([speech.dart:40](../../../app/lib/data/speech.dart#L40-L44)). The app holds a path on Wird's own host, never a signed URL, so a download resumed a week later simply asks again ([speech.dart:64](../../../app/lib/data/speech.dart#L64-L65)). The last path segment is a digest of the files, so new weights never land on a key a half-finished download is resuming against.

On the server, `/models/` needs no sign-in. It mints a signed URL to the object store and answers 302, so the bytes never pass through the API ([models.go:70](../../../server/internal/api/models.go#L70-L79)).

A stopped download keeps its `.part` file. The resume sends a `Range` header, and an `If-Range` with the stored ETag, so a swapped file restarts instead of being spliced onto the old half:

```dart
            headers: {
              // A server that ignores the range answers 200 and the whole
              // file, which would be appended to what is already there and
              // corrupt it.
              if (from > 0) 'range': 'bytes=$from-',
              // And one that honours it will happily continue a DIFFERENT
              // object under the same name. `If-Range` makes the store answer
              // 200 with the whole file instead of 206, so a swapped part
              // restarts rather than splicing two halves that do not belong
              // together. Length alone cannot see that.
              if (from > 0 && heldTag.isNotEmpty) 'if-range': heldTag,
            },
```

[speech.dart:249](../../../app/lib/data/speech.dart#L249-L260)

A failed fetch is reported to Settings as one of two things: `notServed` (the host answered, but not with the file) or `interrupted` (the bytes stopped) ([speech.dart:172](../../../app/lib/data/speech.dart#L172-L181)). Settings starts the fetch from its model panel ([settings_screen.dart:523](../../../app/lib/features/settings/settings_screen.dart#L523-L528)).

### 3. Old models are swept away

Every fetch first deletes any file in the `voice/` directory that this build does not use. Without it, a phone that once held an older recogniser keeps it forever; the transducer this model replaced was 339 MB.

```dart
  void sweepUpAfterAnOlderModel() {
    final keep = {
      for (final part in voiceModelParts) ...[part, '$part.part', '$part.etag'],
    };
    try {
      for (final entry in dir.listSync()) {
        if (entry is! File) continue;
        if (keep.contains(entry.uri.pathSegments.last)) continue;
        entry.deleteSync();
      }
    } on Object {
      // Disk the reader cannot see is not worth failing a download over.
    }
  }
```

[speech.dart:306](../../../app/lib/data/speech.dart#L306-L319)

The model is "ready" only when every part exists ([speech.dart:207](../../../app/lib/data/speech.dart#L207)). The reader can remove it again from Settings ([speech.dart:323](../../../app/lib/data/speech.dart#L323-L325)).

### 4. A prayer opens the microphone before the model loads

The prayer screen calls `PrayerVoice.start` when it opens ([prayer_screen.dart:183](../../../app/lib/features/prayer/prayer_screen.dart#L183-L191)). It checks the stored permission and the model files, and returns `null` if either is missing. The microphone opens first and the model loads second, because loading takes seconds and the first words of the recitation must not be lost:

```dart
      if (await micPermission(db) != MicPermission.granted) return null;
      final model = await VoiceModel.beside(await getDatabasesPath());
      if (!model.ready) return null;
      mic = AudioRecorder();
      // Asked without a prompt. The reader already answered in Settings, and
      // a device that has since had the permission taken away answers false
      // here rather than raising anything over the prayer. Thrown rather than
      // returned: see above.
      if (!await mic.hasPermission(request: false)) {
        throw StateError('the microphone was taken away since Settings');
      }
      voice = PrayerVoice._(cursor, Recitation(words), mic, log);
      await voice._listen();
      log.note('microphone', 'listening, ${since()}');
      listening?.call(voice);
```

[prayer_voice.dart:222](../../../app/lib/features/prayer/prayer_voice.dart#L222-L236)

Audio that arrives while the model loads waits in a buffer. Every failure after the microphone opens throws into one handler that stops everything ([prayer_voice.dart:251](../../../app/lib/features/prayer/prayer_voice.dart#L251-L260)). The stream is 16 kHz mono PCM with no auto gain and no noise suppression ([prayer_voice.dart:276](../../../app/lib/features/prayer/prayer_voice.dart#L276-L290)).

### 5. The recogniser runs on its own isolate

`Recogniser.open` spawns an isolate and gives up if it has not answered within 20 seconds ([speech.dart:359](../../../app/lib/data/speech.dart#L359-L393)). The isolate builds a sherpa_onnx streaming zipformer CTC recogniser, with endpointing on, and only then answers ([speech.dart:460](../../../app/lib/data/speech.dart#L460-L487)). The model writes Qurʼanic phonemes: Arabic letters, short vowels and tajwīd marks, with no Latin letters at all ([speech.dart:25](../../../app/lib/data/speech.dart#L25-L30)). One stream lives for the whole prayer. Each batch of samples goes in once, and the reply is the current utterance plus whether it has just ended:

```dart
      stream.acceptWaveform(samples: message, sampleRate: heardSampleRate);
      while (recogniser.isReady(stream)) {
        recogniser.decode(stream);
      }
      text = recogniser.getResult(stream).text;
      ended = recogniser.isEndpoint(stream);
      // Only the utterance now being said. What is worth carrying past the
      // end of one is the caller's business, which is where the matcher's
      // window lives.
      if (ended) recogniser.reset(stream);
```

[speech.dart:499](../../../app/lib/data/speech.dart#L499-L508)

`hear` never throws and never queues: a second ask while one is pending answers empty, and an ask times out after 10 seconds ([speech.dart:421](../../../app/lib/data/speech.dart#L421-L438)). Leaving the prayer asks the isolate to unwind, so the native weights are freed, and kills it after 2 seconds if it will not ([speech.dart:525](../../../app/lib/data/speech.dart#L525-L540)).

### 6. The drain hands audio over in 300 ms slices

`_handOver` takes the whole backlog at once and feeds it to the recogniser in slices of 300 ms ([prayer_voice.dart:331](../../../app/lib/features/prayer/prayer_voice.dart#L331-L448)). Before the reader's first word, quiet slices are skipped by a fixed level gate (`heardQuiet = 0.02`, [speech.dart:161](../../../app/lib/data/speech.dart#L161)). Once the reader begins, the gate latches open and every slice is heard, pauses included.

```dart
          if (peak < heardQuiet && !_speaking) continue;
          if (!_speaking) {
            trail.note('voice', 'the reader began, at ${peak.toStringAsFixed(2)}');
          }
          _speaking = true;
          final said = await hear(samples);
          // What the reciter has said, as far as this side is concerned: the
          // phrase before this one and the one now being spoken.
          final heard = '$_carried ${said.text}'.trim();
          // Read before it is replaced: this window is the old carry plus what
          // is being said now, and only the NEXT one is affected by an endpoint
          // here.
          _carried = carry(_carried, said);
```

[prayer_voice.dart:383](../../../app/lib/features/prayer/prayer_voice.dart#L383-L395)

The text judged is the previous utterance plus the current one, so the matcher can read across the breath between two ayas. When an utterance ends, the carry is replaced by what it said, even if that was nothing ([prayer_voice.dart:46](../../../app/lib/features/prayer/prayer_voice.dart#L46-L47)). That empty reset is the fix for a bystander's words being matched on the strength of the reader's own last aya.

Three more checks run before the matcher is asked ([prayer_voice.dart:417](../../../app/lib/features/prayer/prayer_voice.dart#L417-L427)): during a catch-up only the last slice moves the screen, an unchanged answer is not judged again, and for 4 seconds after a tap the reader's hand wins ([prayer_voice.dart:479](../../../app/lib/features/prayer/prayer_voice.dart#L479), [speech.dart:82](../../../app/lib/data/speech.dart#L82)).

### 7. Both sides are folded to the letters they agree on

The muṣḥaf writes fully vowelled Uthmani text; the recogniser writes sounds, with doubled letters and held vowels. `recitationKey` reduces both to bare letters: it folds alif and hamza forms together, drops the waṣl alif, and collapses a run of one letter to that letter ([voice_follow.dart:19](../../../app/lib/features/prayer/voice_follow.dart#L19-L65)).

```dart
    // Everything that is not a letter: the harakāt, the sukūn, the waqf marks,
    // tatwīl, and the tajwīd the recogniser rides above a letter — the qalqala
    // on ٱقْرَأْ is written ءِقڇرَء and is the ق echoing, not a sound of its own.
    if (folded < 0x0621 || folded > 0x064A || folded == 0x0640) continue;
    if (folded != last) letters.writeCharCode(folded);
    last = folded;
  }
  return letters.toString();
```

[voice_follow.dart:57](../../../app/lib/features/prayer/voice_follow.dart#L57-L64)

### 8. The matcher locates the reciter in the set

The matcher does not transcribe. It already knows the text and only asks where in the set the last few words fit. `Recitation` folds the set once per prayer into one run of letters, remembering which word each letter came from ([alignment.dart:77](../../../app/lib/features/prayer/alignment.dart#L77-L112)).

```mermaid
flowchart TB
  heard["Heard text"] --> fold["Fold to letters,<br/>keep the last 24"]
  fold --> short{"Fewer than 4 letters?"}
  short -->|yes| none["No place"]
  short -->|no| scan["Score the tail against<br/>every word end in the set"]
  scan --> best["Best place + best rival<br/>two or more words away"]
  best --> bar{"score >= needed?<br/>0.44 + 0.01 per missing letter"}
  bar -->|no| none
  bar -->|yes| margin{"score - rival >= 0.32?"}
  margin -->|no| none
  margin -->|yes| move["Move to that word"]
  move --> sure{"score >= 0.8?"}
  sure -->|yes| word["Word lit"]
  sure -->|no| aya["Only the aya lit"]
```

`explain` scores the heard tail against the text ending at every word end in the set, using edit distance ([alignment.dart:139](../../../app/lib/features/prayer/alignment.dart#L139-L190)). It searches the whole set, not a band ahead of the screen, so a reciter who repeats an aya is followed back into it. `locate` adds two gates:

```dart
({int word, double score})? locate(Recitation set, String heard) {
  final said = explain(set, heard);
  if (said == null) return null;
  if (said.score < said.needed) return null;
  if (said.score - said.rival < followMargin) return null;
  return (word: said.word, score: said.score);
}
```

[alignment.dart:124](../../../app/lib/features/prayer/alignment.dart#L124-L130)

The window is short on purpose, about four words ([alignment.dart:40](../../../app/lib/features/prayer/alignment.dart#L40)). A long window would drag a reciter who repeats an aya forward through the text. The thresholds are named constants with their reasons beside them ([alignment.dart:49](../../../app/lib/features/prayer/alignment.dart#L49-L65)). The margin is what refuses a phrase that appears twice in the set. Where the screen stands now is deliberately not an input.

Settings has a check screen that runs the same `locate` and `explain` on live audio, so a reader can see what is heard, where it lands and why it did not move, without praying ([voice_check.dart:134](../../../app/lib/features/settings/voice_check.dart#L134-L160)). It feeds the recogniser directly, with no slicing and no level gate, and it keeps the older carry rule that holds on to the last non-empty utterance ([voice_check.dart:128](../../../app/lib/features/settings/voice_check.dart#L128-L131)).

### 9. The cursor moves, and the screen turns the aya

A match moves the cursor, marking the word as sure only above `followSure`, and shows the matched words as a faint echo under the aya ([prayer_voice.dart:437](../../../app/lib/features/prayer/prayer_voice.dart#L437-L440)). The cursor moves in either direction and stays silent when nothing changed:

```dart
  void moveTo(int word, {bool sure = true}) {
    final next = word.clamp(0, words - 1);
    if (next == _at && sure == _sure) return;
    _at = next;
    _sure = sure;
    notifyListeners();
  }
```

[prayer_cursor.dart:58](../../../app/lib/features/prayer/prayer_cursor.dart#L58-L64)

```mermaid
stateDiagram-v2
  [*] --> Shown: aya on screen
  Shown --> Dwell: voice crosses into another aya
  Dwell --> Shown: dwell ends, next aya shown
  Dwell --> Shown: second move, turn at once
  Dwell --> Shown: cursor back in the shown aya, wait cancelled
  Shown --> Shown: tap, turn at once
```

The screen lets the aya just finished stand for a one-second dwell before turning ([prayer_screen.dart:70](../../../app/lib/features/prayer/prayer_screen.dart#L70)), unless the reciter keeps going or the move came from a tap ([prayer_screen.dart:159](../../../app/lib/features/prayer/prayer_screen.dart#L159-L178)). A tap forward goes to the start of the next aya. A tap back goes to the start of the aya you are in, or to the aya before when you are already at its start. Both wrap at the ends of the set, and calls `hold` so the voice does not pull the screen straight back ([prayer_screen.dart:261](../../../app/lib/features/prayer/prayer_screen.dart#L261-L276)).

### 10. The prayer trail records what happened

A prayer cannot be watched, so each one writes `prayer-trail.log` beside the database, truncated when the next prayer opens ([prayer_trail.dart:28](../../../app/lib/features/prayer/prayer_trail.dart#L28-L38)). Every line is stamped with seconds since the prayer opened, and writing never fails the prayer:

```dart
  void note(String what, String detail) {
    final sink = _sink;
    if (sink == null) return;
    try {
      final at = DateTime.now().difference(_began).inMilliseconds / 1000;
      sink.writeln('${at.toStringAsFixed(1)}s  $what  $detail');
    } on Object {
      // A prayer is not interrupted so that its diary can be kept.
    }
  }
```

[prayer_trail.dart:46](../../../app/lib/features/prayer/prayer_trail.dart#L46-L55)

The lines written include: the size of the `set`, `microphone` and `recogniser` load times ([prayer_voice.dart:235](../../../app/lib/features/prayer/prayer_voice.dart#L235-L244)), a `voice` line when voice-follow did not start ([prayer_screen.dart:202](../../../app/lib/features/prayer/prayer_screen.dart#L202)), `voice` when the reader begins, a `still here` heartbeat every 3 seconds with the range of batch levels ([prayer_voice.dart:366](../../../app/lib/features/prayer/prayer_voice.dart#L366-L378)), each `utterance ended`, each `held` for a new answer ignored during a hold, and each `heard` with the matcher's verdict: `too little heard`, `MOVE`, `stay` under the bar, or `stay` because the phrase was said twice ([prayer_voice.dart:484](../../../app/lib/features/prayer/prayer_voice.dart#L484-L496)). The trail is local only. On a Mac it lands next to `wird.db` in the app's sandboxed Documents folder ([Getting started](../../guides/getting-started.md#the-one-trap-delete-wirddb-after-a-corpus-rebuild)).

### 11. Leaving the prayer stops everything, once

`stop` is idempotent and swallows every error, because it is reached from both the screen's way out and `start`'s own failure handler ([prayer_voice.dart:510](../../../app/lib/features/prayer/prayer_voice.dart#L510-L532)). The screen tracks the voice from the moment the microphone is live, so backing out while the model still loads also closes the microphone ([prayer_screen.dart:127](../../../app/lib/features/prayer/prayer_screen.dart#L127-L135)).

### Known issues

The field walks are recorded in [the voice-follow walk](../../journal/voice-follow-walk.md). The open one is [finding 9](../../journal/voice-follow-walk.md#9-the-margin-rule-pins-the-cursor-on-any-set-that-says-a-phrase-twice): the margin rule refuses every window on a set that says one phrase twice, such as ٱلرَّحْمَـٰنِ ٱلرَّحِيمِ in al-Fātiḥa, so the cursor can stand still for many seconds.

## Why it is this way

- [ADR 0005](../../adr/0005-voice-follow-locates-the-reciter-with-a-quran-model-on-the-phone.md) — locate, do not transcribe; the model runs on the phone; the tap stays the fallback.
- [ADR 0007](../../adr/0007-the-voice-model-is-published-where-its-weights-already-live.md) — superseded; kept for why a signed-out phone must be able to fetch the model.
- [ADR 0008](../../adr/0008-the-recogniser-is-served-from-wirds-own-host.md) — the model is served from `wird.bnei.dev/models/` as a redirect to the object store.
- [ADR 0009](../../adr/0009-the-recogniser-hears-quranic-phonemes-not-language.md) — an Arabic-only phoneme CTC model replaced a multilingual one that drifted into other languages.

## Go deeper

- Parent: [App](../app.md). Sibling: [Sets and reader](sets-and-reader.md), which builds the set voice-follow listens for.
- Tour: [Following your voice](../../tours/following-your-voice.md).
- Field log: [the voice-follow walk](../../journal/voice-follow-walk.md).
- Tests: [voice_follow_test.dart](../../../app/test/features/prayer/voice_follow_test.dart) (graded fixtures), [prayer_cursor_test.dart](../../../app/test/features/prayer/prayer_cursor_test.dart), [speech_test.dart](../../../app/test/data/speech_test.dart), [voice_model_test.dart](../../../app/test/features/settings/voice_model_test.dart).
