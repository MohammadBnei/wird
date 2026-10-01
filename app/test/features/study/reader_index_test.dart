import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wird/data/audio.dart';
import 'package:wird/features/index/index_screen.dart';
import 'package:wird/features/study/study_screen.dart';
import 'package:wird/nav.dart';

import '../../corpus.dart';
import '../../fonts.dart';
import '../../offline.dart';
import '../../wird.dart';

/// The way from the reading screen to another sūra: its name in the bar
/// opens the index, and the aya picked there comes back to the same reader.
void main() {
  late Database db;
  late AudioCache audio;

  setUpAll(loadBundledFonts);
  setUp(() async {
    db = await testCorpus();
    audio = await emptyCache();
  });

  Future<void> openStudy(WidgetTester tester) async => pumpPhone(
    tester,
    await wirdAround(
      db,
      StudyScreen(db: db),
      route: Routes.study,
      cache: audio,
    ),
  );

  testWidgets('the reader cannot reach the sūra index, so changing sūra means '
      'leaving the reading by the drawer', (tester) async {
    await openStudy(tester);

    await tester.tap(find.byKey(const Key('surah name')));
    await tester.pumpAndSettle();

    expect(find.byType(IndexScreen), findsOneWidget);
    expect(
      find.byIcon(Icons.menu),
      findsNothing,
      reason: 'the index opened from the reading is a step, not a destination',
    );
  });

  testWidgets('the aya picked in the index leaves the reader on the index, or '
      'on a second reader stacked over the first', (tester) async {
    await openStudy(tester);

    await tester.tap(find.byKey(const Key('surah name')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sura-1')));
    await tester.pumpAndSettle();

    expect(find.byType(IndexScreen), findsNothing);
    expect(find.byType(StudyScreen), findsOneWidget);
    expect(find.textContaining('Al-Fatihah'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('position'))).data,
      startsWith('1:1 '),
    );
  });
}
