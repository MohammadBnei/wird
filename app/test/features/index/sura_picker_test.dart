import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wird/data/sets.dart';
import 'package:wird/features/index/index_screen.dart';
import 'package:wird/features/index/sura_picker.dart';
import 'package:wird/l10n/app_localizations.dart';
import 'package:wird/theme/nocturne.dart';

import '../../corpus.dart';

void main() {
  late List<SuraEntry> suras;

  setUpAll(() async => suras = await suraIndex(await testCorpus()));

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

  Future<void> pick(
    WidgetTester tester, {
    String query = '',
    Set<int> exclude = const {},
  }) async {
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
            exclude: exclude,
            onSura: (_) {},
            onRef: (_) {},
          ),
        ),
      ),
    );
    if (query.isNotEmpty) {
      await tester.enterText(find.byType(TextField), query);
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
}
