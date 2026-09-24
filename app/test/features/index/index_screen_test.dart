import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wird/data/db.dart';
import 'package:wird/features/index/index_screen.dart';
import 'package:wird/theme/nocturne.dart';

import '../../corpus.dart';
import '../../fonts.dart';

void main() {
  late Database db;

  /// What the index handed back when it was left, which is what screen 1a
  /// opens on.
  int? chosen;

  setUpAll(loadBundledFonts);
  setUp(() async {
    db = await testCorpus();
    chosen = null;
  });

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: nocturneTheme(),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              chosen = await Navigator.of(context).push<int>(
                MaterialPageRoute(builder: (_) => IndexScreen(db: db)),
              );
            },
            child: const Text('whoever opened the index'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('whoever opened the index'));
    await tester.pumpAndSettle();
  }

  test('the index is missing a sūra, so part of the Qur’an cannot be reached '
      'at all', () async {
    expect(await suraIndex(db), hasLength(114));
  });

  testWidgets('a sūra row says nothing about how far the reader has got, so '
      'the index cannot be read for progress', (tester) async {
    await markSetUnderstood(db, newOpId(), [1001, 1002, 1003]);

    await open(tester);

    expect(find.text('1 · Al-Fatihah'), findsOneWidget);
    expect(find.text('3 / 7'), findsOneWidget);
    // The revelation order is what the app's own default walk is ordered by; a
    // reader in that order cannot find their place by the written number.
    expect(find.text('5th to be revealed'), findsOneWidget);
  });

  testWidgets('the revelation order is a bare number under the count of ayas, '
      'so a reader takes it for a second count', (tester) async {
    await open(tester);

    // Al-Baqarah is 286 ayas and the 87th sūra revealed. Printed as
    // "Revealed 87" under "0 / 286" the two read as one sentence.
    expect(find.text('87th to be revealed'), findsOneWidget);
    expect(find.text('Revealed 87'), findsNothing);
  });

  testWidgets('choosing an aya in the index leaves without naming it, so the '
      'reader lands back on the set they came from', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('ayas-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('aya-1005')));
    await tester.pumpAndSettle();

    expect(chosen, 1005);
    expect(find.byType(IndexScreen), findsNothing);
  });

  testWidgets('choosing a sūra only unfolds its aya numbers, so the reader who '
      'wanted to read Al-Baqarah has to pick one of 286 boxes first',
      (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('sura-2')));
    await tester.pumpAndSettle();

    expect(chosen, 2001, reason: 'a sūra opens at its first aya');
    expect(find.byType(IndexScreen), findsNothing);
  });

  testWidgets('nothing on a sūra row says the arrow does something other than '
      'the row, so the aya numbers are found by accident', (tester) async {
    await open(tester);

    expect(
      find.text('A sūra opens at its first aya. The arrow picks one inside it.'),
      findsOneWidget,
    );
  });
}
