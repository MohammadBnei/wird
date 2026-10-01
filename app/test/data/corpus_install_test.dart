import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wird/data/db.dart';

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('wird_corpus'));
  tearDown(() => dir.deleteSync(recursive: true));

  final corpus = Uint8List.fromList(List.filled(4096, 7));

  test('the corpus is written straight to the path the app opens, so a write '
      'that dies partway leaves a truncated database there and every later '
      'launch opens it', () async {
    final target = File('${dir.path}/wird.db');

    // The write has to go somewhere other than the destination, and this is
    // the only way to observe that from outside: block the scratch path, and
    // a write that uses it fails with the destination untouched. A write that
    // goes straight to the destination does not notice and lands there.
    Directory('${target.path}.part').createSync();

    await expectLater(installCorpus(target, corpus), throwsA(isA<Object>()));

    expect(
      target.existsSync(),
      isFalse,
      reason: 'a failed copy put bytes at the destination, and openWird asks '
          'only whether the destination exists',
    );
  });

  test('a copy that finishes leaves its scratch file behind, so the 24 MB is '
      'paid for again on the next launch', () async {
    final target = File('${dir.path}/wird.db');
    await installCorpus(target, corpus);

    expect(target.readAsBytesSync(), corpus);
    expect(File('${target.path}.part').existsSync(), isFalse);
  });
}
