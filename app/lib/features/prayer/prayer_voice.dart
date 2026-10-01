import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:sqflite/sqflite.dart';

import '../../data/mic.dart';
import '../../data/speech.dart';
import 'alignment.dart';
import 'prayer_cursor.dart';
import 'prayer_trail.dart';
import 'voice_follow.dart';

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
/// [PrayerCursor.moveTo], and only on a place `locate` named clearly.

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

/// How long an unchanged window may go on counting as the reciter heard.
///
/// A madd is held for two to six counts, a few seconds at most. Past that,
/// the same words standing in a loud room are not a vowel being held: they
/// are a recogniser that has stopped writing anything new — it lost the
/// reciter, or someone beside them is praying aloud — and that is the case
/// the pace is there to cover.
const heldAtMost = Duration(seconds: 6);

/// Whether an answer unchanged since the last one is still the reciter being
/// heard: the last answer named them surely, the room is loud, and not for
/// longer than a held vowel lasts.
bool stillHeard({
  required bool sure,
  required double peak,
  required Duration since,
}) => sure && peak >= heardQuiet && since < heldAtMost;

/// How many words of Al-Fātiḥa a rakʿah may be begun inside: its first two
/// ayas, the basmala and `al-ḥamdu lillāhi rabbi l-ʿālamīn`, four words each.
const openingWords = 8;

class PrayerVoice {
  PrayerVoice._(this._cursor, this._set, this._mic, this.trail, this._unseenAt);

  /// The last words the recogniser was sure enough about to move the prayer
  /// on, and nothing else.
  ///
  /// Read by the tests of the drain, which is the one place what matched can
  /// be seen: the prayer screen no longer echoes it under the aya. Only what
  /// matched — a window the matcher refused is a window it could not read.
  final matched = ValueNotifier<String>('');

  /// The rakʿah being recited. Both are replaced by [follow] when the next
  /// one begins, because the model takes up to twenty seconds to load and a
  /// prayer cannot wait that long between two rakʿahs.
  PrayerCursor _cursor;
  Recitation _set;

  /// Where in [_set] the basmala the screen does not show begins, or -1. The
  /// words heard there move nothing, and the ones after it are that many
  /// further along in [_set] than on the screen: see `rakahOf`.
  int _unseenAt;

  /// Whether the next rakʿah is waiting to be begun. Between two rakʿahs the
  /// reader is bowing, standing and prostrating, and what they say there —
  /// `al-ḥamdu lillāh` among it — is the opening of Al-Fātiḥa as far as a short
  /// window can tell. So only a full window, landing in Al-Fātiḥa's first two
  /// ayas, begins the rakʿah: that is the reader reciting it, not praising.
  var _opening = false;

  /// Bumped by [follow], so an answer the recogniser was already working on
  /// for the rakʿah just finished is not laid against the next one.
  var _generation = 0;

  /// Whether the last answer judged named the reciter's word surely.
  var _lastSure = false;

  /// When new words last named the reciter's place surely.
  var _lastFound = DateTime.fromMillisecondsSinceEpoch(0);

  /// Called whenever the voice names the reciter's word surely, the same word
  /// again included, so the pace knows the reciter has not been lost.
  void Function()? onRecognised;

  /// What happened, for reading afterwards. A prayer cannot be watched.
  final PrayerTrail trail;
  final AudioRecorder _mic;

  /// Null until the model has finished loading, because the microphone is
  /// opened first — see [start]. Held only so [stop] can give it back; the
  /// drain asks through [_hear].
  Recogniser? _recogniser;

  /// How the drain asks where the reciter is. [Recogniser.hear] in a prayer,
  /// and the one seam the drain can be tested through: `FakeMic` cannot carry a
  /// stream, so a test that went in through [start] never reaches a batch at
  /// all, and the drain is the part of this class with a loop, a level gate and
  /// a ceiling in it.
  ///
  /// Nullable and mutable, so Dart will not promote it: bind a local first.
  Future<({String text, bool ended})> Function(Float32List)? _hear;

  StreamSubscription<Uint8List>? _stream;

  /// Recitation the recogniser has not been handed yet, because it is still
  /// working on what came before — or because it does not exist yet, which is the
  /// whole of what [start]'s reorder buys. Nothing here may be dropped: a
  /// transducer that misses a second of speech misses the words in it for good.
  ///
  /// It holds no more than the microphone delivered during one hand-over, and
  /// [_handOver] keeps it that way on purpose rather than by a size limit.
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
  ///
  /// A ceiling on one piece and never a floor: an ordinary hand-over is
  /// whatever the microphone delivered since the last one, which is less.
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

  /// What the recogniser last said AND was acted on, so an unchanged answer is
  /// not re-judged.
  ///
  /// An answer computed while the drain was still behind is not recorded here:
  /// it never reached the screen, so the piece that catches up must not be
  /// deduplicated against it.
  String _lastHeard = '';

