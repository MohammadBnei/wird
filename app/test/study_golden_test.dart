import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wird/data/audio.dart';
import 'package:wird/features/study/study_screen.dart';

import 'corpus.dart';
import 'fonts.dart';
import 'offline.dart';
import 'wird.dart';

void main() {
  late Database db;
  late AudioCache audio;

  setUpAll(loadBundledFonts);
  // Opening the corpus and making the cache directory are real file work,
  // which never completes inside the fake-async zone a widget test body runs
  // in.
  setUp(() async {
    db = await testCorpus();
    audio = await emptyCache();
  });

  testWidgets('screen 1a drifts away from the design in a way no behaviour '
      'test can see: type, spacing, or the layout of the set', (tester) async {
    // No recitation on disk and no network: the golden captures the screen a
    // phone shows before anything has been downloaded.
    await pumpPhone(tester, await wirdAround(db, StudyScreen(db: db), cache: audio));

    await expectLater(
      find.byType(StudyScreen),
      matchesGoldenFile('goldens/study.png'),
    );
  });
}
