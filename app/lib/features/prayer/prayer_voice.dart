import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:sqflite/sqflite.dart';

import '../../data/mic.dart';
import '../../data/speech.dart';
import 'alignment.dart';
import 'prayer_cursor.dart';
import 'prayer_trail.dart';

/// The microphone, wired to the cursor.
///
/// It holds whatever of the reciter's voice the recogniser has not been handed
/// yet — a fraction of a second in the ordinary case, and up to twenty at the
/// start of a prayer while the model is still loading — hands it over when the
/// last batch has come back, and gives whatever came out to [followHeard]. That
/// is the whole of it, and the shortness is the point: everything that could go
/// wrong here goes wrong as silence.
///
/// Contract 2 — nothing appears in front of someone praying — is kept by there
/// being no path out of this class onto the screen. It cannot raise a dialog,
/// it has no error to show, and the only thing it can do to the prayer is call
/// [PrayerCursor.follow], which refuses to rewind and ceilings a jump.

/// What survives the end of an utterance. An utterance that ended with nothing
/// decoded is a reader who has stopped, not a breath between ayas.
///
/// Finding 1 on the walk: in a room where English was being spoken a metre away
/// the cursor moved to word 8 on a phrase nobody praying had said. The level
/// gate is not what let that through — the phrase scored 0.58 on the reader's
/// OWN last aya, with a bystander fragment glued to the end of it. Two endpoints
/// in a row had decoded nothing, six seconds apart, and because the carry was
/// only replaced when an utterance ended with text, the reader's aya stayed
/// standing as the front half of every window after them. The junk matched on
/// the strength of somebody else's recitation.
///
/// The cost is lateness, and it is not free. sherpa's rule 1 endpoints on 2.4 s
/// of trailing silence with `must_contain_nonsilence = false`, so it re-fires
/// through any long quiet: a reader in rukūʿ or sujūd, or listening to an imam,
/// produces empty endpoints while still praying and each one wipes the field
/// whose whole purpose is reading across the breath between two ayas. A late
/// screen beats a wrong one, and the lateness heals itself as the reciter
/// carries on. A wrong cursor position does not.
String carry(String previous, ({String text, bool ended}) said) =>
    said.ended ? said.text.trim() : previous;

class PrayerVoice {
  PrayerVoice._(this._cursor, this._set, this._mic, this.trail);

  /// The last words the recogniser was sure enough about to move the prayer
  /// on, and nothing else.
  ///
  /// The screen shows these while the reader recites. Only what matched: a
  /// window the matcher refused is a window it could not read, and showing
  /// that to somebody praying would be the screen talking about itself.
  final matched = ValueNotifier<String>('');

  final PrayerCursor _cursor;
  final Recitation _set;

  /// What happened, for reading afterwards. A prayer cannot be watched.
  final PrayerTrail trail;
  final AudioRecorder _mic;

  /// Null until the model has finished loading, because the microphone is opened
  /// first — see [start]. Nullable and mutable, so Dart will not promote it: bind
  /// a local before using it.
  Recogniser? _recogniser;

  StreamSubscription<Uint8List>? _stream;

  /// Recitation the recogniser has not been handed yet, because it is still
  /// working on what came before — or because it does not exist yet, which is the
  /// whole of what [start]'s reorder buys. Nothing here may be dropped: a
  /// transducer that misses a second of speech misses the words in it for good.
  final _waiting = <double>[];
  var _handing = false;

  /// Whether [stop] has already run. It is called from the prayer screen's way
  /// out AND from [start]'s own handler, and `matched.dispose()` throws the
  /// second time.
  var _stopped = false;

  /// [heardChunk]'s worth of samples: the batch size everything on this path was
  /// measured at, and the size the catch-up drain hands over in.
  ///
  /// Derived, not a new number to tune. ADR 0009 and [heardChunk]'s own doc both
  /// say 300 ms, "the way the app feeds it", and all five graded fixtures are
  /// 300 ms batches. Nothing in the suite covers a twenty-second one.
  static final _slice = heardChunk.inMilliseconds * heardSampleRate ~/ 1000;