  /// When the trail last spoke of its own accord. The heartbeat's clock, and
  /// nothing else reads it.
  ///
  /// It used to be reset by every changed answer as well, which meant the
  /// `still here` line — the only place the batch levels are written down —
  /// fired only after three seconds of UNCHANGED answer, and the range it then
  /// printed spanned a long mixed window of room and recitation. A single
  /// minimum over such a window cannot answer the one question asked of it:
  /// whether the reader's own batches reach [heardQuiet] or only the room does.
  DateTime _lastNoted = DateTime.fromMillisecondsSinceEpoch(0);

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
  ///
  /// [listening] IS HANDED THE VOICE THE MOMENT THE STREAM IS LIVE, which is
  /// before this answers. That ordering means the microphone runs for as long
  /// as the model takes to load, and a reader who mis-taps into a prayer and
  /// backs out two seconds later would otherwise leave it streaming — OS
  /// indicator and all, over whatever screen they went to next — until
  /// [Recogniser.open] resolves or times out twenty seconds later, because the
  /// prayer screen's own `_voice` is null for that whole window and its way out
  /// has nothing to stop. Whoever takes this owns [stop] from then on; it is
  /// total and idempotent, so this class and that caller may both call it.
  static Future<PrayerVoice?> start(
    Database db,
    PrayerCursor cursor,
    List<String> words, {
    int unseenAt = -1,
    PrayerTrail? trail,
    void Function(PrayerVoice)? listening,
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
      voice = PrayerVoice._(cursor, Recitation(words), mic, log, unseenAt);
      await voice._listen();
      log.note('microphone', 'listening, ${since()}');
      listening?.call(voice);
      final recogniser = await Recogniser.open(model);
      if (recogniser == null) {
        // Files of the right names and the wrong bytes — a download the phone
        // truncated. Thrown rather than returned, because the stream above is
        // live by now.
        throw StateError('the model is on the phone and would not load');
      }
      log.note('recogniser', 'loaded, ${since()}');
      // Explicitly, or the catch-up buffer sits there until the microphone's
      // next chunk happens to call `_handOver` for us. Not awaited: the drain
      // decodes everything the reader has already said, and the screen is
      // waiting on this call to stop saying IN PRAYER.
      unawaited(voice._use(recogniser));
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

  /// Takes the loaded model, or gives it straight back.
  ///
  /// The prayer can be over before the model is up — [start] hands the voice
  /// out as soon as the stream is live, so [stop] may already have run — and a
  /// recogniser nobody will ask anything of is an isolate holding 72.7 MB that
  /// the Dart heap cannot account for.
  Future<void> _use(Recogniser recogniser) async {
    if (_stopped) return recogniser.close();
    _recogniser = recogniser;
    _hear = recogniser.hear;
    await _handOver();
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
  /// being dropped.
  ///
  /// THE BACKLOG COMES OUT IN ONE MOVE AND GOES IN IN [_slice]-SIZED PIECES.
  /// Both halves are load-bearing, and they answer different questions.
  ///
  /// Out in one move, because that is the whole of what bounds `_waiting`: it
  /// can hold no more than the microphone delivered while the previous batch
  /// was being decoded. Taking one slice at a time and leaving the rest queued
  /// would make the BACKLOG the thing that grows when decode falls behind —
  /// boxed doubles at 16 kHz, and lateness growing for the length of the
  /// prayer, which on a phone on the floor is a wrong position rather than a
  /// late one. It also keeps the queue off the front: `removeRange(0, _slice)`
  /// on a `List<double>` shifts every element behind it, so slicing twenty
  /// seconds off the head is twenty-one million element moves, on the isolate
  /// that also draws the prayer, and it gets more expensive the further behind
  /// it falls. `clear` is free.
  ///
  /// In in pieces, because one twenty-second window would be wrong four ways:
  /// it can exceed `hear`'s own ten-second timeout, which nulls its `_pending`
  /// while the isolate is still working and leaves every answer after it —
  /// `ended` included — permanently one batch out of step; an endpoint is then
  /// certain on the first answer, so the carried utterance is set from a window
  /// that is mostly empty room; one peak over twenty seconds walks the room
  /// through the level gate on a single loud sample; and it abandons the 300 ms
  /// regime every fixture and every measurement is in.
  ///
  /// A phone that cannot keep up gets a late screen, and at the point where
  /// decoding is slower than speaking no arrangement of this is both complete
  /// and on time. Measured, a 300 ms piece costs 21 ms at two threads, a
  /// realtime factor of 0.07; the reader still has the tap, which is what they
  /// had before any of this.
  Future<void> _handOver() async {
    // Dart will not promote a nullable mutable field, and the model may not be
    // loaded yet: until it is, the audio waits. `start` calls this itself once
    // the model is up.
    final hear = _hear;
    if (_handing || hear == null || _waiting.isEmpty) return;
    _handing = true;
    try {
      while (_waiting.isNotEmpty) {
        final batch = Float32List.fromList(_waiting);
        _waiting.clear();
        // `_stopped` as well as the queue, because the queue is no longer what
        // this loop reads: the prayer can be left in the middle of a drain, and
        // a recogniser that has been closed answers every remaining piece with
        // `hear`'s ten-second timeout instead of an answer.
        for (var from = 0; from < batch.length && !_stopped; from += _slice) {
          final to = from + _slice < batch.length
              ? from + _slice
              : batch.length;
          final samples = batch.sublist(from, to);
          var peak = 0.0;
          for (final sample in samples) {
            final loud = sample < 0 ? -sample : sample;
            if (loud > peak) peak = loud;
          }
          _peaks++;
          if (peak < _quietest) _quietest = peak;
          if (peak > _loudest) _loudest = peak;
          // ABOVE the level gate, so the trail speaks even while nothing passes
          // it. A microphone handing back zeros — another app holding it, a
          // hardware mute: ordinary Android — otherwise prints `microphone
          // listening`, `recogniser loaded` and then nothing at all for the
          // whole prayer, which is the unreadable trail the heartbeat was added
          // to prevent, in the one case where silence in the record is most
          // ambiguous. Whether the reader has begun is printed with the range,
          // because an unlabelled range over a mixed window is the defect all
          // three rejected datasets for [heardQuiet] have.
          if (DateTime.now().difference(_lastNoted) > heardHeartbeat) {
            _lastNoted = DateTime.now();
            trail.note(
              'still here',
              '$_peaks batches '
                  '${_speaking ? 'since the reader began' : 'of room'}, peak '
                  '${_quietest.toStringAsFixed(3)} to '
                  '${_loudest.toStringAsFixed(3)} | ${_tail(_lastHeard)}',
            );
            _peaks = 0;
            _quietest = 1.0;
            _loudest = 0.0;
          }
          // A recogniser handed silence answers anyway, with a phrase the
          // matcher then has to refuse. The prayer screen opens before the
          // reader begins, so the quiet before the first word is exactly what
          // must not reach it.
          if (peak < heardQuiet && !_speaking) continue;
          if (!_speaking) {
            trail.note(
              'voice',
              'the reader began, at ${peak.toStringAsFixed(2)}',
            );
          }
          _speaking = true;
          final generation = _generation;
          final said = await hear(samples);
          // The rakʿah changed while this was being decoded. What it says is
          // about the rakʿah just finished, and the next one starts clean.
          if (generation != _generation) continue;
          // What the reciter has said, as far as this side is concerned: the
          // phrase before this one and the one now being spoken.
          final heard = '$_carried ${said.text}'.trim();
          // Read before it is replaced: this window is the old carry plus what
          // is being said now, and only the NEXT one is affected by an endpoint
          // here.
          _carried = carry(_carried, said);
          if (said.ended) {
            trail.note(
              'utterance ended',
              said.text.isEmpty ? '(nothing)' : said.text,
            );
          }
          if (heard.isEmpty) continue;
          // WHERE THE READER WAS. Another piece of recitation is already
          // waiting, so this answer is superseded before it could be drawn, and
          // only the last piece of a drain says where anybody is now.
          //
          // The catch-up drain at the start of a prayer is what this is for: up
          // to twenty seconds of audio, decoded in two or three, would
          // otherwise walk the cursor through the whole recitation faster than
          // it was ever said — and `PrayerScreen._onTheMove` reads a second
          // move arriving inside the dwell as a reciter running on, so the page
          // would flip through three ayas in under a second in front of
          // somebody praying. Nothing is dropped: every sample still reaches
          // the recogniser and its answers accumulate. Only the intermediate
          // cursor positions are discarded, which is what `moveTo` does with
          // them anyway when the next one arrives in the same frame.
          if (batch.length - to + _waiting.length >= _slice) continue;
          // The same words as last time are the same question as last time, and
          // it has already been answered. A reader who stops reciting leaves the
          // answer standing, and re-judging it forty times a second neither
          // changes it nor stops being work.
          //
          // Except that a reciter holding a long vowel is still being heard,
          // and the pace must not take a held madd for a reciter it has lost.
          // See [stillHeard] for how long that is believed.
          if (heard == _lastHeard) {
            final since = DateTime.now().difference(_lastFound);
            if (stillHeard(sure: _lastSure, peak: peak, since: since)) {
              onRecognised?.call();
            }
            continue;
          }
          _lastHeard = heard;
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
          _lastSure = at != null && at.score >= followSure;
          if (at == null || (_opening && !_opens(at.word, heard))) continue;
          _opening = false;
          final word = _onScreen(at.word);
          if (word != null) _cursor.moveTo(word, sure: _lastSure);
          matched.value = _tail(heard);
          if (_lastSure) {
            _lastFound = DateTime.now();
            onRecognised?.call();
          }
        }
      }
    } on Object {
      // Silence. The reader taps, as they always could.
    } finally {
      _handing = false;
    }
  }

  /// Drives the drain from a test: audio in, this class's own loop over it, and
  /// the voice back to read [matched] and the cursor off.
  ///
  /// The only way in. `FakeMic` cannot carry a stream, so a test that went
  /// through [start] would never produce a single batch — and what wants a test
  /// is in here: the slicing, the level gate that has to refuse a lead-in batch
  /// by batch, the promise that nothing between the reader's first word and the
  /// end is dropped, and the order of the two lines that build a window out of
  /// the carry.
  @visibleForTesting
  static Future<PrayerVoice> drain(
    PrayerCursor cursor,
    List<String> words,
    Float32List audio, {
    required Future<({String text, bool ended})> Function(Float32List) hear,
    int unseenAt = -1,
  }) async {
    final voice = PrayerVoice._(
      cursor,
      Recitation(words),
      AudioRecorder(),
      PrayerTrail.none(),
      unseenAt,
    ).._hear = hear;
    await voice.feed(audio);
    return voice;
  }

  /// More audio through the same drain, for a test that has [follow]ed the
  /// voice on to another rakʿah since [drain].
  @visibleForTesting
  Future<void> feed(Float32List audio) async {
    _waiting.addAll(audio);
    await _handOver();
  }

  /// Points the voice at the next rakʿah, without closing the microphone or
  /// the model. The rakʿah is begun only by its own opening (see [_opening]):
  /// the cursor stays where it is until then, and the screen begins the
  /// rakʿah when it moves.
  ///
  /// What was carried, what was last heard and the reader's hold all belonged
  /// to the rakʿah just finished, and an answer still being decoded is
  /// dropped when it lands. The audio waiting is kept: the recogniser hears a
  /// stream, and a gap cut into it costs the words on either side.
  void follow(PrayerCursor cursor, List<String> words, {int unseenAt = -1}) {
    _cursor = cursor;
    _set = Recitation(words);
    _unseenAt = unseenAt;
    _opening = true;
    _generation++;
    _carried = '';
    _lastHeard = '';
    _lastSure = false;
    _lastFound = DateTime.fromMillisecondsSinceEpoch(0);
    _theirs = DateTime.fromMillisecondsSinceEpoch(0);
  }

  /// The rakʿah is under way without the voice having heard it begin: the
  /// reader tapped it on, or the model loaded after it had started. Waiting
  /// for Al-Fātiḥa's opening then would wait for words already said, and the
  /// voice would follow nothing for the rest of the rakʿah.
  void begun() => _opening = false;

  /// Whether [word], heard surely in [heard], is the reader beginning
  /// Al-Fātiḥa: a full window, landing inside its first two ayas.
  bool _opens(int word, String heard) {
    var letters = 0;
    for (final w in heard.split(RegExp(r'\s+'))) {
      letters += recitationKey(w).length;
    }
    return _lastSure && letters >= heardTailLetters && word < openingWords;
  }

  /// Where [heard], a word of [_set], stands on the screen: the same place
  /// before the unseen basmala, that many words earlier after it, and nowhere
  /// inside it — the reciter is saying it, and there is nothing to light.
  int? _onScreen(int heard) {
    if (_unseenAt < 0 || heard < _unseenAt) return heard;
    final unseen = _set.words.length - _cursor.words;
    return heard < _unseenAt + unseen ? null : heard - unseen;
  }

  /// The reader moved the prayer themselves. Their hand wins for a moment,
  /// long enough for what they were reciting to leave the window.
  void hold() => _theirs = DateTime.now().add(heardHeldByHand);

  static String _tail(String heard) =>
      heard.length > 40 ? heard.substring(heard.length - 40) : heard;

  static String _verdict(
    ({int word, double score, double needed, double rival, double margin})?
    said,
    ({int word, double score})? at,
  ) {
    if (said == null) return 'too little heard';
    final where = 'word ${said.word} at ${said.score.toStringAsFixed(2)}';
    if (at != null) return 'MOVE to $where';
    if (said.score < said.needed) {
      return 'stay: $where under ${said.needed.toStringAsFixed(2)}';
    }
    return 'stay: $where but elsewhere ${said.rival.toStringAsFixed(2)}, '
        'margin ${said.margin.toStringAsFixed(2)} — said twice';
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
    _hear = null;
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
