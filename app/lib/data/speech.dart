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
/// is a hundred and sixty. A reader who never turns voice-follow on pays
/// nothing for it: no bundle weight, no background download, no request the
/// first launch makes on its own. The download is offered in Settings, with
/// its size printed, and it can be stopped and picked up again.
///
/// Nothing said into the microphone leaves the phone. The whole reason for a
/// model on disk is that the alternative is streaming somebody's prayer to a
/// server.

/// whisper-base fine-tuned on tarteel-ai/everyayah — the same corpus the app's
/// own reference recitation comes from — exported to ONNX and quantised to
/// int8, which is what these three files are. See ADR 0005 for the export and
/// the numbers behind choosing base over tiny.
const voiceModelParts = [
  'quran-encoder.int8.onnx',
  'quran-decoder.int8.onnx',
  'quran-tokens.txt',
];

/// What the reader is told before they agree to it. Read off the exported
/// files: 29.1 MB of encoder, 130.7 MB of decoder, 0.8 MB of tokens.
const voiceModelBytes = 160 * 1000 * 1000;

/// Where the three files are published: Wird's own host, which answers a phone
/// that has never signed in and hands it on to the store. `/models/` on
/// wird-api mints a short-lived signed URL and answers 302, so the bytes go
/// phone-to-store and never cross the API. ADR 0007 has the reasoning.
///
/// **A path, never a URL.** A signed URL expires, and a reader may press
/// Download, put the phone in a pocket for a week, and resume. Holding the
/// path means every resume re-asks and is handed a fresh signature, so an
/// expiry is not a thing this side has to think about.
///
/// The last path segment is a digest of the three files' own digests. A
/// re-export with different weights cannot land on the key a half-finished
/// download is resuming against — two int8 halves that disagree load without
/// complaint and transcribe nothing, which is a thing to debug once.
///
/// Moving it costs a release. There is no server override — saying there was
/// one is how this stayed pointed for a fortnight at a host where the three
/// files answered 401 and nothing had ever been uploaded.
const defaultVoiceModelOrigin =
    'https://wird.bnei.dev/models/base-ar-quran/38853d7df20b/';

/// How much recitation the recogniser is asked about at once, and how often.
///
/// A four-second window costs a median of 346 ms on an M-series laptop at two
/// threads, 456 ms at its worst over twenty windows of Ḥuṣarī. A phone is the
/// same order and slower, and a prayer runs for many minutes, so the hop is
/// not a fixed number: [heardHop] is the floor, and the driver waits at least
/// as long again as the last window took. That holds the recogniser under half
/// the time whatever the phone turns out to be, which is the ceiling on the
/// heat rather than a guess about it.
const heardWindow = Duration(seconds: 4);
const heardHop = Duration(milliseconds: 1200);
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

  /// Takes the model off the phone. The reader gets their disk back and the
  /// prayer screen goes back to the tap it never stopped answering.
  Future<void> remove() async {
    if (dir.existsSync()) await dir.delete(recursive: true);
  }
}

/// The recogniser, on an isolate of its own.
///
/// A window of recitation costs a fraction of a second of CPU. Spending that
/// on the isolate that draws the prayer would freeze the screen, and the
/// screen has to keep answering a thumb — the tap is the fallback for every
/// window this refuses to be sure about.
class Recogniser {
  Recogniser._(this._isolate, this._to, this._from);

  final Isolate _isolate;
  final SendPort _to;
  final ReceivePort _from;
  Completer<String>? _pending;

  /// Null when the model is missing or the platform will not load it. Every
  /// caller treats that as "the reader taps", which is what they did before.
  static Future<Recogniser?> open(VoiceModel model) async {
    if (!model.ready) return null;
    final from = ReceivePort();
    try {
      final isolate = await Isolate.spawn(_serve, (
        from.sendPort,
        model.fileFor(voiceModelParts[0]).path,
        model.fileFor(voiceModelParts[1]).path,
        model.fileFor(voiceModelParts[2]).path,
      ));
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
      from.close();
      return null;
    }
  }

  void _listen() {
    _from.listen((message) {
      final waiting = _pending;
      _pending = null;
      if (waiting != null && !waiting.isCompleted) {
        waiting.complete(message is String ? message : '');
      }
    });
  }

  /// Whether a window is still being worked on. A caller drops its window
  /// rather than queueing behind this one.
  bool get busy => _pending != null;

  /// What the recogniser made of one window, or the empty string when it could
  /// not be asked. It never throws: this is called from inside a prayer.
  Future<String> hear(Float32List samples) {
    if (_pending != null) return Future.value('');
    final answer = _pending = Completer<String>();
    try {
      _to.send(samples);
    } on Object {
      _pending = null;
      return Future.value('');
    }
    return answer.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        _pending = null;
        return '';
      },
    );
  }

  /// Ends the listening and gives the model back.
  ///
  /// The isolate is asked to stop and waited for rather than killed where it
  /// stands, because killing reclaims only its Dart heap and the model is 160
  /// MB that onnxruntime malloc'd. A prayer is left five times a day.
  Future<void> close() {
    _pending = null;
    _from.close();
    return stopIsolate(_isolate, _to);
  }
}

/// The isolate: builds the recogniser once, answers windows until it is sent
/// anything that is not one, and frees the model on the way out. The stream a
/// window is decoded on is native memory too, and is freed per window.
Future<void> _serve((SendPort, String, String, String) args) async {
  final (home, encoder, decoder, tokens) = args;
  final inbox = ReceivePort();
  home.send(inbox.sendPort);

  sherpa.initBindings();
  final recogniser = sherpa.OfflineRecognizer(
    sherpa.OfflineRecognizerConfig(
      model: sherpa.OfflineModelConfig(
        whisper: sherpa.OfflineWhisperModelConfig(
          encoder: encoder,
          decoder: decoder,
          // The reciter is reading classical Arabic aloud, and never asking
          // for a translation.
          language: 'ar',
          task: 'transcribe',
        ),
        tokens: tokens,
        modelType: 'whisper',
        numThreads: 2,
      ),
    ),
  );

  SendPort? replies;
  await for (final message in inbox) {
    if (message is SendPort) {
      replies = message;
      continue;
    }
    if (message is! Float32List) break;
    var text = '';
    try {
      final stream = recogniser.createStream();
      stream.acceptWaveform(samples: message, sampleRate: heardSampleRate);
      recogniser.decode(stream);
      text = recogniser.getResult(stream).text;
      stream.free();
    } on Object {
      text = '';
    }
    replies?.send(text);
  }
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
