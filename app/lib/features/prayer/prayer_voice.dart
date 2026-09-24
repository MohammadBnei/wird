import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart';
import 'package:sqflite/sqflite.dart';

import '../../data/mic.dart';
import '../../data/speech.dart';
import 'prayer_cursor.dart';
import 'voice_follow.dart';

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
  PrayerVoice._(this._cursor, this._keys, this._recogniser, this._mic);

  final PrayerCursor _cursor;
  final List<String> _keys;
  final Recogniser _recogniser;
  final AudioRecorder _mic;

  StreamSubscription<Uint8List>? _stream;
  Timer? _hop;
  var _lastWindow = heardHop;

  /// The last [heardWindow] of recitation, oldest first.
  final _recent = <double>[];

  /// Starts listening, or answers null and leaves the prayer to the thumb.
  ///
  /// Null is the ordinary outcome and not a fault: no permission, no model, no
  /// microphone, an isolate that would not start. Voice-follow is on exactly
  /// when the reader has granted the microphone and downloaded the model, both
  /// of which happen in Settings, long before anyone is praying.
  static Future<PrayerVoice?> start(
    Database db,
    PrayerCursor cursor,
    List<String> words,
  ) async {
    Recogniser? recogniser;
    AudioRecorder? mic;
    try {
      if (await micPermission(db) != MicPermission.granted) return null;
      final model = await VoiceModel.beside(await getDatabasesPath());
      if (!model.ready) return null;
      recogniser = await Recogniser.open(model);
      if (recogniser == null) return null;
      mic = AudioRecorder();
      // Asked without a prompt. The reader already answered in Settings, and
      // a device that has since had the permission taken away answers false
      // here rather than raising anything over the prayer.
      if (!await mic.hasPermission(request: false)) return null;
      final voice = PrayerVoice._(
        cursor,
        recitationKeys(words),
        recogniser,
        mic,
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
    _schedule(heardHop);
  }

  /// The next window is asked for no sooner than [heardHop], and never sooner
  /// than the last one took to answer. A phone slow enough to spend a second
  /// on a window is a phone that gets asked half as often, rather than one
  /// that runs its recogniser flat out for the length of a prayer.
  void _schedule(Duration wait) {
    _hop = Timer(wait, () async {
      await _askWhereWeAre();
      if (_hop != null) {
        _schedule(_lastWindow > heardHop ? _lastWindow : heardHop);
      }
    });
  }

  void _keep(Uint8List chunk) {
    _recent.addAll(pcm16ToFloat(chunk));
    final keep = heardWindow.inMilliseconds * heardSampleRate ~/ 1000;
    if (_recent.length > keep) {
      _recent.removeRange(0, _recent.length - keep);
    }
  }

  /// One window, asked about only when the last answer is in. A window that
  /// arrives while the recogniser is still working is dropped: an answer about
  /// audio from several seconds ago would move the prayer to where the reciter
  /// used to be.
  Future<void> _askWhereWeAre() async {
    if (_recogniser.busy) return;
    // Under a second of voice is a breath between ayas, not a word.
    if (_recent.length < heardSampleRate) return;
    final started = DateTime.now();
    try {
      final heard = await _recogniser.hear(Float32List.fromList(_recent));
      _lastWindow = DateTime.now().difference(started);
      if (heard.isNotEmpty) followHeard(_cursor, _keys, heard);
    } on Object {
      // Silence. The reader taps, as they always could.
    }
  }

  Future<void> stop() async {
    _hop?.cancel();
    _hop = null;
    await _stream?.cancel();
    _recogniser.close();
    try {
      await _mic.stop();
    } on Object {
      // Leaving the prayer is not a moment to fail in either.
    }
    await _mic.dispose();
  }
}
