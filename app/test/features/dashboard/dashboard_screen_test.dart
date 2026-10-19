import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:flutter/material.dart';
import 'package:wird/data/audio.dart';
import 'package:wird/data/db.dart';
import 'package:wird/data/sets.dart';
import 'package:wird/widgets/nocturne_button.dart';

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

  // The failure: the set's two buttons weighed the same, with Pray on top, so
  // a newcomer was asked to pray a set before being offered to read it.
  testWidgets('home asks for a prayer before offering to read the set', (
    tester,
  ) async {
    await openHome(tester);

    final read = find.byKey(const Key('read the set'));
    final pray = find.byKey(const Key('pray the set'));
    expect(tester.getTopLeft(read).dy, lessThan(tester.getTopLeft(pray).dy));
    expect(
      tester.widget<NocturneButton>(read).variant,
      NocturneButtonVariant.primary,
    );
    expect(
      tester.widget<NocturneButton>(pray).variant,
      isNot(NocturneButtonVariant.primary),
    );
  });

  // The failure: home repeated every drawer row as a door, so the screen a
  // reader lands on had six ways out and no first step.
  testWidgets('home lists every drawer destination as a door', (tester) async {
    await openHome(tester);

    expect(find.byKey(const ValueKey('door/index')), findsOneWidget);
    expect(find.byKey(const ValueKey('door/prepare')), findsOneWidget);
    expect(find.byKey(const ValueKey('door/progress')), findsNothing);
    expect(find.byKey(const ValueKey('door/kept')), findsNothing);
  });

  // The failure: the one continue line pointed at the sūra the walk had just
  // finished, rather than at one the reader opened outside it.
  testWidgets('home offers a finished sūra as the place to continue', (
    tester,
  ) async {
    await markSetUnderstood(db, newOpId(), [
      for (var a = 1; a <= 7; a++) 1000 + a,
    ]);
    await movePosition(db, 2255003);
    // The last place stood in, but a sūra already understood to its end.
    await movePosition(db, 1007001);
    await openHome(tester);

    expect(find.byKey(const ValueKey('continue 1007001')), findsNothing);
    expect(find.byKey(const ValueKey('continue 2255003')), findsOneWidget);
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
