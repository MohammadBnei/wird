import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wird/data/db.dart';
import 'package:wird/features/progress/progress_screen.dart';
import 'package:wird/theme/nocturne.dart';

import 'corpus.dart';
import 'fonts.dart';

void main() {
  late Database db;

  setUpAll(loadBundledFonts);
  setUp(() async => db = await testCorpus());

  testWidgets('screen 1d drifts away from the design in a way no behaviour '
      'test can see: the ring, the tiles, or the sūra rows', (tester) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // The reader the design draws: a sūra finished, one well into, and a set
    // part-read — so the ring has full, partial and untouched arcs on it.
    await markSetUnderstood(db, newOpId(), [
      for (var n = 1; n <= 7; n++) 1000 + n,
      for (var n = 1; n <= 171; n++) 2000 + n,
      103001,
      103002,
    ]);

    await tester.pumpWidget(
      MaterialApp(
        theme: nocturneTheme(),
        home: ProgressScreen(db: db),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(ProgressScreen),
      matchesGoldenFile('goldens/progress.png'),
    );
  });
}
