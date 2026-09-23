import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wird/data/db.dart';
import 'package:wird/features/index/index_screen.dart';
import 'package:wird/features/kept/kept_screen.dart';
import 'package:wird/data/sets.dart';
import 'package:wird/features/progress/passage.dart';
import 'package:wird/features/progress/progress_screen.dart';
import 'package:wird/nav.dart';
import 'package:wird/theme/nocturne.dart';

import '../../corpus.dart';
import '../../fonts.dart';

/// Al-Fātiḥa, all seven ayas: the whole of one sūra and a slice of the first
/// juz, so a count that is wrong shows up as a wrong sūra row and a wrong arc
/// at the same time.
const _fatiha = [1001, 1002, 1003, 1004, 1005, 1006, 1007];

void main() {
  late Database db;

  setUpAll(loadBundledFonts);
  setUp(() async => db = await testCorpus());

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: nocturneTheme(),
        onGenerateRoute: (settings) => screenRoute(settings, db),
        home: ProgressScreen(db: db),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a reader who has prayed no set at all is shown a division by '
      'zero where the prayers-per-set tile belongs', (tester) async {
    await open(tester);

    expect(find.text('—'), findsOneWidget);
    expect(find.textContaining('NaN'), findsNothing);
    expect(find.textContaining('Infinity'), findsNothing);
  });

  testWidgets('the tiles count the sets the reader prayed as sets they '
      'understood, so a set prayed twice reads as two sets read', (
    tester,
  ) async {
    // Two sets read and marked, and a third the reader has prayed twice
    // without marking: the set rows and the walk disagree on purpose.
    for (var i = 0; i < 2; i++) {
      final set = (await nextSet(db, await readingOrder(db)))!;
      await markSetUnderstood(db, newOpId(), [for (final a in set.ayas) a.id]);
    }
    final praying = (await nextSet(db, await readingOrder(db)))!;
    await recordSetPrayed(db, praying);
    await recordSetPrayed(db, praying);

    final passage = await readPassage(db);
    expect(passage.setsUnderstood, 2);
    expect(passage.prayers, 2);
    expect(passage.currentSet, 3, reason: 'the walk is on its third set');
    expect(
      passage.prayersOnCurrentSet,
      2,
      reason: 'the next prayer on this set is its third',
    );

    await open(tester);
    expect(find.text('1.0'), findsOneWidget);
  });

  testWidgets('the passage is counted against something other than the 6,236 '
      'ayas of the Ḥafṣ muṣḥaf', (tester) async {
    final semantics = tester.ensureSemantics();
    await markSetUnderstood(db, newOpId(), _fatiha);
    await open(tester);

    // The ring's own numbers are painted, so the reader who cannot see them
    // and the test both read them off the semantics.
    expect(
      find.bySemanticsLabel(RegExp(r'0\.1% .*7 of 6,236 ayas')),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('the ring lights a juz the reader has never opened, or leaves '
      'a finished one dark', (tester) async {
    final before = await readPassage(db);
    expect(before.juz.every((f) => f == 0), isTrue);

    await markSetUnderstood(db, newOpId(), _fatiha);
    final after = await readPassage(db);

    // Juz 1 runs from 1:1 to 2:141 — 148 ayas, of which Al-Fātiḥa is seven.
    expect(after.juz.first, closeTo(7 / 148, 1e-9));
    expect(after.juz.skip(1).every((f) => f == 0), isTrue);
  });

  testWidgets('the sūra the next set comes from is missing from "Where you '
      'are", so the screen never says where the reader is', (tester) async {
    await open(tester);

    // The chronological walk opens at Al-ʿAlaq, so that is where a reader who
    // has understood nothing stands.
    expect(find.text("96 · Al-'Alaq"), findsOneWidget);
    expect(find.text('0 / 19'), findsOneWidget);
  });

  testWidgets('a sūra the reader has worked through drops off "Where you '
      'are" in favour of one they have not touched', (tester) async {
    await markSetUnderstood(db, newOpId(), _fatiha);
    await open(tester);

    expect(find.text('1 · Al-Fatihah'), findsOneWidget);
    expect(find.text('7 / 7'), findsOneWidget);
  });

  testWidgets('the roots met in the ayas already understood are not counted '
      'as known, so the card is empty for a reader who has read', (
    tester,
  ) async {
    await markSetUnderstood(db, newOpId(), _fatiha);
    await open(tester);

    final passage = await readPassage(db);
    expect(passage.rootsKnown, isNotEmpty);
    expect(find.textContaining('roots cover'), findsOneWidget);
    expect(
      find.textContaining('${passage.rootsKnownCount} roots cover'),
      findsOneWidget,
    );
  });

  testWidgets('"All 114" opens the kept list instead of the 114 sūras it '
      'names', (tester) async {
    await open(tester);
    await tester.tap(find.text('All 114'));
    await tester.pumpAndSettle();

    expect(find.byType(IndexScreen), findsOneWidget);
    expect(find.byType(KeptScreen), findsNothing);
  });

}
