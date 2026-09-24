import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:wird/data/audio.dart';
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

  testWidgets('home goes on offering the set the reader has just marked '
      'understood', (tester) async {
    final finished = (await nextSet(db, ReadingOrder.nuzul))!;
    await openHome(tester);
    expect(find.text(finished.title), findsOneWidget);

    await goTo(tester, 'The set');
    await tester.tap(find.text('Mark set understood'));
    await tester.pumpAndSettle();
    await goTo(tester, 'Home');

    expect(find.text(finished.title), findsNothing);
    expect(find.text((await nextSet(db, ReadingOrder.nuzul))!.title),
        findsOneWidget);
  });

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
    await goTo(tester, 'Home');

    expect(find.text(mushaf.title), findsOneWidget);
    expect(find.text(chronological.title), findsNothing);
  });
}
