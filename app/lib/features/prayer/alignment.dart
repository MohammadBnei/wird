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

/// How far ahead of another place the best one must sit before the prayer
/// moves, for two places whose text has nothing in common. Places that share
/// text are asked for less, in proportion: see [Recitation.twin].
///
/// This is the guard that does the real work. Asked of every pair alike, it
/// refused every window on a set that says a phrase twice — al-Fātiḥa's
/// ٱلرَّحْمَٰنِ ٱلرَّحِيمِ, in every rakʿah — and the cursor pinned (ADR 0019).
const followMargin = 0.32;

/// How alike the set's own text must be at two places for them to be one
/// phrase said twice — copies, settled by order, rather than places told
/// apart by the margin. Swept on the bench at 0.9, 0.8, 0.75 and 0.7: no wrong
/// place at any, fewest windows behind at 0.7. At 0.9 the basmala opening a
/// second rakʿah — 1:3's near-copy — was refused and the reader had to recite
/// on into 1:2.
const followCopy = 0.7;

/// The least margin asked of any pair that is not a copy, however alike the
/// set says they are. Below it the difference is the recogniser's spelling,
/// not the reciter's place: al-Fātiḥa's 1:3 lost to the passage's first word
/// at a margin of 0.07 and the cursor jumped twenty words.
const followMarginFloor = 0.15;

/// How many more letters of the set than were heard a place is read against.
/// Connected recitation drops letters the muṣḥaf writes — وَلَا ٱلضَّآلِّينَ is
/// said walaḍ-ḍāllīn — and a window exactly as long as what was heard then
/// pushed its first letters out of reach: the last word of al-Fātiḥa could
/// not be named.
const followSlack = 6;

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

  /// The [length] letters of the set that end at [end], or fewer near its
  /// start.
  String expected(int end, int length) =>
      stream.substring(max(0, end - length), end);

  final _twins = <(int, int, int), double>{};

  /// How alike the set's own text is at two places, read as a window of
  /// [length] letters ending at each: 1 for a phrase the set says twice, near
  /// 0 for two places with nothing in common.
  ///
  /// This is what a perfect recitation at [a] would score at [b], so `1 - twin`
  /// is the most margin any voice could ever give between them. The margin
  /// asked of a window is a share of that, not a constant: the set says before
  /// a word is spoken which of its places are hard to tell apart.
  double twin(int a, int b, int length) => _twins.putIfAbsent((
    length,
    min(a, b),
    max(a, b),
  ), () => _alike(expected(a, length), expected(b, length + followSlack)));

  bool get isEmpty => stream.isEmpty;
}

/// Which word of [set] the reciter has reached, and how sure that is, or null
/// when no place fits well enough to move to.
///
/// Where the screen stands, [from], settles only a phrase the set says more
/// than once, word for word (see [explain]). Places that merely sound alike
/// are still told apart by the margin alone: preferring the nearer of those
/// was tried and removed, because it moved the prayer on evidence that named
/// two places equally well.
({int word, double score})? locate(Recitation set, String heard, {int? from}) {
  final said = explain(set, heard, from: from);
  if (said == null) return null;
  if (said.score < said.needed) return null;
  if (said.score - said.rival < said.margin) return null;
  return (word: said.word, score: said.score);
}

