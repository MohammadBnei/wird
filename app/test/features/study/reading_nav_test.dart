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

/// The footer of screen 1a moves the reader through the text. A reader who
/// can read a whole sūra needs a way around it that is not scrolling, and a
/// way out of it that is not the drawer.
void main() {
  late Database db;
  late AudioCache audio;

  setUpAll(loadBundledFonts);
  setUp(() async {
    db = await testCorpus();
    audio = await emptyCache();
  });

  Future<void> openStudy(WidgetTester tester, {int? target}) async =>
      pumpPhone(
        tester,
        await wirdAround(
          db,
          StudyScreen(db: db, target: target),
          route: Routes.study,
          cache: audio,
        ),
      );

  Future<void> step(WidgetTester tester, String which) async {
    await tester.tap(find.byKey(Key(which)));
    await tester.pumpAndSettle();
  }

  testWidgets('the aya after the set can only be reached by marking the set '
      'understood first', (tester) async {
    await openStudy(tester);
    expect(find.textContaining("Al-'Alaq 1–5"), findsOneWidget);

    await step(tester, 'next aya');

    expect(find.textContaining("Al-'Alaq 6"), findsOneWidget);
    expect(await db.query('ayah_understood'), isEmpty);
  });

  testWidgets('the aya before the one the reader is visiting is out of reach, '
      'so a sūra can only be read forwards', (tester) async {
    await openStudy(tester, target: 2255);

    await step(tester, 'previous aya');

    expect(find.textContaining('Al-Baqarah 254'), findsOneWidget);
  });

  testWidgets('the step down is offered at the end of the sūra, where the aya '
      'below it is one the corpus cannot serve', (tester) async {
    // 96:19 ends Al-'Alaq. 96:20 is nothing, and a set read from nothing
    // empties the screen onto "there is nothing left to serve".
    await openStudy(tester, target: 96019);

    await step(tester, 'next aya');

    expect(find.textContaining("Al-'Alaq 19"), findsOneWidget);
  });

  testWidgets('the step up is offered at the head of the sūra, where the aya '
      'above it is one the corpus cannot serve', (tester) async {
    await openStudy(tester, target: 2001);

    await step(tester, 'previous aya');

    expect(find.textContaining('Al-Baqarah 1'), findsOneWidget);
  });

  testWidgets('the footer cannot reach the sūra index, so changing sūra means '
      'leaving the reading by the drawer', (tester) async {
    await openStudy(tester);

    await tester.tap(find.byKey(const Key('open the index')));
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

    await tester.tap(find.byKey(const Key('open the index')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sura-1')));
    await tester.pumpAndSettle();

    expect(find.byType(IndexScreen), findsNothing);
    expect(find.byType(StudyScreen), findsOneWidget);
    expect(find.textContaining('Al-Fatihah 1'), findsOneWidget);
  });
}
