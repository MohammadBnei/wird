import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wird/features/prayer/prayer_cursor.dart';
import 'package:wird/features/prayer/voice_follow.dart';

/// Voice-follow graded against five recitations of two sūras rather than one.
///
/// One recording grades one voice, and a matcher tuned on a single studio
/// reciter was found to follow that reciter perfectly and the owner's own
/// recitation not at all — one advance in twenty-three windows. The readers
/// this is for have accents, slip, and recite in rooms; tajwīd reshapes words
/// and the recogniser does not break them where the muṣḥaf does.
///
/// `scripts/voice-fixture.py` builds these. everyayah serves a file per aya,
/// so concatenating them gives exact aya boundaries and the truth a window is
/// graded against — which aya was being recited then — needs nobody to align
/// anything by hand.
const _fatiha =
    'بِسْمِ ٱللَّهِ ٱلرَّحْمَـٰنِ ٱلرَّحِيمِ ٱلْحَمْدُ لِلَّهِ رَبِّ ٱلْعَـٰلَمِينَ '
    'ٱلرَّحْمَـٰنِ ٱلرَّحِيمِ مَـٰلِكِ يَوْمِ ٱلدِّينِ إِيَّاكَ نَعْبُدُ وَإِيَّاكَ '
    'نَسْتَعِينُ ٱهْدِنَا ٱلصِّرَٰطَ ٱلْمُسْتَقِيمَ صِرَٰطَ ٱلَّذِينَ أَنْعَمْتَ عَلَيْهِمْ '
    'غَيْرِ ٱلْمَغْضُوبِ عَلَيْهِمْ وَلَا ٱلضَّآلِّينَ';

/// How many words each of al-Fātiḥa's seven ayas holds, so an aya boundary in
/// the audio is a word the reciter cannot yet have passed.
const _ayaWords = [4, 4, 2, 3, 4, 3, 9];

Map<String, dynamic> _fixture(String name) =>
    jsonDecode(File('test/fixtures/$name.json').readAsStringSync())
        as Map<String, dynamic>;

void main() {
  // Four reciters, two of them nothing like the studio Ḥuṣarī the matcher was
  // first written against. A voice the matcher cannot follow is a reader who
  // must tap through their whole prayer.
  for (final reciter in ['Alafasy', 'Abdul', 'Minshawy']) {
    test('$reciter recites al-Fātiḥa and the prayer does not follow', () {
      final fixture = _fixture('fatiha_${reciter}_heard');
      final keys = recitationKeys(_fatiha.split(' '));
      final bounds = (fixture['ayas'] as List).cast<Map<String, dynamic>>();

      int couldHaveReached(int ms) {
        var words = 0;
        for (var i = 0; i < bounds.length; i++) {
          words += _ayaWords[i];
          if ((bounds[i]['endMs'] as int) >= ms) break;
        }
        return words - 1;
      }

      final cursor = PrayerCursor(keys.length);
      var advances = 0;
      final ahead = <String>[];
      for (final window in (fixture['windows'] as List)) {
        final was = cursor.position;
        followHeard(cursor, keys, window['heard'] as String);
        if (cursor.position == was) continue;
        advances++;
        final could = couldHaveReached(window['atMs'] as int);
        if (cursor.position > could) {
          ahead.add(
            '${window['atMs']}ms "${window['heard']}" landed on '
            '${cursor.position}, the reciter was no further than $could',
          );
        }
      }

      expect(ahead, isEmpty, reason: ahead.join('\n'));
      expect(
        cursor.position,
        greaterThanOrEqualTo(keys.length - 3),
        reason: 'the prayer was left $advances advances in, on word '
            '${cursor.position} of ${keys.length}',
      );
    });
  }

  // The voice the feature was found broken on, and the only one here that is
  // not a professional in a studio. It is the regression guard for the whole
  // of this: before the matcher ran over letters it advanced once, to word 4,
  // and the reader recited the entire sūra to a screen that did not move.
  test('the owner recites al-Fātiḥa in a room and the prayer does not follow', () {
    final fixture = _fixture('fatiha_reader_heard');
    final keys = recitationKeys(_fatiha.split(' '));
    final cursor = PrayerCursor(keys.length);
    var advances = 0;
    for (final window in (fixture['windows'] as List)) {
      final was = cursor.position;
      followHeard(cursor, keys, window['heard'] as String);
      if (cursor.position != was) advances++;
    }

    expect(
      cursor.position,
      greaterThanOrEqualTo(keys.length - 3),
      reason: 'the reader recited the whole sūra and the prayer reached word '
          '${cursor.position} of ${keys.length} in $advances advances',
    );
    // Reaching the end early and wrapping would read as a second reading the
    // reader never began.
    expect(cursor.position, lessThan(keys.length));
  });
}