/// The same search, with its workings, for the screen in Settings that exists
/// to say why the prayer is not moving. [locate] is this plus the two gates:
///
/// - **fit**: `score` must reach `needed`.
/// - **clear**: `score - rival` must reach `margin`, where `rival` is the place
///   two or more words away that comes closest to failing that, and `margin`
///   is what that pair is asked for ([followMargin] scaled by
///   [Recitation.twin]).
///
/// A phrase the set says word for word in more than one place ([followCopy])
/// cannot be placed by what was heard at all. Those places are `copies`, and
/// with [from] the first of them at or after it is taken: a reciter is at or
/// past the cursor, so the nearest copy ahead of it is never ahead of them —
/// at worst it is late. With every copy behind [from], or no [from], they
/// hold. The margin is then asked against every place that is not a copy.
///
/// Kept as one implementation rather than two: a diagnosis that does not run
/// the code being diagnosed is worth nothing, and this screen was written
/// because four builds went to a reader with nobody able to see what their
/// phone was doing.
({
  int word,
  double score,
  double needed,
  double rival,
  double margin,
  int copies,
})?
explain(Recitation set, String heard, {int? from}) {
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

  final scores = [
    for (final end in set.ends)
      _alike(tail, set.expected(end, tail.length + followSlack)),
  ];

  // The best place. Two ends within [_tie] of each other are one answer told
  // twice, and the earlier one is kept: late, never ahead.
  var best = 0;
  for (var i = 1; i < scores.length; i++) {
    if (scores[i] > scores[best] + _tie) best = i;
  }
  final bestEnd = set.ends[best];
  int wordOf(int i) => set.wordAt(set.ends[i] - 1);
  double asked(int i) => max(
    followMarginFloor,
    followMargin * (1 - set.twin(bestEnd, set.ends[i], tail.length)),
  );

  // The places that say what the best one says, and score as well.
  final copies = [
    for (var i = 0; i < scores.length; i++)
      if (i == best ||
          ((wordOf(i) - wordOf(best)).abs() >= 2 &&
              set.twin(bestEnd, set.ends[i], tail.length) >= followCopy &&
              scores[best] - scores[i] < asked(i)))
        i,
  ];
  // Settled when there is one, or when order picks one of them.
  final ahead = [
    for (final i in copies)
      if (from != null && wordOf(i) >= from - 1) wordOf(i),
  ];
  final settled = copies.length == 1 || ahead.isNotEmpty;
  final word = copies.length == 1 || ahead.isEmpty
      ? wordOf(best)
      : ahead.reduce(min);

  // The competitor that comes closest to holding the prayer where it is. A
  // reciter with an accent agrees with the muṣḥaf less well everywhere, so how
  // high the best score is says as much about the voice as about the place;
  // what does not depend on the voice is whether one place fits better than
  // the rest. Settled copies are no rivals; unsettled, each one holds.
  var rival = 0.0, margin = followMargin, slack = double.infinity;
  for (var i = 0; i < scores.length; i++) {
    final near = settled ? copies : [best];
    if (near.any((c) => (wordOf(i) - wordOf(c)).abs() < 2)) continue;
    final gap = scores[best] - scores[i];
    // Clears even the margin asked of two unrelated places: no need to ask
    // the set how alike they are.
    if (gap >= followMargin && gap - followMargin >= slack) continue;
    final need = asked(i);
    if (gap - need < slack) {
      slack = gap - need;
      rival = scores[i];
      margin = need;
    }
  }

  // A short window is weak evidence wherever it agrees, because a handful of
  // letters finds agreement almost anywhere in a run of them. It clears a
  // higher bar rather than being thrown away: Ḥuṣarī at a teaching pace puts
  // two words in a window and is followed correctly, a reader at speed puts
  // five in and is followed on the same rule.
  final needed =
      followThreshold + (heardTailLetters - tail.length) * followPerLetterShort;
  return (
    word: word,
    score: scores[best],
    needed: needed,
    rival: rival,
    margin: margin,
    copies: copies.length,
  );
}

/// How alike what was heard is to the set's letters ending at a place, with
/// no floor under it. A reciter with an accent, a reader who slips, and tajwīd
/// reshaping a word all arrive here as a few letters out of a great many,
/// which is a percentage rather than a verdict.
///
/// The match must end where the place ends but may start anywhere in
/// [expected]: letters of the set before what was heard are not errors. A
/// recogniser that began a new utterance hears less than a full window, and
/// charging it for the set's letters before that put every place but the
/// first in the set at a disadvantage — al-Fātiḥa's basmala then beat its
/// exact twin before the passage.
double _alike(String heard, String expected) {
  if (heard.isEmpty || expected.isEmpty) return 0;
  return max(0, 1 - _edits(heard, expected) / heard.length);
}

/// Edits to turn [a] into a run of [b] that ends where [b] ends.
int _edits(String a, String b) {
  // Row 0 is free: [b] may be entered at any letter.
  var previous = List<int>.filled(b.length + 1, 0);
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
