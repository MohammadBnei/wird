import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wird/data/speech.dart';

/// A host that serves the three model files, honours a byte range, and can be
/// told to cut the connection partway through.
///
/// A raw socket rather than an HttpServer, and a real one rather than a mock:
/// what is under test is what happens to the bytes on disk when a download
/// dies mid-flight, and an HttpServer will not let a response be cut short.
class ModelHost {
  ModelHost(this._server, {required this.size}) {
    unawaited(_serve());
  }

  static Future<ModelHost> start({int size = 4096}) async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    return ModelHost(server, size: size);
  }

  final ServerSocket _server;
  final int size;

  /// Bytes to send before hanging up. Null serves the whole file.
  int? cutAfter;

  /// A status to answer with instead of the file, the way a host that has
  /// never been given the model answers for it.
  int? refuse;

  /// What this host calls the object it is serving. A store that swaps the
  /// object changes it, which is the only way a resuming client can tell.
  String etag = '"one"';

  /// The If-Range of every request, so a test can prove a resume names the
  /// object it started against rather than trusting the byte count.
  final ifRanges = <String?>[];

  /// The range header of every request, so a test can prove the second attempt
  /// asked for the rest rather than for the whole file again.
  final ranges = <String?>[];

  String get origin => 'http://${_server.address.host}:${_server.port}/';

  Future<void> _serve() async {
    await for (final socket in _server) {
      unawaited(_answer(socket));
    }
  }

  Future<void> _answer(Socket socket) async {
    try {
      final head = String.fromCharCodes(await socket.first);
      final range = head
          .split('\r\n')
          .where((line) => line.toLowerCase().startsWith('range:'))
          .firstOrNull;
      ranges.add(range?.split(':').last.trim());
      final ifRange = head
          .split('\r\n')
          .where((line) => line.toLowerCase().startsWith('if-range:'))
          .firstOrNull;
      ifRanges.add(ifRange?.split(':').sublist(1).join(':').trim());
      final refused = refuse;
      if (refused != null) {
        socket.write(
          'HTTP/1.1 $refused Unauthorized\r\n'
          'Content-Length: 0\r\n'
          'Connection: close\r\n\r\n',
        );
        await socket.flush();
        socket.destroy();
        return;
      }
      // A store honours a range only while the object is the one the client
      // started against. If-Range naming anything else means the whole file,
      // which is what stops two halves being spliced together.
      final stale =
          ifRanges.last != null && ifRanges.last != etag;
      final from = range == null || stale
          ? 0
          : int.parse(range.split('=')[1].split('-')[0]);
      final body = List<int>.filled(size - from, 7);
      final stop = cutAfter;
      final sent = stop == null || stop >= body.length
          ? body
          : body.sublist(0, stop);
      socket.write(
        'HTTP/1.1 ${from > 0 ? '206 Partial Content' : '200 OK'}\r\n'
        'ETag: $etag\r\n'
        'Content-Length: ${body.length}\r\n'
        'Connection: close\r\n\r\n',
      );
      socket.add(sent);
      await socket.flush();
    } on Object {
      // A client that hung up first is not this host's problem.
    }
    socket.destroy();
  }

  Future<void> close() => _server.close();
}

/// Stands in for the recogniser's isolate: it holds something only it can give
/// back, and says so on the way out. The real one holds 160 MB of onnxruntime
/// and cannot be run here without the model on disk.
Future<void> _holder((SendPort, SendPort) args) async {
  final (home, freed) = args;
  final inbox = ReceivePort();
  home.send(inbox.sendPort);
  await for (final message in inbox) {
    if (message is! Float32List) break;
  }
  freed.send('freed');
  inbox.close();
}

