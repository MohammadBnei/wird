import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:dio/dio.dart';
// Transitive through flutter, and not worth a line in pubspec for one
// annotation.
// ignore: depend_on_referenced_packages
import 'package:meta/meta.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

/// The recogniser voice-follow listens with, and the download that fetches it.
///
/// RUNTIME FETCH, AND ONLY ON A READER'S WORD. The app is 27 MB and the model
/// is seventy-three. A reader who never turns voice-follow on pays
/// nothing for it: no bundle weight, no background download, no request the
/// first launch makes on its own. The download is offered in Settings, with
/// its size printed, and it can be stopped and picked up again.
///
/// Nothing said into the microphone leaves the phone. The whole reason for a
/// model on disk is that the alternative is streaming somebody's prayer to a
/// server.

/// A streaming zipformer CTC model over a Qur'anic phoneme alphabet, int8.
///
/// It writes what it hears in 251 symbols: Arabic letters, the three short
/// vowels, and the marks that carry gemination, madd and tajwīd. There is no
/// Latin letter in that alphabet and no second language behind it, which is
/// the whole reason it is here. The multilingual transducer it replaced chose
/// a language from the first sounds it was given, بِسْمِ ٱللَّهِ sounded Latin
/// enough to send it into English, and the choice lived in the stream's state
/// where nothing could argue it out again — the owner's screen showed `BIS`,
/// then `然后`, and did not move for the rest of the prayer.
///
/// Measured against that transducer on the owner's own recorded prayer, fed
/// in 300 ms chunks the way the app feeds it: this one follows al-Fātiḥa to
/// its last word, the transducer stalls three words short and stays there.
/// 14 ms per chunk against 24 ms, and a fifth of the bytes. ADR 0009.
const voiceModelParts = ['model.int8.onnx', 'tokens.txt'];

/// What the reader is told before they agree to it. Read off the published
/// files: 72.7 MB of weights and 2.3 kB of tokens.
const voiceModelBytes = 72707738;

/// Where the files are published: Wird's own host, which answers a phone that
/// has never signed in and hands it on to the store. `/models/` on wird-api
/// mints a short-lived signed URL and answers 302, so the bytes go
/// phone-to-store and never cross the API. ADR 0008 has the reasoning.
///
/// **A path, never a URL.** A signed URL expires, and a reader may press
/// Download, put the phone in a pocket for a week, and resume. Holding the
/// path means every resume re-asks and is handed a fresh signature, so an
/// expiry is not a thing this side has to think about.
///
/// The last path segment is a digest of the files' own digests. A re-export
/// with different weights cannot land on the key a half-finished download is
/// resuming against — weights and a token table that disagree load without
/// complaint and transcribe nothing, which is a thing to debug once.
///
/// Moving it costs a release. There is no server override — saying there was
/// one is how this stayed pointed for a fortnight at a host where the files
/// answered 401 and nothing had ever been uploaded.
const defaultVoiceModelOrigin =
    'https://wird.bnei.dev/models/ar-phoneme/54f7db6bdcff/';

/// How much recitation is handed over at a time.
///
/// There is no window any more and nothing is re-heard: audio goes in once, in
/// the order it arrived, and the answer grows. This is only how often the
/// microphone's bytes are passed along, and it is the floor on how late the
/// screen can be. A chunk costs 21 ms on an M-series laptop at two threads —
/// a realtime factor of 0.07 — so a phone several times slower still spends a
/// fraction of the prayer decoding it.
const heardChunk = Duration(milliseconds: 300);

/// How long the reader's own tap holds the prayer against the voice.
///
/// Long enough that the words they tapped past fall out of the matching
/// window, so the next answer describes where they now are rather than where
/// they were when they reached for the screen.
const heardHeldByHand = Duration(seconds: 4);

