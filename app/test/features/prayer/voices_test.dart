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
  // The set the owner was actually praying when voice-follow was found dead:
  // al-Fātiḥa 1-5, which says ٱلرَّحْمَٰنِ ٱلرَّحِيمِ twice — once in the
  // basmala and once as its own aya. A set that repeats a phrase inside
  // itself is ordinary, and it is the case that broke a rule requiring the
  // best agreement to beat the runner-up by a margin proportional to its own
  // score: the better a window matched, the further ahead of the repeat it
  // was asked to be, so a window that matched the muṣḥaf exactly was refused.
  // Every window of his prayer was refused and the screen never moved.
  test('a phrase the set says twice stops the prayer following at all', () {
    final keys = recitationKeys(_fatiha.split(' ').take(17));
    expect(keys[2], keys[8], reason: 'this set has to repeat, or it tests nothing');

    final exact = locate(keys, 0, 'بِسْمِ اللَّهِ');
    expect(
      exact,
      isNotNull,
      reason: 'the recogniser heard the opening of the set exactly and the '
          'prayer stayed where it was',
    );
    expect(exact!.position, 1);
    expect(exact.score, 1.0);
  });

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
      var advances = 0, lost = 0;
      final ahead = <String>[];
      for (final window in (fixture['windows'] as List)) {
        final moved = followHeard(
          cursor,
          keys,
          window['heard'] as String,
          reach: lost >= followLostAfter ? keys.length : followReach,
        );
        lost = moved ? 0 : lost + 1;
        if (!moved) continue;
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

  // The voice the feature was found broken on, and the only fixture here that
  // is not a professional in a studio — and the only one built from the audio
  // the app itself captured rather than from a recording made beside it.
  //
  // Both of those mattered. Every studio reciter passed while voice-follow
  // advanced twice and stopped on this reader's phone, and a fixture built
  // from his own voice memo passed too: the memo and the app's microphone are
  // the same phone and the same voice, and the recogniser makes noticeably
  // different work of them. Only the app's own audio reproduced the prayer he
  // was actually praying.
  test('the owner recites into Wird itself and the prayer stops following', () {
    final fixture = _fixture('fatiha_reader_heard');
    // al-Fātiḥa 1-5, which is the set the prayer screen was showing him.
    final keys = recitationKeys(_fatiha.split(' ').take(fixture['words'] as int));
    final cursor = PrayerCursor(keys.length);
    var advances = 0, lost = 0;
    for (final window in (fixture['windows'] as List)) {
      final moved = followHeard(
        cursor,
        keys,
        window['heard'] as String,
        reach: lost >= followLostAfter ? keys.length : followReach,
      );
      lost = moved ? 0 : lost + 1;
      if (moved) advances++;
    }

    expect(
      cursor.position,
      greaterThanOrEqualTo(keys.length - 3),
      reason: 'the reader recited the whole set and the prayer reached word '
          '${cursor.position} of ${keys.length} in $advances advances',
    );
    expect(cursor.position, lessThan(keys.length));
  });
}
