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
/// It holds the last few seconds of the reciter's voice, hands a window of it
/// to the recogniser when the last one has come back, and gives whatever came
/// out to [followHeard]. That is the whole of it, and the shortness is the
/// point: everything that could go wrong here goes wrong as silence.
///
/// Contract 2 — nothing appears in front of someone praying — is kept by there
/// being no path out of this class onto the screen. It cannot raise a dialog,
/// it has no error to show, and the only thing it can do to the prayer is call
/// [PrayerCursor.follow], which refuses to rewind and ceilings a jump.
class PrayerVoice {
  PrayerVoice._(this._cursor, this._set, this._recogniser, this._mic, this.trail);

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
  final Recogniser _recogniser;
  final AudioRecorder _mic;

  StreamSubscription<Uint8List>? _stream;

  /// Recitation the recogniser has not been handed yet, because it is still
  /// working on what came before. Nothing here may be dropped: a transducer
  /// that misses a second of speech misses the words in it for good.
  final _waiting = <double>[];
  var _handing = false;

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
  var _speaking = false;

  /// What the recogniser last said, so an unchanged answer is not re-judged.
  String _lastHeard = '';
  DateTime _lastSaid = DateTime.fromMillisecondsSinceEpoch(0);

  /// The utterance before the one now being said, when it was Arabic. This is
  /// what lets the matcher read across the breath between two ayas.
  String _carried = '';

  /// Starts listening, or answers null and leaves the prayer to the thumb.
  ///
  /// Null is the ordinary outcome and not a fault: no permission, no model, no
  /// microphone, an isolate that would not start. Voice-follow is on exactly
  /// when the reader has granted the microphone and downloaded the model, both
  /// of which happen in Settings, long before anyone is praying.
  static Future<PrayerVoice?> start(
    Database db,
    PrayerCursor cursor,
    List<String> words, {
    PrayerTrail? trail,
  }) async {
    Recogniser? recogniser;
    AudioRecorder? mic;
    // Nothing is allocated before the recogniser, and nothing past it returns:
    // an exit from there on throws, so the one handler that knows what is open
    // is the one that closes it.
    try {
      if (await micPermission(db) != MicPermission.granted) return null;
      final model = await VoiceModel.beside(await getDatabasesPath());
      if (!model.ready) return null;
      recogniser = await Recogniser.open(model);
      if (recogniser == null) return null;
      mic = AudioRecorder();
      // Asked without a prompt. The reader already answered in Settings, and
      // a device that has since had the permission taken away answers false
      // here rather than raising anything over the prayer. Thrown rather than
      // returned: the recogniser above is open by now, and only the handler
      // below knows to close it.
      if (!await mic.hasPermission(request: false)) {
        throw StateError('the microphone was taken away since Settings');
      }
      final voice = PrayerVoice._(
        cursor,
        Recitation(words),
        recogniser,
        mic,
        trail ?? PrayerTrail.none(),
      );
      await voice._listen();
      return voice;
    } on Object {
      recogniser?.close();
      await mic?.dispose();
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
  Future<void> _handOver() async {
    if (_handing || _waiting.isEmpty) return;
    _handing = true;
    try {
      while (_waiting.isNotEmpty) {
        final samples = Float32List.fromList(_waiting);
        _waiting.clear();
        // A recogniser handed silence answers anyway, with a phrase the
        // matcher then has to refuse. The prayer screen opens before the
        // reader begins, so the quiet before the first word is exactly what
        // must not reach it.
        var peak = 0.0;
        for (final sample in samples) {
          final loud = sample < 0 ? -sample : sample;
          if (loud > peak) peak = loud;
        }
        if (peak < heardQuiet && !_speaking) continue;
        if (!_speaking) {
          trail.note('voice', 'the reader began, at ${peak.toStringAsFixed(2)}');
        }
        _speaking = true;
        final said = await _recogniser.hear(samples);
        // What the reciter has said, as far as this side is concerned: the
        // phrase before this one and the one now being spoken.
        final heard = '$_carried ${said.text}'.trim();
        if (said.ended) {
          if (said.text.trim().isNotEmpty) _carried = said.text.trim();
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
            'peak ${peak.toStringAsFixed(2)} | ${_tail(heard)}',
          );
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

  Future<void> stop() async {
    matched.dispose();
    await _stream?.cancel();
    _stream = null;
    _waiting.clear();
    _recogniser.close();
    try {
      await _mic.stop();
    } on Object {
      // Leaving the prayer is not a moment to fail in either.
    }
    await _mic.dispose();
  }
}
