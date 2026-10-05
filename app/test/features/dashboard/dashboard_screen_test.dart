import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:flutter/material.dart';
import 'package:wird/data/audio.dart';
import 'package:wird/data/db.dart';
import 'package:wird/data/sets.dart';

import '../../corpus.dart';
import '../../fonts.dart';
import '../../offline.dart';
import '../../wird.dart';

void main() {
  late Database db;
  late AudioCache audio;

  setUpAll(loadBundledFonts);
  setUp(() async {
    db = await testCorpus();
    audio = await emptyCache();
  });

  Future<void> openHome(WidgetTester tester) async =>
      pumpPhone(tester, await wholeApp(db, cache: audio));

  testWidgets('home offers the set of the reading order the reader has just '
      'left', (tester) async {
    final chronological = (await nextSet(db, ReadingOrder.nuzul))!;
    final mushaf = (await nextSet(db, ReadingOrder.mushaf))!;
    expect(chronological.title, isNot(mushaf.title));

    await openHome(tester);
    expect(find.text(chronological.title), findsOneWidget);

    await goTo(tester, 'Settings');
    await tester.tap(find.text('Muṣḥaf'));
    await tester.pumpAndSettle();
    await closeSettings(tester);

    expect(find.text(mushaf.title), findsOneWidget);
    expect(find.text(chronological.title), findsNothing);
  });

  // The failure: home only knows the walk, so a reader part-way through
  // Al-Baqarah finds no way back to 2:255 but the index and a scroll.
  testWidgets('a reader part-way through a sūra finds no way back to the word '
      'they stopped on', (tester) async {
    await movePosition(db, 2255003);
    await openHome(tester);

    await tester.tap(find.byKey(const ValueKey('continue 2255003')));
    await tester.pumpAndSettle();

    expect(
      tester.widget<Text>(find.byKey(const Key('position'))).data,
      startsWith('2:255 · word '),
    );
  });

  testWidgets('a fresh install asks for a prayer before saying what a set is', (
    tester,
  ) async {
    await openHome(tester);

    expect(find.text('WELCOME'), findsOneWidget);
    expect(find.textContaining('a few ayas at a time'), findsOneWidget);
  });

  // The failure: the welcome keyed on anything the reader touched, so one word
  // tapped out of curiosity took it away before a set was ever understood.
  testWidgets('a word tapped out of curiosity ends the welcome', (
    tester,
  ) async {
    await movePosition(db, 2255003);
    await openHome(tester);

    expect(find.text('WELCOME'), findsOneWidget);
  });

  testWidgets('the welcome outlives a prayer recorded off the walk', (
    tester,
  ) async {
    final visited = (await ayaSet(db, ReadingOrder.nuzul, 2255))!;
    await recordSetPrayed(db, visited);
    await openHome(tester);

    expect(find.text('WELCOME'), findsNothing);
  });

  // The failure: in the order of revelation the walk opens on Al-'Alaq, which
  // sits in juz 30, so a newcomer was told they were at the last juz of 30.
  testWidgets('under revelation order home tells a newcomer they are in juz 30',
      (tester) async {
    await openHome(tester);

    expect(
      find.text('Sūra 1 of 114 in the order of revelation'),
      findsOneWidget,
    );
    expect(find.textContaining('Juzʾ'), findsNothing);

    await goTo(tester, 'Settings');
    await tester.tap(find.text('Muṣḥaf'));
    await tester.pumpAndSettle();
    await closeSettings(tester);

    expect(find.text('Sūra 1 of 114 · Juzʾ 1'), findsOneWidget);
  });

  testWidgets('home lists the sūra the walk is in twice, once as the set and '
      'once as a place to continue', (tester) async {
    final set = (await nextSet(db, ReadingOrder.nuzul))!;
    final inTheSet = set.ayas.first.id * 1000 + 1;
    await movePosition(db, inTheSet);
    await movePosition(db, 2255003);
    await openHome(tester);

    expect(find.byKey(ValueKey('continue $inTheSet')), findsNothing);
    expect(find.byKey(const ValueKey('continue 2255003')), findsOneWidget);
  });
}