/// How loud a batch must be before the recogniser is asked about it.
///
/// A recogniser handed silence still answers, and what it invents out of a
/// quiet room is a phrase the matcher then has to refuse. The prayer screen
/// opens before the reader begins, so the quiet before the first word is
/// exactly what should not reach it — and there is more of it than there was,
/// because `PrayerVoice.start` now opens the microphone BEFORE loading the
/// model rather than after, to stop losing the opening of the recitation.
///
/// THE DECISION THAT ORDERING FORCES, so it is not found later in a commit
/// message. `prayer_screen_test.dart` asserts that a reader with permission and
/// no model gets no microphone, and says why in words: "opening the microphone
/// would be a recording nobody asked for". That still holds — [VoiceModel.ready]
/// is still checked before the recorder is built. But with the files PRESENT and
/// unloadable, which [Recogniser.open] below documents as a real case, the
/// microphone now runs for up to twenty seconds of a prayer and every sample of
/// it is thrown away. On Android the OS microphone indicator appears over the
/// prayer for those seconds, on a phone where voice-follow will never work.
/// Nothing leaves the device either way. The alternative is to open the
/// microphone only once the model has loaded and accept that the opening of the
/// recitation is lost, which is the second walk finding left unfixed.
///
/// ponytail: one fixed absolute floor, and it guards only the quiet *before*
/// the first word — the caller latches `_speaking` on and never turns it off,
/// so from the reader's first syllable every batch reaches the recogniser
/// whatever its level. That is deliberate. The two changes that look like
/// improvements on it are refused below, by measurement.
///
/// THREE SETS OF NUMBERS HAVE BEEN WRITTEN HERE AND ONLY ONE IS OF THIS PATH.
/// They disagree by a factor of twenty, which is why they are spelled out rather
/// than left as a constant nobody can re-derive:
///
/// - 0.4 reciting / 0.004 room. A voice memo, not this path. `voices_test.dart`
///   records why those are not the same signal: the memo and the app's own
///   microphone are the same phone and the same voice, and the recogniser makes
///   noticeably different work of them. Whatever a recorder app does to a memo,
///   this path is `autoGain: false`. WRONG SIGNAL.
/// - 0.10 to 0.17 reader / 0.03 to 0.05 room. Off the phone's own trail, but read
///   off the batches that trail happened to print — which are the ones that
///   PASSED this floor and were loud enough to be worth a line. Selected on the
///   quantity being measured. WRONG SAMPLE.
/// - 0.02 to 0.24 reader. Off that same trail, over every batch inside confirmed
///   recitation: 0.24, 0.15, 0.11, 0.10, 0.09, 0.08, 0.06, 0.05, 0.04, 0.03 and
///   0.02, the last three at 18.1s, 29.1s and 33.9s. This is the one that
///   survives — this path, and not selected.
///
/// So the reader's own recitation reaches down to this floor and the room reaches
/// up past it. The distributions overlap, and neither of these separates them:
///
/// - A ratio against a decaying peak of the reader's own loudness. Refused by
///   the distribution above: any ratio wide enough to keep the reader's 0.02
///   batches admits a room at 0.03 to 0.05, and any ratio tight enough to refuse
///   the room drops recitation.
/// - Re-arming this gate at `said.ended`, so the batch level is back in charge
///   instead of latching open. It drops recitation, twice over. `enableEndpoint:
///   true` leaves sherpa's three defaults in force, and rule 3 ends an utterance
///   at 20 s of speech — so endpoints fire mid-recitation, guaranteed, in any
///   longer passage, and the batch after one is usually not an utterance opening.
///   Re-arming discards the 0.02 batches listed above, which is the one thing
///   `prayer_voice.dart` forbids. It would also promote this from a lead-in guard
///   into a VAD threshold running the whole prayer, on the very data that proves
///   0.02 cannot tell reader from room.
///
/// A bystander is refused by the MATCHER, not by the level: a phoneme alphabet
/// cannot write English, so the room is transcribed as whatever Arabic it sounds
/// closest to and then scores badly. The walk's own wrong move — the cursor to
/// word 8 on a phrase nobody praying had said — was not this gate letting the
/// room in. It was the carried utterance holding the reader's last aya across two
/// empty endpoints, so the junk was scored with the reader's own recitation glued
/// to the front of it. `carry` in `prayer_voice.dart` is the fix for that.
///
/// The trail now prints the count and range of EVERY batch's peak once a
/// heartbeat, at three decimals, so the next argument about this number is had
/// against numbers from this path. It is printed from above the gate — a
/// microphone handing back zeros says so instead of going silent — and says
/// whether the reader has begun, because a range over a window holding both is
/// the defect all three sets above share.
const heardQuiet = 0.02;

