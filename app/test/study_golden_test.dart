import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wird/features/study/study_screen.dart';
import 'package:wird/theme/nocturne.dart';

import 'corpus.dart';
import 'fonts.dart';

void main() {
  late Database db;

  setUpAll(loadBundledFonts);
  // Opening the corpus is real file work, which never completes inside the
  // fake-async zone a widget test body runs in.
  setUp(() async => db = await testCorpus());

  testWidgets('screen 1a drifts away from the design in a way no behaviour '
      'test can see: type, spacing, or the layout of the set', (tester) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(theme: nocturneTheme(), home: StudyScreen(db: db)),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(StudyScreen),
      matchesGoldenFile('goldens/study.png'),
    );
  });
}