void main() {
  late Directory dir;
  late ModelHost host;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('wird-voice');
    host = await ModelHost.start();
  });
  tearDown(() async {
    await host.close();
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  VoiceModel model() => VoiceModel(dir, origin: host.origin);

  test('the prayer never listens to half a model', () async {
    final voice = model();
    expect(voice.ready, isFalse);
    expect(await voice.fetch(), isNull);
    expect(voice.ready, isTrue);

    // One part gone is the whole model gone: a recogniser opened on a missing
    // decoder is a failure inside a prayer rather than before one.
    await voice.fileFor(voiceModelParts[1]).delete();
    expect(voice.ready, isFalse);
  });

  test('a download cut off on a train starts again from where it stopped, '
      'not from nothing', () async {
    host.cutAfter = 1000;
    final voice = model();
    expect(await voice.fetch(), VoiceModelTrouble.interrupted);
    expect(voice.ready, isFalse);
    expect(voice.bytesOnDisk, 1000, reason: 'what arrived is kept');

    host.cutAfter = null;
    host.ranges.clear();
    expect(await voice.fetch(), isNull);
    expect(
      host.ranges.first,
      'bytes=1000-',
      reason: 'the reader does not pay for the first thousand bytes twice',
    );
    expect(voice.fileFor(voiceModelParts[0]).lengthSync(), 4096);
  });

  // A resume sends a byte count, and a byte count cannot tell one object from
  // another. If the model is re-exported while a reader's download is half
  // done, continuing from byte 1000 of the NEW file splices two halves that
  // do not belong together — and two int8 halves that disagree load without
  // complaint and transcribe nothing, which is the same silent failure a
  // dynamo-exported graph gives.
  test('a model swapped under a half-finished download is spliced onto the '
      'half already on the phone', () async {
    host.cutAfter = 1000;
    final voice = model();
    expect(await voice.fetch(), VoiceModelTrouble.interrupted);
    expect(voice.bytesOnDisk, 1000);

    // The store now holds a different object under the same name.
    host.etag = '"two"';
    host.cutAfter = null;
    host.ranges.clear();
    host.ifRanges.clear();

    expect(await voice.fetch(), isNull);
    expect(
      host.ifRanges.first,
      '"one"',
      reason: 'the resume did not name the object it started against',
    );
    expect(
      voice.fileFor(voiceModelParts[0]).lengthSync(),
      4096,
      reason: 'a whole file, not 1000 bytes of one model and 3096 of another',
    );
  });

  test('the etag of a finished part is left on the phone forever', () async {
    final voice = model();
    expect(await voice.fetch(), isNull);
    for (final part in voiceModelParts) {
      expect(
        File('${voice.dir.path}/$part.etag').existsSync(),
        isFalse,
        reason: 'a scratch file outlives the download it was for',
      );
    }
  });

  test(
    'a reader who stops the download is not billed for the rest of it',
    () async {
      final voice = model();
      final cancel = CancelToken();
      final fetching = voice.fetch(cancel: cancel);
      cancel.cancel();
      expect(await fetching, VoiceModelTrouble.interrupted);
      expect(voice.ready, isFalse);
    },
  );

  test(
    'a model the reader removed does not sit on the phone forever',
    () async {
      final voice = model();
      expect(await voice.fetch(), isNull);
      expect(voice.ready, isTrue);
      await voice.remove();
      expect(voice.ready, isFalse);
      expect(voice.bytesOnDisk, 0);
    },
  );

  test(
    'a host that will not answer leaves Settings a sentence, not a crash',
    () async {
      final voice = VoiceModel(dir, origin: 'http://127.0.0.1:1/');
      expect(await voice.fetch(), VoiceModelTrouble.interrupted);
    },
  );

  test(
    'a model nobody has published is not handed to the reader as their own '
    'bad connection',
    () async {
      // What wird.bnei.dev/models/ answered for a fortnight: a host with no
      // such route, so the request fell through to the authenticator. A reader
      // told to check their signal would have checked it forever.
      host.refuse = 401;
      final voice = model();
      expect(await voice.fetch(), VoiceModelTrouble.notServed);
      expect(voice.bytesOnDisk, 0, reason: 'a refusal is not a part file');
    },
  );

  test('a prayer that ends kills the recogniser before it hands the model '
      'back', () async {
    final home = ReceivePort();
    final freed = ReceivePort();
    final isolate = await Isolate.spawn(_holder, (
      home.sendPort,
      freed.sendPort,
    ));
    final inbox = await home.first as SendPort;
    home.close();

    await stopIsolate(isolate, inbox);
    expect(
      await freed.first.timeout(const Duration(seconds: 2)),
      'freed',
      reason: 'killed with the whole model still malloc\'d, every prayer',
    );
    freed.close();
  });

  test('the microphone is heard as the numbers the recogniser wants', () {
    // Sixteen-bit little-endian: silence, full positive, full negative.
    final pcm = Uint8List.fromList([0, 0, 0xFF, 0x7F, 0x00, 0x80]);
    final samples = pcm16ToFloat(pcm);
    expect(samples.length, 3);
    expect(samples[0], 0);
    expect(samples[1], closeTo(1, 0.001));
    expect(samples[2], -1);
  });
}
