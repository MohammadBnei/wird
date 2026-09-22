import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wird/data/audio.dart';
import 'package:wird/features/study/study_screen.dart';
import 'package:wird/theme/nocturne.dart';

import 'corpus.dart';
import 'fonts.dart';
import 'offline.dart';

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
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: nocturneTheme(),
        // No recitation on disk and no network: the golden captures the
        // screen a phone shows before anything has been downloaded.
        home: StudyScreen(db: db, audioCache: audio),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(StudyScreen),
      matchesGoldenFile('goldens/study.png'),
    );
  });
}
