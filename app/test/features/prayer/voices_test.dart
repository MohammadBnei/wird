import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wird/features/prayer/prayer_cursor.dart';
import 'package:wird/features/prayer/alignment.dart';
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
  // The two things a reciter does that the app could not follow until
  // 2026-09-25, and which nothing covered because the cursor refused them by
  // construction. Both are ordinary prayer, and during ṣalāh there is no hand
  // coming to correct the screen if it will not go with them.
  group('what a reciter does and the screen would not', () {
    final words = _fatiha.split(' ').take(17).toList();
    final set = Recitation(words);
    // 0 بسم 1 الله 2 الرحمن 3 الرحيم | 4 الحمد 5 لله 6 رب 7 العالمين
    // 8 الرحمن 9 الرحيم | 10 مالك 11 يوم 12 الدين | 13 اياك 14 نعبد
    // 15 واياك 16 نستعين

    test('the reciter goes back an aya and is dragged onward instead', () {
      final cursor = PrayerCursor(set.words.length);
      cursor.moveTo(locate(set, 'مَالِكِ يَوْمِ الدِّينِ')!.word);
      expect(cursor.at, 12);

      // They go back to the second aya and say it again.
      final back = locate(set, 'الْحَمْدُ لِلَّهِ رَبِّ الْعَالَمِينَ');
      expect(back, isNotNull, reason: 'the reciter said a whole aya of the '
          'set and the screen had nothing to say about it');
      cursor.moveTo(back!.word);
      expect(cursor.at, 7, reason: 'the screen stayed at 12 while the reciter '
          'was four words behind it, for the rest of the prayer');
    });

    test('the recogniser warming up carries the prayer off word one', () {
      // A streaming model starts with no left context — this one wants 128
      // frames of it — so the opening of a prayer comes back short. It costs
      // nothing, and this is why: the screen starts on word 0, which is where
      // the reciter starts, so there is nowhere to be carried from. What
      // matters is that the fragment is refused rather than acted on.
      expect(locate(set, 'هي'), isNull);
      expect(locate(set, 'ااهِ'), isNull);
    });

    test('what the recogniser writes and what the muṣḥaf writes are two '
        'different alphabets', () {
      // The recogniser writes Qur'anic phonemes, and until 2026-09-27 the fold
      // both sides pass through knew only the muṣḥaf's letters: a madd came
      // back as ۦۦۦۦ and was dropped entirely, gemination came back as the
      // letter twice and stayed doubled. Neither is a different word, and a
      // fold that cannot say so puts the whole recitation out of reach.
      //
      // These are the recogniser's own output on the owner's prayer, beside
      // the muṣḥaf's spelling of the same words.
      expect(recitationKey('رَحِۦۦۦۦم'), recitationKey('ٱلرَّحِيمِ').substring(1));
      expect(recitationKey('ءِييَااكَ'), recitationKey('إِيَّاكَ'));
      expect(recitationKey('رَببِ'), recitationKey('رَبِّ'));
      expect(recitationKey('صِرَااطَ'), recitationKey('ٱلصِّرَٰطَ').substring(1));
      // Not everything closes, and the one that does not is worth naming: the
      // muṣḥaf writes no alif in لِلَّهِ and the reciter holds the ā anyway, so
      // the two spellings stand a letter apart whatever the fold does. That is
      // a percentage of a window rather than a verdict on it, which is the
      // whole reason the matching is over letters — and the real opening of
      // al-Fātiḥa, as this recogniser wrote it, still lands where it should.
      expect(recitationKey('لِللَااهِ'), isNot(recitationKey('لِلَّهِ')));
      // And the repeat guard reads the new alphabet as it read the old one:
      // بِسْمِ ٱللَّهِ names one place in this set and moves, while the same window
      // grown as far as ٱلرَّحْمَـٰنِ ٱلرَّحِيمِ names the basmala and the third aya
      // equally well, and is refused rather than guessed at.
      expect(locate(set, 'بِسمِللَااهِررَ')?.word, 1);
      expect(locate(set, 'بِسمِللَااهِررَحمَاانِررَحِۦۦم'), isNull);
    });

    test('the set begun again for the next rakʿa runs off the end', () {
      final cursor = PrayerCursor(set.words.length)..moveTo(16);

      // The transcript never resets — one stream lives for the whole prayer —
      // so the next rakʿa arrives as more words on the end of the same
      // recitation, and the only thing that says "they have started again" is
      // that what they are saying now is the opening of the set.
      final again = locate(set, 'بِسْمِ اللَّهِ');
      expect(again, isNotNull);
      cursor.moveTo(again!.word);
      expect(cursor.at, 1, reason: 'the second rakʿa was prayed against a '
          'screen frozen on the last aya of the first');
    });
  });

  // The set the owner was actually praying when voice-follow was found dead:
  // al-Fātiḥa 1-5, which says ٱلرَّحْمَٰنِ ٱلرَّحِيمِ twice — once in the
  // basmala and once as its own aya. A set that repeats a phrase inside
  // itself is ordinary, and it is the case that broke a rule requiring the
  // best agreement to beat the runner-up by a margin proportional to its own
  // score: the better a window matched, the further ahead of the repeat it
  // was asked to be, so a window that matched the muṣḥaf exactly was refused.
  // Every window of his prayer was refused and the screen never moved.
  test('a phrase the set says twice stops the prayer following at all', () {
    final words = _fatiha.split(' ').take(17).toList();
    final set = Recitation(words);
    expect(
      recitationKey(words[2]),
      recitationKey(words[8]),
      reason: 'this set has to repeat, or it tests nothing',
    );

    // The opening of the set as this recogniser actually wrote it, reciter
    // by reciter — not an invented spelling.
    final exact = locate(set, 'بِسمِللَااهِررَ');
    expect(
      exact,
      isNotNull,
      reason: 'the recogniser heard the opening of the set and the prayer '
          'stayed where it was',
    );
    expect(exact!.word, 1);
  });

  // Four reciters, two of them nothing like the studio Ḥuṣarī the matcher was
  // first written against. A voice the matcher cannot follow is a reader who
  // must tap through their whole prayer.
  for (final reciter in ['Alafasy', 'Abdul', 'Minshawy']) {
    test('$reciter recites al-Fātiḥa and the prayer does not follow', () {
      final fixture = _fixture('fatiha_${reciter}_heard');
      final set = Recitation(_fatiha.split(' '));
      final bounds = (fixture['ayas'] as List).cast<Map<String, dynamic>>();

      int couldHaveReached(int ms) {
        var words = 0;
        for (var i = 0; i < bounds.length; i++) {
          words += _ayaWords[i];
          if ((bounds[i]['endMs'] as int) >= ms) break;
        }
        return words - 1;
      }

      final cursor = PrayerCursor(set.words.length);
      var advances = 0;
      final ahead = <String>[];
      for (final window in (fixture['windows'] as List)) {
        final was = cursor.at;
        final at = locate(set, window['heard'] as String);
        if (at != null) cursor.moveTo(at.word);
        if (cursor.at == was) continue;
        advances++;
        final could = couldHaveReached(window['atMs'] as int);
        if (cursor.at > could) {
          ahead.add(
            '${window['atMs']}ms "${window['heard']}" landed on '
            '${cursor.at}, the reciter was no further than $could',
          );
        }
      }

      expect(ahead, isEmpty, reason: ahead.join('\n'));
      expect(
        cursor.at,
        greaterThanOrEqualTo(set.words.length - 3),
        reason: 'the prayer was left $advances advances in, on word '
            '${cursor.at} of ${set.words.length}',
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
    final set = Recitation(
      _fatiha.split(' ').take(fixture['words'] as int).toList(),
    );
    final cursor = PrayerCursor(set.words.length);
    var advances = 0;
    for (final window in (fixture['windows'] as List)) {
      final was = cursor.at;
      final at = locate(set, window['heard'] as String);
      if (at != null) cursor.moveTo(at.word);
      if (cursor.at != was) advances++;
    }

    expect(
      cursor.at,
      greaterThanOrEqualTo(set.words.length - 3),
      reason: 'the reader recited the whole set and the prayer reached word '
          '${cursor.at} of ${set.words.length} in $advances advances',
    );
    expect(cursor.at, lessThan(set.words.length));
  });
}
