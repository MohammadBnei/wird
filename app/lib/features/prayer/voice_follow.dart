import 'dart:math';

import 'prayer_cursor.dart';

/// Turning what a recogniser heard into a position in the set.
///
/// The app already knows the text, so this is not transcription, it is
/// locating. A hypothesis is matched against the words the set expects next,
/// which is a far smaller question than "what was said" and survives a
/// recogniser that spells badly.
///
/// The rule the whole file is written under: a wrong advance is worse than no
/// advance. Where the answer is not clear nothing moves, and the reader's
/// thumb still works, as it always did.

/// How many of the most recently heard words are matched. A recogniser is
/// asked about the last few seconds, so its tail is the part that describes
/// where the reciter is now; anything earlier only has to agree.
const heardTail = 4;

/// The score below which nothing moves.
///
/// It is a bound and not a fit. Swept from 0.10 to 0.80 against Ḥuṣarī on
/// Al-ʿAlaq 1-5 the wrong-advance count stays at zero throughout, so that
/// recording does not pin this number: a clean studio reciter never puts a
/// hypothesis near the line. What it guards is the room this has not been
/// measured in — a hesitant reader, a fan, a child — and the cost of being
/// conservative there is measured and small: one extra window of lag over the
/// whole of Al-ʿAlaq 1-5. Lower it on evidence from a real room, not on the
/// studio recording, which would only be over-fitting to it.
///
/// The guards below and this one carry the safety together rather than
/// severally: dropping any one of them alone leaves the measurement at zero
/// wrong advances, and dropping this, [_similar]'s floor and [heardTail]
/// together puts four wrong advances into 52 windows.
const followThreshold = 0.62;

/// Two candidates this close together are one answer told twice, and the
/// earlier is taken: the reciter is likelier to be at the first of two places
/// that sound alike than at the second.
const _tie = 0.05;

/// How far past the cursor a window may put the reciter.
///
/// A window describes four seconds of voice and the next one is asked for a
/// second or two later, so the reciter has moved a handful of words since the
/// last one, never a reading. Without this the strongest match for a cursor
/// standing ahead of the reciter — after a tap on the go-on zone, or a brushed
/// one — is the word just recited, found again a whole reading on through the
/// wrap in [_agreement], at a perfect score and with the prayer's own ceiling
/// no help. It is a distance and not an end-of-reading bound on purpose: the
/// reciter who runs straight on into the next reading is one or two positions
/// away, which is what the wrap is there for.
const followReach = 8;

/// The muṣḥaf and a recogniser do not spell one word the same way. One is
/// fully vowelled Uthmani carrying the Qur'anic annotation marks, the other
/// writes plain Arabic and guesses at a hamza. Both sides are reduced to the
/// letters they agree on, which is what makes the Uthmani and the heard
/// spelling of al-insān the same word.
String recitationKey(String word) {
  final letters = StringBuffer();
  for (final rune in word.runes) {
    final folded = switch (rune) {
      0x0622 || 0x0623 || 0x0625 || 0x0627 || 0x0671 => 0x0627, // آ أ إ ا ٱ
      0x0649 => 0x064A, // ى to ي
      0x0629 => 0x0647, // ة to ه
      // The dagger alif is the long ā the muṣḥaf writes above the line and a
      // recogniser writes on it. Spelling it out costs a letter on the few
      // words modern orthography also leaves it off, such as ar-Raḥmān, and
      // buys an exact match on every word where it does not.
      0x0670 => 0x0627,
      _ => rune,
    };
    // Everything a reciter's voice cannot distinguish for us: the harakāt, the
    // sukūn, the waqf marks, tatwīl.
    if (folded >= 0x0621 && folded <= 0x064A && folded != 0x0640) {
      letters.writeCharCode(folded);
    }
  }
  return letters.toString();
}

/// The set's words in the form [locate] compares against.
List<String> recitationKeys(Iterable<String> words) => [
  for (final word in words) recitationKey(word),
];

/// Where the reciter is, in the same straight-through count [PrayerCursor]
/// keeps, or null when the recogniser did not say clearly enough.
///
/// Only positions at or after [from] are considered, so a matcher that is
/// wrong is wrong by standing still or by running ahead, never by proposing
/// the rewind the cursor would refuse anyway. The far end of the search is
/// [followReach] words on, which is as far as a reciter gets between windows.
({int position, double score})? locate(
  List<String> keys,
  int from,
  String heard,
) {
  if (keys.isEmpty) return null;
  final tail = <String>[];
  for (final word in heard.split(RegExp(r'\s+'))) {
    final key = recitationKey(word);
    if (key.isNotEmpty) tail.add(key);
  }
  if (tail.isEmpty) return null;
  final recent = tail.length <= heardTail
      ? tail
      : tail.sublist(tail.length - heardTail);

  var best = (position: from, score: 0.0);
  for (var at = from; at <= from + followReach; at++) {
    final score = _agreement(keys, at, recent);
    if (score > best.score + _tie) best = (position: at, score: score);
  }
  if (best.position <= from || best.score < followThreshold) return null;
  return best;
}

/// How well the words just heard sit against the set read as ending at [at].
/// The last word heard carries the most weight: it is the one that says where
/// the reciter is now, the ones before it only corroborate.
double _agreement(List<String> keys, int at, List<String> recent) {
  var weight = 1.0, total = 0.0, sum = 0.0;
  for (var back = 0; back < recent.length; back++) {
    final index = at - back;
    if (index < 0) break;
    final heard = recent[recent.length - 1 - back];
    sum += weight * _similar(heard, keys[index % keys.length]);
    total += weight;
    weight *= 0.55;
  }
  return total == 0 ? 0 : sum / total;
}

/// ponytail: full edit distance over words of at most a dozen letters. Band it
/// if a set ever runs long enough for this to show on a frame.
double _similar(String heard, String expected) {
  if (heard == expected) return 1;
  if (heard.isEmpty || expected.isEmpty) return 0;
  final ratio =
      1 - _edits(heard, expected) / max(heard.length, expected.length);
  // A third of the letters wrong is not a near miss, it is another word, and
  // giving it partial credit is how a wrong advance gets through.
  return ratio < 0.67 ? 0 : ratio;
}

int _edits(String a, String b) {
  var previous = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final row = List<int>.filled(b.length + 1, 0)..[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      row[j] = min(
        min(row[j - 1] + 1, previous[j] + 1),
        previous[j - 1] + cost,
      );
    }
    previous = row;
  }
  return previous[b.length];
}

/// Hands the cursor what the recogniser just said, and nothing when it is not
/// sure. Every guard that keeps the prayer safe belongs to one of these two
/// calls: [locate] never proposes a rewind, and the cursor refuses one anyway.
void followHeard(PrayerCursor cursor, List<String> keys, String heard) {
  final at = locate(keys, cursor.position, heard);
  if (at != null) cursor.follow(at.position);
}
