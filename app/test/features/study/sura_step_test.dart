import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wird/app.dart';
import 'package:wird/data/sets.dart';
import 'package:wird/features/study/study_screen.dart';
import 'package:wird/nav.dart';

import '../../corpus.dart';
import '../../fonts.dart';
import '../../wird.dart';

void main() {
  late Database db;
  late List<SurahPlace> all;

  setUpAll(loadBundledFonts);
  setUp(() async {
    db = await testCorpus();
    all = await surahPlaces(db);
  });

  test('in revelation order the next sūra is the one revealed next, not the '
      'next in the book', () {
    expect(surahBeside(all, ReadingOrder.nuzul, 96, 1)?.id, 68);
    expect(surahBeside(all, ReadingOrder.nuzul, 96, -1), isNull);
    expect(surahBeside(all, ReadingOrder.nuzul, 110, 1), isNull);
  });

  test('in written order Al-Fātiḥa has no previous sūra and its next is '
      'Al-Baqarah', () {
    expect(surahBeside(all, ReadingOrder.mushaf, 1, -1), isNull);
    expect(surahBeside(all, ReadingOrder.mushaf, 1, 1)?.id, 2);
    expect(surahBeside(all, ReadingOrder.mushaf, 114, 1), isNull);
  });

  testWidgets('the link at the top of a sūra follows the order the reader '
      'switches to, and opens that sūra', (tester) async {
    await pumpPhone(
      tester,
      await wirdAround(
        db,
        StudyScreen(db: db, target: 96001),
        route: Routes.study,
      ),
    );
    final prefs = Wird.of(tester.element(find.byType(StudyScreen))).prefs;
    Finder nextNamed(String name) => find.descendant(
      of: find.byKey(const Key('next sura')).first,
      matching: find.text(name),
    );

    await tester.runAsync(() => prefs.setOrder(ReadingOrder.mushaf));
    await tester.pumpAndSettle();
    expect(nextNamed('Al-Qadr'), findsOneWidget);

    await tester.runAsync(() => prefs.setOrder(ReadingOrder.nuzul));
    await tester.pumpAndSettle();
    expect(nextNamed('Al-Qalam'), findsOneWidget);

    await tester.tap(find.byKey(const Key('next sura')).first);
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const Key('surah name')),
        matching: find.textContaining('Al-Qalam'),
      ),
      findsOneWidget,
    );
  });
}
