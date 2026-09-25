import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wird/data/speech.dart';
import 'package:wird/features/settings/voice_check.dart';

import '../../corpus.dart';
import '../../fonts.dart';
import '../../wird.dart';

void main() {
  late Database db;

  setUpAll(loadBundledFonts);
  setUp(() async => db = await testCorpus());

  // The screen that exists to say why voice-follow is not working cannot be
  // the thing that fails: it shipped naming two colours the theme does not
  // have, `color()` force-unwraps, and the reader who tapped Check the
  // recogniser was handed a grey rectangle. Nothing rendered it before a
  // phone did.
  testWidgets('the screen that explains the silence is itself silent', (
    tester,
  ) async {
    await pumpPhone(
      tester,
      await wirdAround(
        db,
        VoiceCheck(
          model: VoiceModel(
            Directory('${Directory.systemTemp.path}/wird-voice-unwritten'),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('recogniser'), findsWidgets);
  });
}
