import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wird/features/prayer/prepare_screen.dart';
import 'package:wird/l10n/app_localizations.dart';
import 'package:wird/theme/nocturne.dart';

import 'corpus.dart';
import 'features/prayer/sets.dart';
import 'fonts.dart';

void main() {
  late Database db;

  setUpAll(loadBundledFonts);
  setUp(() async {
    db = await testCorpus();
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: nocturneTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: PrepareScreen(db: db, from: await alAsr(db)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the prayer is prepared on a screen that drifts from the design '
      'in a way no behaviour test can see', (tester) async {
    await pump(tester);
    await expectLater(
      find.byType(PrepareScreen),
      matchesGoldenFile('goldens/prepare.png'),
    );
  });

  testWidgets('a passage is chosen from a list and a range that drift from '
      'the design', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('passage 1')));
    await tester.pumpAndSettle();
    // The chooser opens on the passage's own range; the list is a step back.
    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/chooser.png'),
    );
    await tester.enterText(find.byType(TextField), '2:255');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Go to Al-Baqarah 2:255'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/chooser_range.png'),
    );
  });
}
