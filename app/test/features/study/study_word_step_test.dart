import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wird/data/audio.dart';
import 'package:wird/features/study/study_screen.dart';
import 'package:wird/nav.dart';

import '../../corpus.dart';
import '../../fonts.dart';
import '../../offline.dart';
import '../../wird.dart';

/// The arrows in the root sheet: the reader walks the sūra a word at a time,
/// reading what each one is built from, instead of hunting for the next word
/// to tap. They are what a reader who cannot drag, or a screen reader, walks
/// with, so they do everything the swipe does.
///
/// The unit is the word and the reach is the sūra — every word of it,
/// particles included.
void main() {
  late Database db;
  late AudioCache audio;

  setUpAll(loadBundledFonts);
  setUp(() async {
    db = await testCorpus();
    audio = await emptyCache();
  });

  Future<void> openStudy(WidgetTester tester, {int? target}) async => pumpPhone(
    tester,
    await wirdAround(
      db,
      StudyScreen(db: db, target: target),
      route: Routes.study,
      cache: audio,
    ),
  );

  final next = find.byKey(const Key('next word'));
  final previous = find.byKey(const Key('previous word'));

  Future<void> step(WidgetTester tester, Finder arrow, {int times = 1}) async {
    for (var i = 0; i < times; i++) {
      await tester.tap(arrow);
      await tester.pumpAndSettle();
    }
  }

  bool dark(WidgetTester tester, Finder arrow) =>
      tester.widget<GestureDetector>(arrow).onTap == null;

  /// A root as the sheet names it, over the word open. The ring further down
  /// the sheet prints the same letters at its centre.
  Finder rootNamed(String display) => find.descendant(
    of: find.byKey(const ValueKey('open-root')),
    matching: find.text(display),
  );

  testWidgets('the next arrow skips a word or stays put instead of opening the '
      'next word of the aya', (tester) async {
    await openStudy(tester);
    expect(rootNamed('ق ر أ'), findsOneWidget);

    await step(tester, next);

    expect(rootNamed('س م و'), findsOneWidget);
    expect(rootNamed('ق ر أ'), findsNothing);
  });

  testWidgets('a word with no root stops the walk dead instead of being one '
      'more word to pass through', (tester) async {
    await openStudy(tester);

    // ٱلَّذِى, the fourth word: a particle the corpus gives no root.
    await step(tester, next, times: 3);

    expect(find.text('No root'), findsOneWidget);
    expect(dark(tester, next), isFalse);
    expect(dark(tester, previous), isFalse);

    await step(tester, next);

    expect(rootNamed('خ ل ق'), findsOneWidget);
  });

  testWidgets('the walk stops at the edge of the acted set, leaving the ayas '
      'the reader is looking at out of reach', (tester) async {
    // A visit: the set is aya 10 alone, and the sūra around it is the reading.
    await openStudy(tester, target: 96010);
    expect(rootNamed('ع ب د'), findsOneWidget);

    // عبد, إذا, صلى — then out of the acted aya and into the next one.
    await step(tester, next, times: 3);

    expect(rootNamed('ر أ ي'), findsOneWidget);
  });

  testWidgets('an arrow with nowhere to go is still lit, so the reader presses '
      'it and nothing happens', (tester) async {
    await openStudy(tester);

    expect(dark(tester, previous), isTrue, reason: 'the first word of 96');
    expect(dark(tester, next), isFalse);

    // The last aya of the sūra has five words, and it opens on the first.
    await tester.pumpWidget(const SizedBox.shrink());
    await openStudy(tester, target: 96019);
    await step(tester, next, times: 4);

    expect(rootNamed('ق ر ب'), findsOneWidget);
    expect(dark(tester, next), isTrue, reason: 'the last word of 96');
    expect(dark(tester, previous), isFalse);
  });

  testWidgets('two presses in one frame move one word, because the second '
      'counts from where the first started', (tester) async {
    await openStudy(tester);

    await tester.tap(next);
    await tester.tap(next);
    await tester.pumpAndSettle();

    expect(rootNamed('ر ب ب'), findsOneWidget);
  });

  testWidgets('a word whose root the corpus lost pins the reader on the word '
      'before it', (tester) async {
    await db.delete('roots', where: 'letters = ?', whereArgs: ['سمو']);

    await openStudy(tester);
    await step(tester, next);

    expect(find.text('No root'), findsOneWidget);
    expect(rootNamed('ق ر أ'), findsNothing);
  });

  testWidgets('expanding the sheet on a word with no root leaves a sheet that '
      'cannot be brought back down', (tester) async {
    await openStudy(tester);
    await step(tester, next, times: 3);

    await tester.tap(find.byKey(const Key('sheet handle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('open aya')), findsOneWidget);
    await tester.tap(find.byKey(const Key('sheet handle')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('open aya')), findsNothing);

    expect(find.text('No root'), findsOneWidget);
    expect(next, findsOneWidget);
  });
}
