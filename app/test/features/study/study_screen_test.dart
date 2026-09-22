import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wird/data/db.dart';
import 'package:wird/features/study/study_screen.dart';
import 'package:wird/theme/nocturne.dart';

import '../../corpus.dart';
import '../../fonts.dart';

/// The word as the corpus spells it, harakat and all. Read from the database
/// rather than typed here, so the test cannot pass against a text the screen
/// never shows.
Future<String> word(Database db, int id) async {
  final rows = await db.query('words', where: 'id = ?', whereArgs: [id]);
  return rows.single['text_ar']! as String;
}

/// A word by its corpus id. Al-ʿAlaq repeats ٱقْرَأْ and ٱلَّذِى inside one
/// set, so a finder on the text alone matches the wrong tile.
Finder tile(int wordId) => find.byKey(ValueKey(wordId));

Text arabicOf(WidgetTester tester, int wordId) => tester.widget<Text>(
  find.descendant(of: tile(wordId), matching: find.byType(Text)).first,
);

void main() {
  late Database db;

  setUpAll(loadBundledFonts);
  setUp(() async => db = await testCorpus());

  Future<void> openStudy(WidgetTester tester) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(theme: nocturneTheme(), home: StudyScreen(db: db)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a set that crosses a sūra boundary drops the ayas on the far '
      'side of it', (tester) async {
    await db.execute(
      "INSERT INTO ayah_understood SELECT id, '' FROM ayahs "
      'WHERE surah_id = 96 AND number < 19',
    );

    await openStudy(tester);

    expect(find.text(await word(db, 96019001)), findsOneWidget);
    expect(find.text(await word(db, 68001001)), findsOneWidget);
    expect(find.textContaining('Al-Qalam'), findsOneWidget);
  });

  testWidgets('the aya paints left to right, or loses the harakat the corpus '
      'stores', (tester) async {
    await openStudy(tester);

    final painted = arabicOf(tester, 96001001);
    expect(painted.data, await word(db, 96001001));
    expect(
      painted.data,
      contains('ْ'),
      reason: 'the sukūn the corpus stores survives into the painted text',
    );
    expect(painted.textDirection, TextDirection.rtl);
    expect(painted.style!.fontFamily, Nocturne.arabicFamily);
  });

  testWidgets('tapping a word blanks the aya while the root panel catches up',
      (tester) async {
    await openStudy(tester);
    expect(find.text('ق ر أ'), findsOneWidget);

    await tester.tap(tile(96002004));
    await tester.pump();
    expect(
      tile(96002004),
      findsOneWidget,
      reason: 'the aya stays on screen while the new root is read',
    );

    await tester.pumpAndSettle();
    expect(find.text('ع ل ق'), findsOneWidget);
    expect(find.text('ق ر أ'), findsNothing);
  });

  testWidgets('tapping a word that carries no root throws away the root the '
      'reader was reading', (tester) async {
    await openStudy(tester);

    await tester.tap(tile(96001004));
    await tester.pumpAndSettle();

    expect(find.text('ق ر أ'), findsOneWidget);
  });

  testWidgets('the aya progress bar marks ayas the reader never understood',
      (tester) async {
    await markUnderstood(db, 96002);

    await openStudy(tester);

    expect(
      find.text('Aya 2 marked understood · aya 1, 3, 4 and 5 open'),
      findsOneWidget,
    );
  });

  testWidgets('turning the gloss off takes the Arabic with it', (tester) async {
    await openStudy(tester);
    expect(find.text('a clinging substance'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Neither'));
    await tester.pumpAndSettle();

    expect(find.text('a clinging substance'), findsNothing);
    expect(find.text(await word(db, 96002004)), findsOneWidget);
  });

  testWidgets('the Arabic size setting leaves the aya at the size it was',
      (tester) async {
    await openStudy(tester);
    final before = arabicOf(tester, 96001001).style!.fontSize;

    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(Slider), const Offset(-200, 0));
    await tester.pumpAndSettle();

    final after = arabicOf(tester, 96001001).style!.fontSize!;
    expect(after, isNot(before));
    expect(after, inInclusiveRange(24, 44));
  });
}