/// How often the trail says something even when nothing has changed. A record
/// that goes quiet exactly when the thing it records goes quiet cannot be
/// read back.
const heardHeartbeat = Duration(seconds: 3);

const heardSampleRate = 16000;

/// Why a download stopped, in the two shapes that mean different things to the
/// reader. Nothing else about a failed fetch is worth a sentence.
enum VoiceModelTrouble {
  /// The origin answered, and not with the file: a 401 from a host with no
  /// such route, a 404 from one that has the route and is serving nothing.
  /// No phone can fix this and the reader must not be told to try.
  notServed,

  /// The bytes stopped arriving. A tunnel, a full disk, or the reader's own
  /// Stop — the panel holds the cancel token and knows which.
  interrupted,
}

/// The model on disk: whether it is there, and how to get it.
class VoiceModel {
  VoiceModel(this.dir, {this.origin = defaultVoiceModelOrigin, Dio? http})
    : _http = http ?? Dio();

  /// ponytail: beside the database and the audio cache, for the reason
  /// [AudioCache.beside] gives — path_provider is not in the stack table.
  static Future<VoiceModel> beside(String databasesPath, {String? origin}) {
    final dir = Directory('$databasesPath/voice');
    return dir
        .create(recursive: true)
        .then(
          (_) => VoiceModel(dir, origin: origin ?? defaultVoiceModelOrigin),
        );
  }

  final Directory dir;
  final String origin;
  final Dio _http;

  File fileFor(String part) => File('${dir.path}/$part');

  /// Every part present. A half-finished download is not a model, and the
  /// prayer screen asks this before it listens to anything.
  bool get ready => voiceModelParts.every((p) => fileFor(p).existsSync());

  /// How much of the download is already on disk, finished parts included.
  int get bytesOnDisk {
    var total = 0;
    for (final part in voiceModelParts) {
      for (final file in [fileFor(part), File('${dir.path}/$part.part')]) {
        if (file.existsSync()) total += file.lengthSync();
      }
    }
    return total;
  }

  /// Fetches whatever is missing, resuming a part that was interrupted.
  ///
  /// A stopped download leaves its `.part` file where it is, so the reader who
  /// lost signal on a train picks up from there rather than from nothing.
  ///
  /// Null once the model is on the phone, otherwise why it is not. It answers
  /// rather than throwing because the only caller is Settings, which says what
  /// happened in its own words — but it has to be told which thing happened,
  /// or the reader presses Download at a host that will never answer and the
  /// panel goes quiet as if they had mistyped their own wifi password.
  @useResult
  Future<VoiceModelTrouble?> fetch({
    void Function(int received, int total)? onProgress,
    CancelToken? cancel,
  }) async {
    sweepUpAfterAnOlderModel();
    var done = bytesOnDisk;
    try {
      for (final part in voiceModelParts) {
        if (fileFor(part).existsSync()) continue;
        final partial = File('${dir.path}/$part.part');
        final tagFile = File('${dir.path}/$part.etag');
        final from = partial.existsSync() ? partial.lengthSync() : 0;
        final heldTag = tagFile.existsSync() ? tagFile.readAsStringSync() : '';
        final response = await _http.get<ResponseBody>(
          '$origin$part',
          cancelToken: cancel,
          options: Options(
            responseType: ResponseType.stream,
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
            validateStatus: (code) => code == 200 || code == 206,
          ),
        );
        final append = response.statusCode == 206;
        final tag = response.headers.value('etag') ?? '';
        if (tag.isNotEmpty) tagFile.writeAsStringSync(tag);
        if (!append && from > 0) await partial.delete();
        done -= append ? 0 : from;
        final sink = partial.openSync(
          mode: append ? FileMode.append : FileMode.write,
        );
        try {
          await for (final chunk in response.data!.stream) {
            sink.writeFromSync(chunk);
            done += chunk.length;
            onProgress?.call(done, voiceModelBytes);
          }
        } finally {
          sink.closeSync();
        }
        await partial.rename(fileFor(part).path);
        if (tagFile.existsSync()) tagFile.deleteSync();
      }
      return ready ? null : VoiceModelTrouble.interrupted;
    } on DioException catch (failure) {
      return failure.type == DioExceptionType.badResponse
          ? VoiceModelTrouble.notServed
          : VoiceModelTrouble.interrupted;
    } on Object {
      return VoiceModelTrouble.interrupted;
    }
  }