  /// Until when the reader's own hand has the prayer.
  ///
  /// A tap and a voice disagree for a moment by construction: the reader taps
  /// because the screen is in the wrong place, and the seconds already heard
  /// still describe where it was. Without this the next answer — computed from
  /// the same unchanged recitation — puts the screen straight back, and the
  /// one correction the reader has stops working.
  DateTime _theirs = DateTime.fromMillisecondsSinceEpoch(0);

  /// Whether the reader has said anything yet. Until they have, the quiet is
  /// kept away from the recogniser; afterwards it is fed everything, because
  /// a pause between ayas is part of the recitation and cutting it out would
  /// hand the recogniser a reader who never breathes.
  ///
  /// There is more of that lead-in quiet than there used to be: the microphone
  /// now opens before the model loads, so the first thing the recogniser is
  /// handed is a catch-up buffer that begins several seconds before the reader
  /// did. That is why the drain hands it over in [_slice]-sized batches rather
  /// than as one window — a single batch computes ONE peak, so one loud sample
  /// would walk twenty seconds of room straight through this gate. Sliced, the
  /// gate refuses the silent batches one at a time, which is what it was
  /// measured doing.
  ///
  /// It is latched on purpose and must stay latched. See [heardQuiet] for why
  /// re-arming it at an endpoint drops recitation.
  var _speaking = false;

  /// What the recogniser last said, so an unchanged answer is not re-judged.
  String _lastHeard = '';
  DateTime _lastSaid = DateTime.fromMillisecondsSinceEpoch(0);

  /// The utterance before the one now being said. This is what lets the matcher
  /// read across the breath between two ayas, and [carry] is the whole of the
  /// rule for what stays in it.
  String _carried = '';

  /// Every batch's peak level since the last heartbeat: how many, and the two
  /// ends of the range.
  ///
  /// Measurement, not a gate — nothing reads these but the trail. Three sets of
  /// numbers have been written down for [heardQuiet] and they disagree by a
  /// factor of twenty, so the argument about it has to be had against the levels
  /// this path actually sees. Counted BEFORE the gate, so the batches it refuses
  /// are in the distribution too, and printed at three decimals because two
  /// renders the committed 0.004 room figure as `0.00`.
  var _peaks = 0;
  var _quietest = 1.0;
  var _loudest = 0.0;

  /// Starts listening, or answers null and leaves the prayer to the thumb.
  ///
  /// Null is the ordinary outcome and not a fault: no permission, no model, no
  /// microphone, an isolate that would not start. Voice-follow is on exactly
  /// when the reader has granted the microphone and downloaded the model, both
  /// of which happen in Settings, long before anyone is praying.
  ///
  /// THE MICROPHONE OPENS BEFORE THE MODEL LOADS, and that ordering is the fix
  /// for the second walk finding: it took 4.5 s to reach first audio, so the
  /// opening of the recitation was never captured at all — the cursor sat on
  /// word 0 until 18.1s and then jumped to word 7. [Recogniser.open] spawns an
  /// isolate and loads 72.7 MB of int8 with a twenty-second timeout of its own,
  /// and `_waiting`'s promise that nothing is dropped can only begin when the
  /// stream does.
  static Future<PrayerVoice?> start(
    Database db,
    PrayerCursor cursor,
    List<String> words, {
    PrayerTrail? trail,
  }) async {
    PrayerVoice? voice;
    AudioRecorder? mic;
    // How long the reader waited, for both halves of it. The microphone is
    // opened first now, so `microphone listening` comes before `recogniser
    // loaded` and the gap between them is exactly the audio the catch-up buffer
    // is holding.
    final log = trail ?? PrayerTrail.none();
    final asked = DateTime.now();
    String since() =>
        '${DateTime.now().difference(asked).inMilliseconds}ms after the prayer opened';
    // NOTHING PAST THE MICROPHONE RETURNS. [Recogniser.open] answers null rather
    // than throwing, and a `return null` from below here would walk out leaving
    // a live stream appending into `_waiting` for the length of the prayer while
    // the screen says IN PRAYER — boxed doubles at 16 kHz, so a ten-minute
    // prayer is a couple of hundred megabytes and an OS kill mid-sujūd. So every
    // exit from here on throws, and the handler below is the one thing that
    // knows what is open.
    try {
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
      final recogniser = await Recogniser.open(model);
      if (recogniser == null) {
        // Files of the right names and the wrong bytes — a download the phone
        // truncated. Thrown rather than returned, because the stream above is
        // live by now.
        throw StateError('the model is on the phone and would not load');
      }
      log.note('recogniser', 'loaded, ${since()}');
      voice._recogniser = recogniser;
      // Explicitly, or the catch-up buffer sits there until the microphone's
      // next chunk happens to call `_handOver` for us.
      unawaited(voice._handOver());
      return voice;
    } on Object {
      // Once the voice exists it owns the stream, and only [stop] knows how to
      // put all of it back. It is total and idempotent for exactly this reason.
      if (voice != null) {
        await voice.stop();
      } else {
        await mic?.dispose();
      }
      return null;
    }
  }

