import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wird/features/prayer/prayer_cursor.dart';
import 'package:wird/features/prayer/prayer_screen.dart';
import 'package:wird/theme/nocturne.dart';

import 'corpus.dart';
import 'features/prayer/sets.dart';
import 'fonts.dart';

Future<void> _heldOpen({required bool enable}) async {}

void main() {
  late Database db;

  setUpAll(loadBundledFonts);
  setUp(() async {
    db = await testCorpus();
  });

  testWidgets('screen 1b drifts away from the design in a way no behaviour '
      'test can see: type, spacing, or the layout of the prayer', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: nocturneTheme(),
        home: PrayerScreen(
          db: db,
          set: await alAsr(db),
          // The design's own frame: the third word of 103:2 being recited,
          // the second time through the set. Nothing on this screen animates,
          // and the cursor is pinned, so the frame is the same every run.
          cursor: PrayerCursor(14, position: 17),
          wakelock: _heldOpen,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(PrayerScreen),
      matchesGoldenFile('goldens/prayer.png'),
    );
  });
}
