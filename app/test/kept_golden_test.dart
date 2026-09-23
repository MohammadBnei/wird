import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wird/data/kept_repo.dart';
import 'package:wird/features/kept/kept_screen.dart';
import 'package:wird/theme/nocturne.dart';

import 'corpus.dart';
import 'fonts.dart';

void main() {
  late Database db;

  setUpAll(loadBundledFonts);
  setUp(() async {
    db = await testCorpus();
    await ensureKeptTable(db);
    await db.delete('kept_items');
  });

  testWidgets('screen 1e drifts away from the design in a way no behaviour '
      'test can see: the search field, the filter, or the cards', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // The three kept ayas the design draws, oldest first so the list orders
    // them the way the screen was drawn.
    await keep(
      db,
      kind: KeptKind.aya,
      ayahId: 103002,
      body:
          'Ask: is خُسْر the loss itself, or the state of losing? Ṭabarī '
          'reads it as the ruin one is already inside.',
    );
    await keep(
      db,
      kind: KeptKind.aya,
      ayahId: 2153,
      rootLetters: 'صبر',
      body:
          'Same root, read 209 sets ago. Flagged when the constellation '
          'surfaced it.',
      tags: ['revisit'],
    );
    await keep(
      db,
      kind: KeptKind.aya,
      ayahId: 103003,
      body:
          'The form VI verb makes it mutual — not "be patient" but "bind '
          'each other to patience". Changes who the aya is addressed to.',
      tags: ['grammar'],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: nocturneTheme(),
        home: KeptScreen(db: db),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(KeptScreen),
      matchesGoldenFile('goldens/kept.png'),
    );
  });
}