  /// Throws away anything in the model's directory that this build does not
  /// ask for.
  ///
  /// A phone that downloaded a previous recogniser keeps its files forever
  /// otherwise: they are not [voiceModelParts] any more, so [ready] ignores
  /// them, nothing offers to remove them, and the reader pays for them in disk
  /// they cannot see. The transducer this replaced was 339 MB of exactly that.
  ///
  /// Only this directory, and only names this build has no use for — the
  /// parts, and the `.part` and `.etag` a resume of them is holding. Never
  /// throws: a reader who cannot be tidied up after still gets their
  /// download.
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

  /// Takes the model off the phone. The reader gets their disk back and the
  /// prayer screen goes back to the tap it never stopped answering.
  Future<void> remove() async {
    if (dir.existsSync()) await dir.delete(recursive: true);
  }
}

/// The recogniser, on an isolate of its own.
///
/// Decoding costs a fraction of a second of CPU per chunk. Spending that on
/// the isolate that draws the prayer would freeze the screen, and the screen
/// has to keep answering a thumb — the tap is the fallback for every chunk
/// this refuses to be sure about, and for every phone that cannot load this
/// at all.
///
/// One stream lives for the length of the prayer. Audio is handed over once,
/// in the order it arrived, and what comes back is everything heard so far
/// rather than an opinion about the last few seconds. Nothing is re-heard, so
/// nothing can be heard differently the second time.
class Recogniser {
  Recogniser._(this._isolate, this._to, this._from);

  final Isolate _isolate;
  final SendPort _to;
  final ReceivePort _from;
  Completer<({String text, bool ended})>? _pending;

  /// Null when the model is missing or the platform will not load it. Every
  /// caller treats that as "the reader taps", which is what they did before,
  /// and the prayer screen says IN PRAYER rather than claiming to listen.
  ///
  /// Files of the right names and the wrong bytes — a download the phone
  /// truncated — are enough to pass [VoiceModel.ready], so whether the model
  /// loads is only knowable from inside the isolate. The isolate
  /// therefore says nothing until its recogniser is built, and a build that
  /// throws arrives here as the isolate's death instead: `onExit`/`onError`
  /// put that on the same port, and anything that is not the inbox is a
  /// failure to open rather than a recogniser that hears nothing.
  static Future<Recogniser?> open(VoiceModel model) async {
    if (!model.ready) return null;
    final from = ReceivePort();
    // Held outside the try because the isolate answers only once the model is
    // loaded, so the timeout below is reachable on a slow phone and would
    // otherwise abandon a live isolate holding it.
    Isolate? isolate;
    try {
      isolate = await Isolate.spawn(
        _serve,
        (
          from.sendPort,
          model.fileFor(voiceModelParts[0]).path,
          model.fileFor(voiceModelParts[1]).path,
        ),
        onExit: from.sendPort,
        onError: from.sendPort,
      );
      final first = await from.first.timeout(const Duration(seconds: 20));
      if (first is! SendPort) {
        isolate.kill(priority: Isolate.immediate);
        from.close();
        return null;
      }
      // `from.first` consumed the subscription, so listening again needs a
      // second port; the isolate is told about it with its first message.
      final replies = ReceivePort();
      first.send(replies.sendPort);
      return Recogniser._(isolate, first, replies).._listen();
    } on Object {
      isolate?.kill(priority: Isolate.immediate);
      from.close();
      return null;
    }
  }

  void _listen() {
    _from.listen((message) {
      final waiting = _pending;
      _pending = null;
      if (waiting == null || waiting.isCompleted) return;
      waiting.complete(
        message is List && message.length == 2
            ? (text: message[0] as String, ended: message[1] as bool)
            : (text: '', ended: false),
      );
    });
  }

  /// Whether a window is still being worked on. A caller drops its window
  /// rather than queueing behind this one.
  bool get busy => _pending != null;

