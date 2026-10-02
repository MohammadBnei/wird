import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:wird/data/sets.dart';
import 'package:wird/features/index/aya_search.dart';
import 'package:wird/features/index/index_screen.dart';
import 'package:wird/features/index/sura_picker.dart';
import 'package:wird/l10n/app_localizations.dart';
import 'package:wird/theme/nocturne.dart';

import '../../corpus.dart';

void main() {
  late List<SuraEntry> suras;

  late Database db;

  setUpAll(() async {
    db = await testCorpus();
    suras = await suraIndex(db);
  });

  // The search is kept once read, as a future: one completed in an earlier
  // test's zone never answers in the next, so each test reads its own.
  setUp(AyaSearch.forget);
  tearDownAll(AyaSearch.forget);

  test('a reader who reads by revelation is listed the sūras in written '
      'order, with the first one revealed buried at 96', () {
    final ids = [for (final s in inOrder(suras, ReadingOrder.nuzul)) s.id];
    expect(ids.take(5), [96, 68, 73, 74, 1]);
    expect(ids.toSet(), hasLength(114));
    expect(inOrder(suras, ReadingOrder.mushaf), same(suras));
  });

  test('a reference half typed, 2:, lists no sūra at all, so the reader '
      'is told nothing matches while still typing', () {
    expect([for (final s in searchSuras(suras, '2:')) s.id], [2]);
    expect([for (final s in searchSuras(suras, '2.25')) s.id], [2]);
  });

  int? chosen;

  Future<void> pick(
    WidgetTester tester, {
    String query = '',
    Set<int> exclude = const {},
    Database? db,
  }) async {
    chosen = null;
    await tester.pumpWidget(
      MaterialApp(
        theme: nocturneTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SuraPicker(
            suras: suras,
            order: ReadingOrder.nuzul,
            goToHint: '',
            db: db,
            exclude: exclude,
            onSura: (_) {},
            onRef: (id) => chosen = id,
          ),
        ),
      ),
    );
    // The text is read off the test's fake clock, as the picker opens.
    if (db != null) await tester.runAsync(() => AyaSearch.of(db));
    await tester.pumpAndSettle();
    if (query.isNotEmpty) {
      await tester.enterText(find.byType(TextField), query);
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    }
    await tester.pumpAndSettle();
  }

  testWidgets('a sūra left out of the picker is still offered through a '
      'reference to one of its ayas', (tester) async {
    await pick(tester, query: '1:1', exclude: {1});
    expect(find.textContaining('Go to'), findsNothing);
    expect(find.byKey(const ValueKey('sura-1')), findsNothing);
  });

  testWidgets('the picker lists in written order whatever the reader reads '
      'in', (tester) async {
    await pick(tester);
    double top(int sura) =>
        tester.getTopLeft(find.byKey(ValueKey('sura-$sura'))).dy;
    expect(top(96), lessThan(top(1)));
  });

  testWidgets('a reader who reads by revelation cannot look a sūra up by its '
      'written number without changing how they read in Settings', (
    tester,
  ) async {
    await pick(tester);
    await tester.tap(find.text('Muṣḥaf'));
    await tester.pumpAndSettle();
    double top(int sura) =>
        tester.getTopLeft(find.byKey(ValueKey('sura-$sura'))).dy;
    expect(top(1), lessThan(top(2)));
    expect(find.byKey(const ValueKey('sura-96')), findsNothing);
  });

  testWidgets('the list by revelation never says where Makkah gives way to '
      'Madinah', (tester) async {
    // Tall enough for all 114 rows and their headers to be built at once.
    tester.view.physicalSize = const Size(800, 20000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pick(tester);
    expect(find.text('MAKKĪ'), findsWidgets);
    expect(find.text('MADANĪ'), findsWidgets);
  });

  testWidgets('an aya found by its words cannot be chosen', (tester) async {
    await pick(tester, db: db, query: 'الكتاب');
    expect(find.text('AYAS CONTAINING “الكتاب”'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('found-2002')));
    expect(chosen, 2002);
  });

  testWidgets('a sūra left out of the picker is still offered through the '
      'words of its ayas', (tester) async {
    await pick(tester, db: db, query: 'the Lord of the Worlds', exclude: {1});
    expect(find.byKey(const ValueKey('found-1002')), findsNothing);
  });
}
