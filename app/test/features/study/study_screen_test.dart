import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wird/data/audio.dart';
import 'package:wird/data/db.dart';
import 'package:wird/data/sets.dart';
import 'package:wird/data/mic.dart';
import 'package:wird/features/study/study_screen.dart';
import 'package:wird/theme/nocturne.dart';
import 'package:wird/widgets/nocturne_button.dart';

import '../../corpus.dart';
import '../../fonts.dart';
import '../../offline.dart';

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
  late AudioCache audio;

  setUpAll(loadBundledFonts);
  // Both the corpus copy and the cache directory are real file work, which
  // never completes inside the fake-async zone a widget test body runs in.
  setUp(() async {
    db = await testCorpus();
    audio = await emptyCache();
  });

  /// The screen on a phone that has never been online: no recitation on disk
  /// and no way to fetch one.
  Future<void> openStudy(WidgetTester tester) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: nocturneTheme(),
        home: StudyScreen(db: db, audioCache: audio),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openSettings(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.tune));
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
    await markSetUnderstood(db, newOpId(), [96002]);

    await openStudy(tester);

    expect(
      find.text('Aya 2 marked understood · aya 1, 3, 4 and 5 open'),
      findsOneWidget,
    );
  });

  testWidgets('turning the gloss off takes the Arabic with it', (tester) async {
    await openStudy(tester);
    expect(find.text('a clinging substance'), findsOneWidget);

    await openSettings(tester);
    await tester.tap(find.text('Neither'));
    await tester.pumpAndSettle();

    expect(find.text('a clinging substance'), findsNothing);
    expect(find.text(await word(db, 96002004)), findsOneWidget);
  });

  testWidgets('the Arabic size setting leaves the aya at the size it was',
      (tester) async {
    await openStudy(tester);
    final before = arabicOf(tester, 96001001).style!.fontSize;

    await openSettings(tester);
    await tester.drag(find.byType(Slider), const Offset(-200, 0));
    await tester.pumpAndSettle();

    final after = arabicOf(tester, 96001001).style!.fontSize!;
    expect(after, isNot(before));
    expect(after, inInclusiveRange(24, 44));
  });

  testWidgets('a long press on an aya that was never downloaded spins instead '
      'of showing the transliteration', (tester) async {
    await openStudy(tester);
    final rows = await db.query('words', where: 'id = 96001001');
    final translit = rows.single['translit']! as String;

    await tester.longPress(tile(96001001));
    await tester.pumpAndSettle();

    expect(find.text(translit), findsOneWidget);
    expect(
      find.byType(CircularProgressIndicator),
      findsNothing,
      reason: 'a word with no audio answers at once, or not at all',
    );
  });

  testWidgets('the recitation offers to play a set that is not on the phone, '
      'and stalls on a file it cannot fetch', (tester) async {
    await openStudy(tester);

    expect(find.text('Not downloaded'), findsOneWidget);
    final play = tester.widget<NocturneButton>(
      find.ancestor(
        of: find.byIcon(Icons.play_arrow),
        matching: find.byType(NocturneButton),
      ),
    );
    expect(play.onPressed, isNull);
  });

  testWidgets('the reader is stuck in the order they started, with no way to '
      'read the muṣḥaf from its first sūra', (tester) async {
    await openStudy(tester);
    expect(find.textContaining("Al-'Alaq 1"), findsOneWidget);

    await openSettings(tester);
    await tester.tap(find.text('Muṣḥaf'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Al-Fatihah 1'), findsOneWidget);
    expect(await readingOrder(db), ReadingOrder.mushaf);
  });

  testWidgets('the microphone is asked for on the way into the prayer, where '
      'no dialog may appear', (tester) async {
    await openStudy(tester);
    expect(
      await micPermission(db),
      MicPermission.notAsked,
      reason: 'opening the set asks for nothing',
    );

    await openSettings(tester);
    await tester.tap(find.text('Allow microphone'));
    await tester.pumpAndSettle();

    expect(await micPermission(db), isNot(MicPermission.notAsked));
    expect(find.textContaining('advances on a tap'), findsOneWidget);
  });

  testWidgets('marking the set understood serves it again, and queues nothing '
      'for the server', (tester) async {
    await openStudy(tester);
    expect(find.textContaining("Al-'Alaq 1"), findsOneWidget);

    await tester.tap(find.text('Mark set understood'));
    await tester.pumpAndSettle();

    expect(find.textContaining("Al-'Alaq 6"), findsOneWidget);
    expect((await db.query('outbox')).length, 1);
    expect((await db.query('ayah_understood')).length, 5);
  });
}
