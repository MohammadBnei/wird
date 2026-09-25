/// Where in the set the reciter is, from what the recogniser just heard.
///
/// The app already knows the text, so this is not transcription, it is
/// locating — a far smaller question than "what was said", and one that
/// survives a recogniser that spells badly.
///
/// **The rule this file is written under: a wrong place is worse than a late
/// one.** Not "worse than no move" — during ṣalāh the phone is on the floor
/// and the reader cannot touch it until the prayer ends, so a screen that
/// stops following is not degraded, it has failed for the rest of the prayer.
/// Lateness fixes itself as the reciter carries on; a wrong place does not.
///
/// Two things follow from that and they are the whole design:
///
/// **The search covers the whole set.** Not a band ahead of where the screen
/// stands. A reciter whose opening the recogniser garbled is already past any
/// band measured from word zero, and nothing later can reach back to them.
/// Searching everywhere is also what lets a reader repeat an aya — ordinary
/// prayer — and be followed into it rather than dragged onward.
///
/// **The window is short on purpose.** Two dozen letters, four words or so. It
/// is tempting to match a long stretch of what was said, on the grounds that
/// more context tells two copies of ٱلرَّحْمَٰنِ ٱلرَّحِيمِ apart. It does, and it
/// cannot be had: a long window has to be laid against the set in order, the
/// set's letters can only be spent once, and a reciter who repeats an aya
/// therefore aligns *forward* through the text they just repeated. Measured on
/// this repo's own fixtures before the idea was dropped: repeating al-Fātiḥa's
/// third aya moved the reader from word 9 to 11 to 13, into the two ayas after
/// it. Long context and following a repeat are in direct tension. The repeat
/// wins, so the window stays short and the ambiguity is settled by
/// [followMargin] below instead.
library;

import 'dart:math';

import 'voice_follow.dart';

/// How many letters of the tail are matched — roughly the last four words.
/// Short on purpose; see above.
const heardTailLetters = 24;

/// The score below which nothing moves.
///
/// A bound, not a fit. Swept from 0.10 to 0.80 against Ḥuṣarī on Al-ʿAlaq 1-5
/// the wrong-place count stays at zero throughout, so that recording does not
/// pin it: a clean studio reciter never puts a hypothesis near the line. What
/// it guards is the room this has not been measured in — a hesitant reader, a
/// child, a fan running.
const followThreshold = 0.44;

/// What a window short of [heardTailLetters] adds to the bar it must clear.
/// A handful of letters agrees almost anywhere in a run of them, so a teaching
/// pace that puts two words in a window is asked for more certainty than a
/// reader at speed who puts five in.
const followPerLetterShort = 0.01;

/// How far ahead of everywhere else the best place must sit before the prayer
/// moves to it. The guard that does the real work: it is what tells the two
/// copies of a repeated phrase apart, by refusing both.
const followMargin = 0.32;

/// The score above which the word itself is worth pointing at, rather than
/// only the aya it sits in. Below it the place is good enough to turn the page
/// and not good enough to put a finger on a word.
const followSure = 0.8;

/// Two candidates this close together are one answer told twice.
const _tie = 0.05;

/// A set, in the form [locate] reads: every word's letters run together, and
/// for each letter the word it came from.
///
/// Built once per prayer rather than per window. The alternative — rebuilding
/// it on each of the several answers a second — is how a set like 2:282, which
/// the app allows on its own, turns a cheap search into a slow one on the
/// isolate that also has to draw the prayer.
class Recitation {
  Recitation(this.words)
    : _keys = recitationKeys(words),
      _letters = StringBuffer(),
      _wordOf = <int>[] {
    for (var word = 0; word < _keys.length; word++) {
      for (var i = 0; i < _keys[word].length; i++) {
        _wordOf.add(word);
      }
      _letters.write(_keys[word]);
    }
    stream = _letters.toString();
  }

  /// The set's words, as the muṣḥaf writes them.
  final List<String> words;

  final List<String> _keys;
  final StringBuffer _letters;
  final List<int> _wordOf;

  /// Every word's letters, run together.
  late final String stream;

  /// Where each word ends in [stream], which is where a match may land. A
  /// reciter is somewhere in a word, and the question this answers is which
  /// word they have reached.
  late final List<int> ends = [
    for (var end = 1; end <= stream.length; end++)
      if (end == stream.length || _wordOf[end] != _wordOf[end - 1]) end,
  ];

  int wordAt(int letter) => _wordOf[letter];

  bool get isEmpty => stream.isEmpty;
}

/// Which word of [set] the reciter has reached, and how sure that is, or null
/// when no place fits well enough to move to.
///
/// Where the screen currently stands is deliberately not an input. Preferring
/// the nearer of two places that sound alike was tried and removed: it let a
/// window move the prayer on evidence that named two places equally well, and
/// which of them won depended on the order the set was scanned in. Refusing
/// instead costs a window of lag — the reciter carries on, the next window is
/// unambiguous, and the screen catches up — and lateness is the error this is
/// allowed to make.
({int word, double score})? locate(Recitation set, String heard) {
  if (set.isEmpty) return null;

  final spoken = StringBuffer();
  for (final word in heard.split(RegExp(r'\s+'))) {
    spoken.write(recitationKey(word));
  }
  var tail = spoken.toString();
  // Fewer letters than a word is not a place, it is a noise.
  if (tail.length < 4) return null;
  if (tail.length > heardTailLetters) {
    tail = tail.substring(tail.length - heardTailLetters);
  }

  var best = (word: -1, score: 0.0);
  // The best agreement somewhere else entirely. A reciter with an accent, or
  // one who slips, agrees with the muṣḥaf less well everywhere — so how high
  // the best score is says as much about the voice as about the place. What
  // does not depend on the voice is whether one place fits better than the
  // rest, and that is what decides whether the prayer moves.
  var rival = 0.0;
  for (final end in set.ends) {
    final expected = StringBuffer();
    for (var i = end - tail.length; i < end; i++) {
      if (i >= 0) expected.writeCharCode(set.stream.codeUnitAt(i));
    }
    final word = set.wordAt(end - 1);
    final score = _alike(tail, expected.toString());

    if (score > best.score + _tie) {
      if (best.word >= 0 && (word - best.word).abs() >= 2) rival = best.score;
      best = (word: word, score: score);
      continue;
    }
    if (score > rival && best.word >= 0 && (word - best.word).abs() >= 2) {
      rival = score;
    }
  }
  if (best.word < 0) return null;

  // A short window is weak evidence wherever it agrees, because a handful of
  // letters finds agreement almost anywhere in a run of them. It clears a
  // higher bar rather than being thrown away: Ḥuṣarī at a teaching pace puts
  // two words in a window and is followed correctly, a reader at speed puts
  // five in and is followed on the same rule.
  final needed =
      followThreshold + (heardTailLetters - tail.length) * followPerLetterShort;
  if (best.score < needed) return null;
  // One place must fit better than anywhere else by a clear margin, or the
  // window is describing a phrase the set says more than once and moving on it
  // is a guess. This is the guard that replaced the old bound on how far ahead
  // a window could reach, and unlike that bound it does not care which
  // direction the reciter went.
  if (best.score - rival < followMargin) return null;
  return best;
}

/// How alike two runs of letters are, with no floor under it. A reciter with
/// an accent, a reader who slips, and tajwīd reshaping a word all arrive here
/// as a few letters out of a great many, which is a percentage rather than a
/// verdict.
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