  /// Everything heard so far, once these samples have been taken in, or the
  /// empty string when it could not be asked. It never throws: this is called
  /// from inside a prayer.
  ///
  /// Audio handed over while a previous chunk is still being decoded would be
  /// lost, and a transducer that misses a second of speech misses the words in
  /// it for good — unlike the window this replaced, where a dropped ask cost
  /// nothing because the next one asked about the same seconds again. The
  /// caller holds what it cannot hand over yet.
  Future<({String text, bool ended})> hear(Float32List samples) {
    const nothing = (text: '', ended: false);
    if (_pending != null) return Future.value(nothing);
    final answer = _pending = Completer<({String text, bool ended})>();
    try {
      _to.send(samples);
    } on Object {
      _pending = null;
      return Future.value(nothing);
    }
    return answer.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        _pending = null;
        return nothing;
      },
    );
  }

  /// Ends the listening and gives the model back.
  ///
  /// The isolate is asked to stop and waited for rather than killed where it
  /// stands, because killing reclaims only its Dart heap and the weights are
  /// what onnxruntime malloc'd. A prayer is left five times a day.
  Future<void> close() {
    _pending = null;
    _from.close();
    return stopIsolate(_isolate, _to);
  }
}

/// The isolate: builds the recogniser once, answers windows until it is sent
/// anything that is not one, and frees the model on the way out. The stream a
/// window is decoded on is native memory too, and is freed per window.
///
/// The inbox is handed back only once the recogniser stands. Announcing it
/// first would mean a model that cannot load still answers every window with
/// the empty string, and [Recogniser.open] would hand the prayer screen a
/// recogniser to print FOLLOWING YOUR VOICE about.
Future<void> _serve((SendPort, String, String) args) async {
  final (home, model, tokens) = args;

  sherpa.initBindings();
  final recogniser = sherpa.OnlineRecognizer(
    sherpa.OnlineRecognizerConfig(
      model: sherpa.OnlineModelConfig(
        zipformer2Ctc: sherpa.OnlineZipformer2CtcModelConfig(model: model),
        tokens: tokens,
        numThreads: 2,
      ),
      // Let the recogniser end an utterance at a pause, and keep the words
      // here rather than in its stream.
      //
      // CTC has no prediction network, so a long stream does not bias itself
      // the way the transducer here before it did — the owner recited
      // al-Fātiḥa, moved to az-Zalzalah, and had to repeat himself while two
      // minutes of the previous sūra argued against him. Endpointing stays on
      // regardless: the matcher reads the tail of everything said and that has
      // to survive a breath between ayas, which is done below in a string this
      // side owns rather than in decoder state.
      enableEndpoint: true,
    ),
  );
  final stream = recogniser.createStream();

  final inbox = ReceivePort();
  home.send(inbox.sendPort);

  SendPort? replies;
  await for (final message in inbox) {
    if (message is SendPort) {
      replies = message;
      continue;
    }
    if (message is! Float32List) break;
    var text = '';
    var ended = false;
    try {
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
    } on Object {
      text = '';
    }
    replies?.send([text, ended]);
  }
  stream.free();
  recogniser.free();
  inbox.close();
}

/// Ends an isolate by asking it to unwind, so that the native memory it holds
/// is freed by the isolate itself. [Isolate.kill] reclaims only the Dart heap.
///
/// Anything that is not a window of samples is the word to stop on. An isolate
/// still wedged after [wait] is killed regardless: on the way out of a prayer,
/// leaking beats hanging.
Future<void> stopIsolate(
  Isolate isolate,
  SendPort to, {
  Duration wait = const Duration(seconds: 2),
}) async {
  final gone = ReceivePort();
  isolate.addOnExitListener(gone.sendPort);
  try {
    to.send(null);
    await gone.first.timeout(wait);
  } on Object {
    // The kill below is the whole of what is left to do about it.
  }
  gone.close();
  isolate.kill(priority: Isolate.immediate);
}

/// Sixteen-bit little-endian PCM, which is what the microphone hands over, as
/// the floats the recogniser wants.
Float32List pcm16ToFloat(Uint8List bytes) {
  final samples = Float32List(bytes.length ~/ 2);
  final view = ByteData.view(bytes.buffer, bytes.offsetInBytes, bytes.length);
  for (var i = 0; i < samples.length; i++) {
    samples[i] = view.getInt16(i * 2, Endian.little) / 32768.0;
  }
  return samples;
}
