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

/// How many letters of the tail are matched. A recogniser and a muṣḥaf do not
/// break words in the same places, so the comparison runs over letters; this
/// is roughly the last four words of recitation.
const heardTailLetters = 24;

/// What a window short of [heardTailLetters] adds to the bar it must clear.
/// A handful of letters finds agreement almost anywhere in a run of them, so
/// a teaching pace that puts two words in a window is asked for more
/// certainty than a reader at speed who puts five in.
const followPerLetterShort = 0.01;

const followMargin = 0.55;

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
/// severally: no one of them holds the measurement on its own.
const followThreshold = 0.44;

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

  // The set as one run of letters, and which word each letter belongs to. A
  // recogniser and a muṣḥaf do not agree on where a word ends — مَالِكِ comes
  // back as `فلا ك`, إِيَّاكَ as `يا ك` — so matching token against token
  // misaligns everything after the first split, however well the letters
  // agree. Letters are the coordinate system both sides share.
  final letters = StringBuffer();
  final wordOf = <int>[];
  for (var word = 0; word < keys.length; word++) {
    for (var i = 0; i < keys[word].length; i++) {
      wordOf.add(word);
    }
    letters.write(keys[word]);
  }
  final stream = letters.toString();
  if (stream.isEmpty) return null;

  final spoken = StringBuffer();
  for (final word in heard.split(RegExp(r'\s+'))) {
    spoken.write(recitationKey(word));
  }
  var tail = spoken.toString();
  // Fewer letters than a word is not a position, it is a noise.
  if (tail.length < 4) return null;
  if (tail.length > heardTailLetters) {
    tail = tail.substring(tail.length - heardTailLetters);
  }

  // Where the cursor stands, as a letter offset into the endlessly repeated
  // stream: the prayer counts straight through every reading of the set.
  var at = (from ~/ keys.length) * stream.length;
  for (var word = 0; word < from % keys.length; word++) {
    at += keys[word].length;
  }
  at += keys[from % keys.length].length;

  var reach = 0;
  for (var step = 0; step <= followReach; step++) {
    reach += keys[(from + 1 + step) % keys.length].length;
  }

  // Only where a word ends. The reciter is asked which word they have just
  // finished, and an alignment that stops halfway through one answers a
  // question nobody asked — while letting a four-letter tail find agreement
  // almost anywhere in a run of letters.
  final ends = <int>[];
  for (var end = at + 1; end <= at + reach; end++) {
    final next = end % stream.length;
    if (next == 0 || wordOf[next] != wordOf[next - 1]) ends.add(end);
  }

  var best = (position: from, score: 0.0);
  // The best agreement somewhere else entirely. A reciter with an accent, or
  // one who slips, agrees with the muṣḥaf less well everywhere — so how high
  // the best score is says as much about the voice as about the place, and a
  // bar set by a studio reciter shuts that reader out. What does not depend
  // on the voice is whether one place fits better than the rest.
  var rival = 0.0;
  for (final end in ends) {
    final expected = StringBuffer();
    for (var i = end - tail.length; i < end; i++) {
      expected.writeCharCode(stream.codeUnitAt(i % stream.length));
    }
    final position =
        (end - 1) ~/ stream.length * keys.length +
        wordOf[(end - 1) % stream.length];
    // The letters run past the word the reach allows, so the bound is held
    // here rather than by where the search stopped.
    if (position > from + followReach) continue;
    // A reciter who runs straight on into the next reading arrives at its
    // first word, not at its seventh. Anything further in is the same phrase
    // found again a reading on — every word of the set repeats there — and
    // taking it costs the reader the whole reading they were in.
    if (position ~/ keys.length > from ~/ keys.length &&
        position % keys.length > 1) {
      continue;
    }
    final score = _alike(tail, expected.toString());
    if (score <= best.score + _tie) {
      if (score > rival && (position - best.position).abs() >= 2) rival = score;
      continue;
    }
    if (best.score > rival && (position - best.position).abs() >= 2) {
      rival = best.score;
    }
    best = (position: position, score: score);
  }
  // A short tail is weak evidence wherever it agrees, because a handful of
  // letters finds agreement almost anywhere in a run of them. It clears a
  // higher bar rather than being thrown away: Ḥuṣarī at a teaching pace puts
  // two words in a window and is followed correctly, a reader at speed puts
  // five in and is followed on the same rule.
  final needed =
      followThreshold + (heardTailLetters - tail.length) * followPerLetterShort;
  if (best.position <= from || best.score < needed) return null;
  // One place has to fit better than anywhere else by a clear margin, or the
  // window is describing a phrase the set says more than once and moving on
  // it is a guess.
  if (best.score - rival < best.score * followMargin) return null;
  return best;
}

/// How alike two runs of letters are, with no floor under it. A reciter with
/// an accent, a reader who slips, and tajwīd reshaping a word all arrive here
/// as a few letters out of a great many, which is a percentage rather than a
/// verdict — and a run this long disagreeing in a few letters is one
/// recitation spelled two ways.
double _alike(String heard, String expected) {
  if (heard.isEmpty || expected.isEmpty) return 0;
  return 1 - _edits(heard, expected) / max(heard.length, expected.length);
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
