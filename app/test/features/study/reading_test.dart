import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wird/data/audio.dart';
import 'package:wird/data/db.dart';
import 'package:wird/data/sets.dart';
import 'package:wird/features/study/study_screen.dart';
import 'package:wird/features/study/word_row.dart';

import '../../corpus.dart';
import '../../fonts.dart';
import '../../offline.dart';
import '../../wird.dart';

/// Āyat al-Kursī, 255 ayas into the longest sūra in the Qur'an. Everything
/// that is cheap for a five-aya set is expensive here.
const _kursi = 2255;

/// A word by its corpus id: the aya's id, then its position in the aya.
int _word(int ayahId, int position) => ayahId * 1000 + position;

void main() {
  late Database db;
  late AudioCache audio;

  setUpAll(loadBundledFonts);
  setUp(() async {
    db = await testCorpus();
    audio = await emptyCache();
  });

  Future<void> openStudy(WidgetTester tester, {int? target}) async {
    await pumpPhone(
      tester,
      await wirdAround(db, StudyScreen(db: db, target: target), cache: audio),
    );
  }

  test('an aya the reader asked for arrives alone, so a sūra can be chosen '
      'but not read', () async {
    final set = (await ayaSet(db, ReadingOrder.mushaf, _kursi))!;

    expect(set.reading, hasLength(286), reason: 'the whole of Al-Baqarah');
    expect(set.reading.first.id, 2001);
    expect(set.reading.last.id, 2286);
    expect(set.focusIndex, 254, reason: 'the reader opens on 2:255');
    expect(
      [for (final aya in set.ayas) aya.id],
      [_kursi],
      reason: 'one aya is still what is marked, prayed and kept',
    );
  });

  test('reading a sūra reads all six thousand of its words to show twenty, '
      'so opening Al-Baqarah stalls before it draws', () async {
    final set = (await ayaSet(db, ReadingOrder.mushaf, _kursi))!;
    final loaded = [
      for (final aya in set.reading)
        if (aya.words.isNotEmpty) aya.id,
    ];

    expect(loaded, [_kursi]);
    expect(
      set.reading.fold(0, (sum, aya) => sum + aya.wordCount),
      6116,
      reason: 'the count is known without the words being read',
    );
  });

  test('a chunk of the sūra comes back missing the ayas that have no words, '
      'so the screen asks for them again every frame', () async {
    final chunk = await wordsFor(db, [2256, 2257, 2258]);

    expect(chunk.keys, [2256, 2257, 2258]);
    expect(chunk[2257], isNotEmpty);
    expect(
      [for (final w in chunk[2256]!) w.id],
      [for (var i = 1; i <= chunk[2256]!.length; i++) _word(2256, i)],
      reason: 'in the order they are recited',
    );
  });

  test('reading a sūra marks it understood, so the walk jumps past everything '
      'the reader only looked at', () async {
    final before = (await nextSet(db, ReadingOrder.nuzul))!;

    await ayaSet(db, ReadingOrder.mushaf, _kursi);

    expect(await db.query('ayah_understood'), isEmpty);
    expect(
      [for (final aya in (await nextSet(db, ReadingOrder.nuzul))!.ayas) aya.id],
      [for (final aya in before.ayas) aya.id],
    );
  });

  testWidgets('opening Al-Baqarah at one aya builds the 254 ayas above it, so '
      'the screen never draws', (tester) async {
    await openStudy(tester, target: _kursi);

    expect(
      find.byKey(ValueKey(_word(_kursi, 1))),
      findsOneWidget,
      reason: 'the reader lands on the aya they asked for',
    );
    expect(
      find.byKey(ValueKey(_word(2001, 1))),
      findsNothing,
      reason: 'the first aya of the sūra is 254 ayas away and is not built',
    );
    expect(
      tester.widgetList(find.byType(WordTile)).length,
      lessThan(200),
      reason: 'Al-Baqarah is 6116 words and a phone shows a screenful',
    );
  });

  testWidgets('a sūra opened at an aya reads downward only, so the reader '
      'cannot see what comes before it', (tester) async {
    await openStudy(tester, target: _kursi);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, 900));
    await tester.pumpAndSettle();

    expect(find.byKey(ValueKey(_word(2254, 1))), findsOneWidget);
  });

  testWidgets('the aya the reader asked for is all there is, so the sūra '
      'around it cannot be read on', (tester) async {
    await openStudy(tester, target: _kursi);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -900));
    await tester.pumpAndSettle();

    expect(find.byKey(ValueKey(_word(2256, 1))), findsOneWidget);
  });

  testWidgets('reading past an aya marks it, so a reader who scrolled through '
      'Al-Baqarah is told they understood it', (tester) async {
    await openStudy(tester, target: _kursi);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -900));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mark set understood'));
    await tester.pumpAndSettle();

    expect(
      (await db.query('ayah_understood')).map((r) => r['ayah_id']),
      [_kursi],
      reason: 'the aya the reader asked for, not the sūra they read',
    );
  });

  testWidgets('the index hands the reader one aya of the sūra they chose, so '
      'choosing Al-Baqarah is not a way to recite it', (tester) async {
    await pumpPhone(tester, await wholeApp(db, cache: audio));
    await goTo(tester, 'Sūra index');
    await tester.tap(find.byKey(const ValueKey('sura-2')));
    await tester.pumpAndSettle();

    expect(find.byType(StudyScreen), findsOneWidget);
    expect(find.byKey(ValueKey(_word(2001, 1))), findsOneWidget);
    expect(
      find.byKey(ValueKey(_word(2002, 1))),
      findsOneWidget,
      reason: 'the sūra goes on under the aya it opened at',
    );
  });

  testWidgets('Al-Baqarah costs a frame and a heap no phone has', (
    tester,
  ) async {
    final rssBefore = ProcessInfo.currentRss;
    final load = Stopwatch()..start();
    await openStudy(tester, target: _kursi);
    load.stop();

    final frame = Stopwatch()..start();
    await tester.pump();
    frame.stop();

    final scroll = Stopwatch()..start();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -900));
    await tester.pumpAndSettle();
    scroll.stop();
    final grew = (ProcessInfo.currentRss - rssBefore) / (1024 * 1024);

    // ignore: avoid_print
    print(
      'Al-Baqarah at 2:255 — open ${load.elapsedMilliseconds} ms, '
      'frame ${frame.elapsedMicroseconds / 1000} ms, '
      'scroll ${scroll.elapsedMilliseconds} ms, '
      'heap +${grew.toStringAsFixed(1)} MB, '
      '${tester.widgetList(find.byType(WordTile)).length} word tiles',
    );

    expect(frame.elapsedMilliseconds, lessThan(16));
    expect(grew, lessThan(60));
  });
}