  Future<void> _listen() async {
    final audio = await _mic.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: heardSampleRate,
        numChannels: 1,
        // A prayer room is quiet and the voice is the reader's own, a foot
        // from the phone. What these would buy is not worth what they cost a
        // recogniser trained on clean recitation.
        autoGain: false,
        noiseSuppress: false,
      ),
    );
    _stream = audio.listen(_keep, onError: (_) {});
  }

  void _keep(Uint8List chunk) {
    _waiting.addAll(pcm16ToFloat(chunk));
    unawaited(_handOver());
  }

  /// Hands over everything waiting, and asks where the reciter is.
  ///
  /// One hand-over at a time, and what arrives meanwhile waits rather than
  /// being dropped. Under load the batches grow instead of the audio thinning,
  /// so the answer is late rather than wrong — and a phone that cannot keep up
  /// leaves the reader the tap, which is what they had before any of this.
  ///
  /// IN [_slice]-SIZED BATCHES, never in one. At the start of a prayer this is
  /// draining up to twenty seconds of catch-up audio, and handing that over as a
  /// single batch would be wrong four ways: it can exceed `hear`'s own ten-second
  /// timeout, which nulls `_pending` while the isolate is still working and leaves
  /// every answer after it — `ended` included — permanently one batch out of step;
  /// an endpoint is then certain on the first answer, so the carried utterance is
  /// set from a window that is mostly empty room; one peak over twenty seconds
  /// walks the room through the level gate on a single loud sample; and it
  /// abandons the 300 ms regime every fixture and every measurement is in.
  Future<void> _handOver() async {
    // Dart will not promote a nullable mutable field, and the recogniser may not
    // exist yet: until it does, the audio waits. `start` calls this itself once
    // the model is up.
    final recogniser = _recogniser;
    if (_handing || recogniser == null || _waiting.isEmpty) return;
    _handing = true;
    try {
      while (_waiting.isNotEmpty) {
        final take = _waiting.length < _slice ? _waiting.length : _slice;
        final samples = Float32List.fromList(_waiting.sublist(0, take));
        _waiting.removeRange(0, take);
        // A recogniser handed silence answers anyway, with a phrase the
        // matcher then has to refuse. The prayer screen opens before the
        // reader begins, so the quiet before the first word is exactly what
        // must not reach it.
        var peak = 0.0;
        for (final sample in samples) {
          final loud = sample < 0 ? -sample : sample;
          if (loud > peak) peak = loud;
        }
        _peaks++;
        if (peak < _quietest) _quietest = peak;
        if (peak > _loudest) _loudest = peak;
        if (peak < heardQuiet && !_speaking) continue;
        if (!_speaking) {
          trail.note('voice', 'the reader began, at ${peak.toStringAsFixed(2)}');
        }
        _speaking = true;
        final said = await recogniser.hear(samples);
        // What the reciter has said, as far as this side is concerned: the
        // phrase before this one and the one now being spoken.
        final heard = '$_carried ${said.text}'.trim();
        // Read before it is replaced: this window is the old carry plus what is
        // being said now, and only the NEXT one is affected by an endpoint here.
        _carried = carry(_carried, said);
        if (said.ended) {
          trail.note(
            'utterance ended',
            said.text.isEmpty ? '(nothing)' : said.text,
          );
        }
        // A heartbeat even when nothing changes, because the last trail had a
        // sixty-second hole in it: the answer stopped changing, every window
        // was skipped, and the record went quiet at exactly the moment it was
        // needed. Silence in a diary reads the same as silence in the room.
        if (DateTime.now().difference(_lastSaid) > heardHeartbeat) {
          _lastSaid = DateTime.now();
          trail.note(
            'still here',
            '$_peaks batches, peak ${_quietest.toStringAsFixed(3)} to '
            '${_loudest.toStringAsFixed(3)} | ${_tail(heard)}',
          );
          _peaks = 0;
          _quietest = 1.0;
          _loudest = 0.0;
        }
        if (heard.isEmpty) continue;
        // The same words as last time are the same question as last time, and
        // it has already been answered. A reader who stops reciting leaves the
        // answer standing, and re-judging it forty times a second neither
        // changes it nor stops being work.
        if (heard == _lastHeard) continue;
        _lastHeard = heard;
        _lastSaid = DateTime.now();
        if (DateTime.now().isBefore(_theirs)) {
          trail.note('held', 'the reader moved the prayer themselves');
          continue;
        }
        final why = explain(_set, heard);
        final at = locate(_set, heard);
        trail.note(
          'heard',
          '${_tail(heard)} | ${_verdict(why, at)} | on ${_cursor.at} '
          '| peak ${peak.toStringAsFixed(2)}',
        );
        // Above the bar the word is named; at the bar the aya is as much as
        // the recitation actually said.
        if (at != null) {
          _cursor.moveTo(at.word, sure: at.score >= followSure);
          matched.value = _tail(heard);
        }
      }
    } on Object {
      // Silence. The reader taps, as they always could.
    } finally {
      _handing = false;
    }
  }

  /// The reader moved the prayer themselves. Their hand wins for a moment,
  /// long enough for what they were reciting to leave the window.
  void hold() => _theirs = DateTime.now().add(heardHeldByHand);

  static String _tail(String heard) =>
      heard.length > 40 ? heard.substring(heard.length - 40) : heard;

  static String _verdict(
    ({int word, double score, double rival, double needed})? said,
    ({int word, double score})? at,
  ) {
    if (said == null) return 'too little heard';
    final where = 'word ${said.word} at ${said.score.toStringAsFixed(2)}';
    if (at != null) return 'MOVE to $where';
    if (said.score < said.needed) {
      return 'stay: $where under ${said.needed.toStringAsFixed(2)}';
    }
    return 'stay: $where but elsewhere ${said.rival.toStringAsFixed(2)} '
        '— said twice';
  }

  /// Ends the listening. It cannot fail, and it cannot be run twice.
  ///
  /// Both of those are load-bearing now that [start]'s own handler calls this:
  /// `matched.dispose()` throws the second time, and `start` is reached from the
  /// prayer screen's `initState` through an `unawaited` with no `try` around it,
  /// so anything escaping here is an uncaught async error raised over somebody
  /// praying. Every line below is a platform, isolate or stream call on the way
  /// out of a prayer and not one of them is worth failing over.
  ///
  /// It blocks for up to two seconds: `close` asks the isolate to unwind rather
  /// than killing it, because killing reclaims the Dart heap and not the weights
  /// onnxruntime malloc'd.
  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    final stream = _stream;
    _stream = null;
    final recogniser = _recogniser;
    _recogniser = null;
    _waiting.clear();
    Future<void> attempt(Future<void> Function() step) async {
      try {
        await step();
      } on Object {
        // Leaving the prayer is not a moment to fail in either.
      }
    }

    await attempt(() async => matched.dispose());
    await attempt(() async => stream?.cancel());
    await attempt(() async => recogniser?.close());
    await attempt(_mic.stop);
    await attempt(_mic.dispose);
  }
}
