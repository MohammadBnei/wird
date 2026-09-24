import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:wird/features/prayer/prayer_cursor.dart';

/// Runs random and adversarial driver input at a cursor, calling [check] after
/// every step with the position the cursor held before it. "Never rewinds" is
/// a property, and a handful of fixtures cannot establish never.
///
/// [PrayerCursor.back] is left out on purpose: it is the reader's own hand on
/// the screen, not a driver's opinion about where the voice went.
void overDrivenInput(void Function(PrayerCursor cursor, int before) check) {
  final random = Random(20260923);
  const extremes = [
    0,
    -1,
    1,
    -4503599627370496,
    9223372036854775807,
    9223372036854775806,
  ];
  for (var run = 0; run < 200; run++) {
    // Including the degenerate sets: a caller that hands this screen an empty
    // one must not take the prayer down.
    final cursor = PrayerCursor(run < 4 ? run - 2 : 1 + random.nextInt(30));
    for (var step = 0; step < 60; step++) {
      final before = cursor.position;
      switch (random.nextInt(8)) {
        case 0:
        case 1:
        case 2:
          cursor.next();
        case 3:
        case 4:
        case 5:
          cursor.follow(random.nextInt(1 << 32) - (1 << 31));
        case 6:
          cursor.follow(extremes[random.nextInt(extremes.length)]);
        default:
          cursor.follow(cursor.position);
      }
      check(cursor, before);
    }
  }
}

void main() {
  test('the prayer jumps back to a word the reader already recited, which '
      'reads as the app having lost them', () {
    overDrivenInput(
      (cursor, before) => expect(
        cursor.position,
        greaterThanOrEqualTo(before),
        reason: 'the cursor went backwards under driver input',
      ),
    );
  });

  test('a driver reporting nonsense leaves the screen with no word to light, '
      'or takes the prayer down in the middle of it', () {
    overDrivenInput((cursor, _) {
      expect(cursor.word, inInclusiveRange(0, cursor.words - 1));
      expect(cursor.reading, greaterThanOrEqualTo(1));
    });
  });

  test('the reciter repeating a word sends the prayer backwards instead of '
      'holding still', () {
    final cursor = PrayerCursor(5)..follow(3);
    cursor
      ..follow(1)
      ..follow(3)
      ..follow(0);
    expect(cursor.position, 3);
  });

  test('the set read a second time inside the same prayer starts the reader '
      'over on the first reading', () {
    final cursor = PrayerCursor(3);
    expect((cursor.word, cursor.reading), (0, 1));
    cursor
      ..next()
      ..next();
    expect((cursor.word, cursor.reading), (2, 1));
    cursor.next();
    expect(
      (cursor.word, cursor.reading),
      (0, 2),
      reason: 'the word wrapped but the reading did not follow it',
    );
  });

  test('a hand reaching backwards is taken for a voice and carries the '
      'prayer on instead', () {
    final cursor = PrayerCursor(5)..follow(3);
    cursor
      ..rewind(4)
      ..rewind(3)
      ..rewind(9);
    expect(cursor.position, 3, reason: 'rewind moved the prayer on');
    cursor.rewind(-8);
    expect(cursor.position, 0, reason: 'rewind ran off the start');
  });

  test('the reader who taps past a word cannot step back to it', () {
    final cursor = PrayerCursor(4)..follow(2);
    cursor.back();
    expect(cursor.position, 1);
    cursor
      ..back()
      ..back();
    expect(cursor.position, 0, reason: 'stepping back ran off the start');
  });
}
