import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wird/data/sets.dart';
import 'package:wird/features/prayer/prayer_cursor.dart';
import 'package:wird/features/prayer/prayer_screen.dart';
import 'package:wird/features/study/word_row.dart';

import '../../corpus.dart';
import '../../fonts.dart';
import 'prayer_screen_test.dart' show noWordIsLit, pumpPrayer;
import 'sets.dart';

/// The word the screen is pointing at, whatever else is on it. During a turn
/// the aya leaving and the aya arriving are both in the tree, so this asks for
/// the lit one rather than the first one.
int litWord(WidgetTester tester) {
  for (final text in tester.widgetList<Text>(find.byType(Text))) {
    if (text.key is WordKey && text.style?.shadows != null) {
      return (text.key! as WordKey).value;
    }
  }
  fail('no word on the screen is lit as the one being recited');
}

/// Whether the word with corpus id [id] is drawn at all.
bool drawn(WidgetTester tester, int id) => tester
    .widgetList<Text>(find.byType(Text))
    .any((t) => t.key is WordKey && (t.key! as WordKey).value == id);

/// The dwell the screen waits before turning, plus a frame. A Timer is not an
/// animation, so pumpAndSettle will not run it out.
const _dwellInTests = Duration(milliseconds: 600);

void main() {
  late Database db;
  late StudySet set;

  setUpAll(loadBundledFonts);
  setUp(() async {
    db = await testCorpus();
    set = await setOf(db, [103001, 103002, 103003]);
  });

  Future<PrayerCursor> pump(WidgetTester tester) async {
    final cursor = PrayerCursor(14);
    await pumpPrayer(
      tester,
      db: db,
      set: set,
      cursor: cursor,
      wakelock: ({required bool enable}) async {},
    );
    await tester.pumpAndSettle();
    return cursor;
  }

  testWidgets('the aya the reciter just finished is gone before they have '
      'stopped saying it', (tester) async {
    final cursor = await pump(tester);
    // Nothing said yet, so nothing is singled out.
    expect(noWordIsLit(tester), isTrue);

    // The voice crosses into 103:2 — al-ʿAsr is one word, then four, then
    // nine, so word 3 is the third word of the second aya. The aya just
    // finished stands for a moment: a screen that changes on the last
    // syllable reads as impatience.
    cursor.moveTo(3);
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      drawn(tester, 103001001),
      isTrue,
      reason: 'the next aya arrived before the reader had drawn breath',
    );
    // Standing as recited: nothing in it is the word being said.
    expect(noWordIsLit(tester), isTrue);

    await tester.pump(_dwellInTests);
    await tester.pumpAndSettle();
    expect(litWord(tester), 103002003);
  });

  testWidgets('a reciter running straight on is made to wait for the screen', (
    tester,
  ) async {
    final cursor = await pump(tester);

    // Into the next aya, and on again before the breath is up: somebody
    // reciting without pausing, who should not be watching the screen catch
    // up with them.
    cursor.moveTo(2);
    await tester.pump(const Duration(milliseconds: 100));
    cursor.moveTo(3);
    await tester.pumpAndSettle();

    expect(
      litWord(tester),
      103002003,
      reason: 'the reciter was two words on and the screen was still holding '
          'the aya before, waiting out a breath they never took',
    );
  });

  testWidgets('the reader taps and is made to wait a breath for the answer', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.byKey(PrayerScreen.nextZone));
    // No dwell for a hand: the reader is saying where they are.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(litWord(tester), 103002001);
  });

  testWidgets('the reciter finishes an aya and the next one is not there '
      'when they look for it', (tester) async {
    final cursor = await pump(tester);
    // 103:1 is one word, heard surely: the aya is finished, and the next one
    // arrives a breath later without waiting for its first word to be heard.
    cursor.moveTo(0, sure: true);
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      drawn(tester, 103002001),
      isFalse,
      reason:
          'the aya was snatched '
          'from under its last syllable',
    );
    await tester.pump(_dwellInTests);
    await tester.pumpAndSettle();
    expect(
      drawn(tester, 103002001),
      isTrue,
      reason:
          'the reciter finished '
          '103:1 and the screen still showed it',
    );
  });

  testWidgets("al-Fātiḥa's last aya runs into the passage's first as one "
      'sūra', (tester) async {
    final fatiha = (await setOf(db, [
      for (var a = 1; a <= 7; a++) 1000 + a,
    ])).ayas;
    // On the passage's first word: the aya before it is al-Fātiḥa's last.
    final cursor = PrayerCursor(29 + 14, at: 29);
    await pumpPrayer(
      tester,
      db: db,
      set: set,
      fatiha: fatiha,
      cursor: cursor,
      wakelock: ({required bool enable}) async {},
    );
    await tester.pumpAndSettle();
    expect(
      find.text("Al-'Asr"),
      findsOneWidget,
      reason:
          'nothing marked '
          'where al-Fātiḥa ended and the passage began',
    );
    expect(
      find.text([for (final w in fatiha.last.words) w.text].join(' ')),
      findsNothing,
    );
  });

  testWidgets('a cursor that steps back off the last word still turns the '
      'aya', (tester) async {
    final cursor = await pump(tester);
    // 103:2's last word, then — before the breath is up — back inside it:
    // the matcher was sure too early, and the reader is still in 103:2.
    cursor.moveTo(4, sure: true);
    await tester.pump(const Duration(milliseconds: 200));
    cursor.moveTo(3, sure: true);
    await tester.pump(_dwellInTests);
    await tester.pumpAndSettle();
    expect(litWord(tester), 103002003);
    expect(drawn(tester, 103003001), isFalse);
  });
}
