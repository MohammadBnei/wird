import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:wird/features/prayer/prayer_cursor.dart';

/// Everything a driver could report, sane and otherwise, against a set of
/// every awkward size. What this harness pins is that the cursor never throws
/// and never names a word that is not in the set — the two things the prayer
/// screen would fail in front of somebody on.
///
/// It no longer pins direction. A reciter repeats an aya, and starts the set
/// again for the next rakʿa; both are backward moves and both are ordinary.
/// What stops a *wrong* move is upstream, in alignment.dart, which refuses to
/// name a place unless one fits better than every other by a clear margin.
void overDrivenInput(void Function(PrayerCursor cursor, int report) check) {
  final random = Random(20260925);
  for (var run = 0; run < 200; run++) {
    final words = 1 + random.nextInt(30);
    final cursor = PrayerCursor(words);
    for (var step = 0; step < 60; step++) {
      final report = switch (random.nextInt(8)) {
        0 => -1 - random.nextInt(1000),
        1 => words * (1 + random.nextInt(4)),
        2 => 0,
        3 => words - 1,
        _ => random.nextInt(words),
      };
      check(cursor, report);
    }
  }
}

void main() {
  test(
    'a driver reporting nonsense leaves the screen with no word to light, or '
    'takes the prayer down in the middle of it',
    () {
      overDrivenInput((cursor, report) {
        cursor.moveTo(report);
        expect(cursor.at, inInclusiveRange(0, cursor.words - 1));
      });
    },
  );

  test(
    'the reciter repeating an aya is dragged on instead of followed back',
    () {
      // The rule this class carried until 2026-09-25 was advance-or-freeze, and
      // it made this impossible. A reciter repeats, and the screen has to go
      // with them: during ṣalāh the phone is on the floor and there is no hand
      // coming to correct it.
      final cursor = PrayerCursor(5)..moveTo(3);
      cursor.moveTo(1);
      expect(cursor.at, 1);
      cursor.moveTo(3);
      expect(cursor.at, 3);
      cursor.moveTo(0);
      expect(cursor.at, 0);
    },
  );

  test('the set started again for the next rakʿa runs off the end instead of '
      'beginning again', () {
    final cursor = PrayerCursor(5)..moveTo(4);
    cursor.moveTo(0);
    expect(cursor.at, 0);
  });

  test('a word past the end of the set lights nothing at all', () {
    final cursor = PrayerCursor(5)..moveTo(40);
    expect(cursor.at, 4);
    cursor.moveTo(-3);
    expect(cursor.at, 0);
  });

  test('the prayer is rebuilt for an answer that did not move it, so the '
      'screen flickers while somebody is praying', () {
    final cursor = PrayerCursor(5)..moveTo(2);
    var rebuilds = 0;
    cursor.addListener(() => rebuilds++);
    cursor.moveTo(2);
    cursor.moveTo(2);
    expect(
      rebuilds,
      0,
      reason:
          'the voice answers several times a second and '
          'mostly answers the same place twice',
    );
    cursor.moveTo(3);
    expect(rebuilds, 1);
  });
}
