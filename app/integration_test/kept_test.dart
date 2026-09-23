import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:wird/data/kept_repo.dart';
import 'package:wird/features/kept/kept_screen.dart';
import 'package:wird/features/progress/progress_screen.dart';

import 'journey.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  journey(
    'keeps an aya and finds it again',
    body: (tester) async {
      await launchFresh(tester);
      final corpus = await openCorpusBeside();

      // Nothing on any built screen keeps an aya yet — the bookmark on 1a
      // leads nowhere by design decision, and the keep icon lives on the root
      // screens. The journey keeps the way those screens will, through the
      // repository, and then proves the reader can find it by hand.
      final ayahId = ayasOnScreen(tester).reduce((a, b) => a < b ? a : b);
      await keep(
        await _writable(),
        kind: KeptKind.aya,
        ayahId: ayahId,
        body: 'the first aya I understood',
      );

      await _openSettings(tester);
      await tester.tap(find.text('Kept'));
      await tester.pumpAndSettle();
      expect(find.byType(KeptScreen), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'first aya');
      await tester.pumpAndSettle();
      expect(
        find.textContaining('the first aya I understood'),
        findsOneWidget,
        reason:
            'the reader kept an aya and then searched for their own words '
            'about it, and the kept list handed back nothing',
      );

      final aya = await corpus.query(
        'ayahs',
        columns: ['text_uthmani'],
        where: 'id = ?',
        whereArgs: [ayahId],
      );
      expect(
        find.text(aya.single['text_uthmani']! as String),
        findsOneWidget,
        reason:
            'the card names the aya but does not carry it, so the reader '
            'cannot tell which one they kept',
      );

      expectNoSpinnerAndNoApology(tester, 'on the kept list');
    },
  );

  journey(
    'counts a set understood on the passage',
    body: (tester) async {
      await launchFresh(tester);
      final before = ayasOnScreen(tester);

      await tester.tap(markSetUnderstood(tester));
      await waitFor(
        tester,
        () => ayasOnScreen(tester).intersection(before).isEmpty,
        'the next set',
      );

      await _openSettings(tester);
      await tester.tap(find.text('Your passage'));
      await tester.pumpAndSettle();
      expect(find.byType(ProgressScreen), findsOneWidget);

      // The ring paints its own numbers, so they are read where a reader who
      // cannot see them reads them.
      final semantics = tester.ensureSemantics();
      expect(
        find.bySemanticsLabel(RegExp('${before.length} of 6,236 ayas')),
        findsOneWidget,
        reason:
            'a set the reader marked understood did not reach the one '
            'number the app exists to show',
      );
      semantics.dispose();
      expectNoSpinnerAndNoApology(tester, 'on the passage');
    },
  );
}

/// The settings panel on 1a, which is where the doors to the passage and the
/// kept list hang until the design draws them somewhere better.
Future<void> _openSettings(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.tune));
  await tester.pumpAndSettle();
}

/// A second handle on the same database file, opened writable so the journey
/// can keep an item the way a screen will.
Future<Database> _writable() async =>
    openDatabase('${await getDatabasesPath()}/wird.db');
