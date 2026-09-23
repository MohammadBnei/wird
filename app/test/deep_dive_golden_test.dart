import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:wird/data/kept_repo.dart';
import 'package:wird/features/deepdive/deep_dive_screen.dart';
import 'package:wird/theme/nocturne.dart';

import 'corpus.dart';
import 'fonts.dart';

/// 103:3 and ṣ-b-r — the aya and the root the design drew this screen around.
const ayaOfPatience = 103003;
const patience = 'صبر';

void main() {
  late Database db;

  setUpAll(loadBundledFonts);
  setUp(() async {
    db = await testCorpus();
    await ensureKeptTable(db);
    await db.delete('kept_items');
  });

  testWidgets('screen 1c drifts away from the design in a way no behaviour '
      'test can see: the aya beside its iʿrāb, the constellation between the '
      'rails, or the sources down the right', (tester) async {
    // The design's own frame, which the iPad Pro 11-inch in landscape is the
    // nearest real device to.
    tester.view.physicalSize = const Size(1180, 794);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: nocturneTheme(),
        home: DeepDiveScreen(
          db: db,
          ayahId: ayaOfPatience,
          letters: patience,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(DeepDiveScreen),
      matchesGoldenFile('goldens/deep_dive.png'),
    );
  });
}
