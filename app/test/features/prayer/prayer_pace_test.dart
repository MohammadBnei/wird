import 'package:flutter_test/flutter_test.dart';
import 'package:wird/features/prayer/prayer_cursor.dart';
import 'package:wird/features/prayer/prayer_pace.dart';

/// The clock is the widget tester's fake one: `pump` with a duration is time
/// passing, and nothing here needs a widget.
void main() {
  // 60 words a minute: one word a second, so the clock reads as words.
  ({PrayerCursor cursor, PrayerPace pace, List<bool> ended}) rig({
    required bool voice,
    required bool pace,
    int words = 10,
  }) {
    final cursor = PrayerCursor(words);
    final ended = <bool>[];
    final p = PrayerPace(
      cursor,
      voice: voice,
      pace: pace,
      wpm: 60,
      onEnd: () => ended.add(true),
    );
    return (cursor: cursor, pace: p, ended: ended);
  }

  const second = Duration(seconds: 1);

  testWidgets('a steady pace leaves the text standing, or runs past the end '
      'of the rakʿah', (tester) async {
    final r = rig(voice: false, pace: true, words: 3)..pace.start();
    await tester.pump(second * 2);
    expect(r.cursor.at, 2);
    expect(r.ended, isEmpty);
    await tester.pump(second);
    expect(r.cursor.at, 2);
    expect(r.ended, [true]);
    await tester.pump(second * 5);
    expect(r.ended, [true]);
  });

  testWidgets('the pace runs over a reciter the voice is following', (
    tester,
  ) async {
    final r = rig(voice: true, pace: true)..pace.start();
    for (var s = 0; s < 6; s++) {
      await tester.pump(second);
      r.cursor.moveTo(s + 1);
      r.pace.recognised();
    }
    expect(r.cursor.at, 6);
    expect(r.pace.pacing, isFalse);
    r.pace.dispose();
  });

  testWidgets('a reciter holding a long vowel is taken for lost', (
    tester,
  ) async {
    final r = rig(voice: true, pace: true)..pace.start();
    r.cursor.moveTo(4);
    // The same word, heard again and again for five seconds.
    for (var s = 0; s < 10; s++) {
      await tester.pump(second ~/ 2);
      r.pace.recognised();
    }
    expect(r.cursor.at, 4);
    expect(r.pace.pacing, isFalse);
    r.pace.dispose();
  });

  testWidgets('voice going quiet strands the reader on the last word heard', (
    tester,
  ) async {
    final r = rig(voice: true, pace: true)..pace.start();
    r.cursor.moveTo(2);
    r.pace.recognised();
    await tester.pump(lostAfter);
    expect(r.cursor.at, 2);
    expect(r.pace.pacing, isTrue);
    await tester.pump(second * 2);
    expect(r.cursor.at, 4);
    r.pace.dispose();
  });

  testWidgets("the pace's own steps keep it from ever handing back to the "
      'voice', (tester) async {
    final r = rig(voice: true, pace: true)..pace.start();
    await tester.pump(lostAfter + second * 2);
    expect(r.pace.pacing, isTrue);
    expect(r.cursor.at, 2);
    // The reciter is found again, two words back.
    r.cursor.moveTo(0);
    r.pace.recognised();
    expect(r.pace.pacing, isFalse);
    await tester.pump(second * 2);
    expect(r.cursor.at, 0, reason: 'the pace moved a reciter it had found');
    r.pace.dispose();
  });

  testWidgets('voice alone, or nothing, moves the text on a timer', (
    tester,
  ) async {
    final voiceOnly = rig(voice: true, pace: false)..pace.start();
    final neither = rig(voice: false, pace: false)..pace.start();
    await tester.pump(second * 20);
    expect(voiceOnly.cursor.at, 0);
    expect(neither.cursor.at, 0);
  });

  testWidgets('a prayer left in the background goes on without the reader', (
    tester,
  ) async {
    final r = rig(voice: false, pace: true)..pace.start();
    await tester.pump(second);
    r.pace.pause();
    await tester.pump(second * 30);
    expect(r.cursor.at, 1);
    r.pace.start();
    await tester.pump(second);
    expect(r.cursor.at, 2);
    r.pace.dispose();
  });
}
