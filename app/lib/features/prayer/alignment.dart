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
/// wins, so the window stays short and the ambiguity is settled by the margin
/// ([FollowTuning.margin]) instead.
///
/// Every number this file decides with is a field of [FollowTuning], with the
/// measurement that set it beside it. The bench
/// (`test/features/prayer/follow_bench_test.dart`) replays every recording and
/// trail through [explain] and can sweep any of them: change a number there,
/// not here, and read the table before committing it.
library;

import 'dart:math';

import 'voice_follow.dart';

/// The numbers the matcher decides with. One object rather than a constant
/// each, so the bench can sweep any of them without editing this file:
/// `FollowTuning(margin: 0.26)` is the defaults with one knob turned.
class FollowTuning {
  const FollowTuning({
    this.tailLetters = 24,
    this.threshold = 0.44,
    this.perLetterShort = 0.01,
    this.margin = 0.32,
    this.marginFloor = 0.15,
    this.repeat = 0.7,
    this.repeatReach = 12,
    this.slack = 6,
    this.sure = 0.8,
    this.tie = 0.05,
  });

  /// How many letters of what was heard are matched — roughly the last four
  /// words. Short on purpose; see the top of this file.
  final int tailLetters;

  /// The score below which nothing moves.
  ///
  /// A bound, not a fit. Swept from 0.10 to 0.80 against Ḥuṣarī on Al-ʿAlaq
  /// 1-5 the wrong-place count stays at zero throughout, so that recording
  /// does not pin it: a clean studio reciter never puts a hypothesis near the
  /// line. What it guards is the room this has not been measured in — a
  /// hesitant reader, a child, a fan running.
  final double threshold;

  /// What a window short of [tailLetters] adds to the bar it must clear. A
  /// handful of letters agrees almost anywhere in a run of them, so a teaching
  /// pace that puts two words in a window is asked for more certainty than a
  /// reader at speed who puts five in.
  final double perLetterShort;

  /// How far ahead of another place the best one must sit before the prayer
  /// moves, for two places whose text has nothing in common. Places that share
  /// text are asked for less, in proportion: see [Recitation.sameText].
  ///
  /// Asked of every pair alike, it refused every window on a set that says a
  /// phrase twice — al-Fātiḥa's ٱلرَّحْمَٰنِ ٱلرَّحِيمِ, in every rakʿah — and
  /// the cursor pinned (ADR 0020). Swept at 0.2 to 0.4: alike up to 0.32,
  /// three conditions fail at 0.4.
  final double margin;

  /// The least margin asked of any pair that is not a repeat, however alike
  /// the set says they are. Below it the difference is the recogniser's
  /// spelling, not the reciter's place: al-Fātiḥa's 1:3 lost to the passage's
  /// first word at a margin of 0.07 and the cursor jumped twenty words. The
  /// bench lags less at 0.05 or 0.1, but cannot see that jump — the trail it
  /// came from has no truth to grade against — so a test pins it instead.
  final double marginFloor;

  /// How alike the set's own text must be at two places for them to be one
  /// phrase said twice — a repeat, settled by order, rather than places told
  /// apart by the margin. Swept on the bench at 0.9, 0.8, 0.75 and 0.7: no
  /// wrong place at any, fewest windows behind at 0.7. At 0.9 the basmala
  /// opening a second rakʿah — 1:3's near-repeat — was refused and the reader
  /// had to recite on into 1:2.
  final double repeat;

  /// How many words past the cursor a repeat may be taken by order. The
  /// nearest repeat at or after the cursor is never ahead of a reciter who is
  /// at or past it — but the cursor can be past the reciter, put there by the
  /// pace or left there by a reader going back, and then the nearest repeat
  /// ahead of it is ahead of them too. Bounded, the worst such guess is one
  /// aya; past it the prayer waits. Swept at 4, 8, 12 and 20: 4 fails a
  /// condition, the rest are alike.
  final int repeatReach;

  /// How many more letters of the set than were heard a place is read
  /// against. Connected recitation drops letters the muṣḥaf writes — وَلَا
  /// ٱلضَّآلِّينَ is said walaḍ-ḍāllīn — and a window exactly as long as what
  /// was heard pushed its first letters out of reach: the last word of
  /// al-Fātiḥa could not be named. Swept on the bench at 0, 3, 6 and 9: six
  /// conditions fail at 0, one at 3, none at 6 or 9.
  final int slack;

  /// The score above which a recognition counts as sure for the pace, which
  /// steps the words on when nothing sure has come for a while.
  final double sure;

  /// Two places this close in score are one answer told twice, and the
  /// earlier is kept: late, never ahead.
  final double tie;
}

/// Why the prayer moved or did not, which the trail, the Settings check and
/// the bench all print: one decision, worded three ways.
enum Verdict {
  /// Fewer letters than a word: a noise, not a place.
  tooLittle,

  /// The best place does not fit well enough ([FollowTuning.threshold]).
  lowFit,

  /// Another place fits nearly as well ([FollowTuning.margin]).
  unclear,

  /// The set says this phrase more than once, and no copy of it is at or
  /// just after the cursor ([FollowTuning.repeatReach]): order cannot say
  /// which.
  repeatNotAhead,

  /// The prayer moves to [Placing.word].
  move,
}

/// Where [explain] puts the reciter, and its workings.
typedef Placing = ({
  Verdict verdict,

  /// The word of the set, or -1 for [Verdict.tooLittle].
  int word,
  double score,

  /// The score [word] had to reach.
  double needed,

  /// The place two or more words away that came closest to holding the
  /// prayer, and the margin that pair was asked for.
  double rival,
  double margin,

  /// How many places of the set say what was heard; more than one is a
  /// phrase the set repeats.
  int repeats,

  /// How many letters of what was heard were matched.
  int letters,
});

/// A set, in the form [explain] reads: every word's letters run together,
/// and for each letter the word it came from.
///
/// Built once per rakʿah rather than per window. The alternative — rebuilding
/// it on each of the several answers a second — is how a set like 2:282,
/// which the app allows on its own, turns a cheap search into a slow one on
/// the isolate that also has to draw the prayer.
class Recitation {
  Recitation(this.words, [this.tuning = const FollowTuning()])
    : _wordOf = <int>[] {
    final keys = recitationKeys(words);
    final letters = StringBuffer();
    for (var word = 0; word < keys.length; word++) {
      for (var i = 0; i < keys[word].length; i++) {
        _wordOf.add(word);
      }
      letters.write(keys[word]);
    }
    stream = letters.toString();
  }

  /// The set's words, as the muṣḥaf writes them.
  final List<String> words;

  /// The numbers this set is matched with. On the set rather than passed per
  /// window, because [sameText] caches what they decide.
  final FollowTuning tuning;

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

  final _sameText = <(int, int, int), double>{};

  /// How alike the set's own text is at two places, read as a window of
  /// [length] letters ending at each: 1 for a phrase the set says twice, near
  /// 0 for two places with nothing in common.
  ///
  /// This is what a perfect recitation at one would score at the other, so
  /// `1 - sameText` is the most margin any voice could give between them. The
  /// margin asked of a window is a share of that, not a constant: the set says
  /// before a word is spoken which of its places are hard to tell apart.
  ///
  /// Read both ways and the higher kept, so the answer does not depend on
  /// which of the two was the best place first: near the start of the set one
  /// window is shorter than the other, and the two readings differ.
  double sameText(int a, int b, int length) => _sameText.putIfAbsent(
    (length, min(a, b), max(a, b)),
    () => max(
      _alike(expected(a, length), expected(b, length + tuning.slack)),
      _alike(expected(b, length), expected(a, length + tuning.slack)),
    ),
  );

  bool get isEmpty => stream.isEmpty;
}

/// Which word of [set] the reciter has reached, and how sure that is, or null
/// when the prayer should not move: [explain] with any verdict but
/// [Verdict.move] read as no place.
({int word, double score})? locate(
  Recitation set,
  String heard, {
  int? cursor,
}) {
  final said = explain(set, heard, cursor: cursor);
  return said.verdict == Verdict.move
      ? (word: said.word, score: said.score)
      : null;
}

/// Where [heard] puts the reciter in [set], with the reason the prayer
/// should or should not move there.
///
/// 1. **Score** every word end against the tail of what was heard.
/// 2. **Best**: the highest, the earliest of any that tie with it.
/// 3. **Repeats**: other places whose own text says what the best place says
///    ([FollowTuning.repeat]) and that score as well. Audio cannot tell them
///    apart; only order can. With [cursor] — where the screen stands, in
///    [set]'s words — the first repeat at or after it, within
///    [FollowTuning.repeatReach], is taken. A reciter is at or past the
///    cursor, so that is never ahead of them; past the reach the guess is not
///    worth making.
/// 4. **Rival**: of the places that are not repeats, the one that comes
///    closest to the place taken, and the margin that pair is asked for.
/// 5. **Verdict**: [Verdict.lowFit] under the bar, [Verdict.unclear] inside
///    the margin, [Verdict.repeatNotAhead] when order cannot choose, else
///    [Verdict.move].
///
/// Where the screen stands settles only a phrase the set repeats. Places that
/// merely sound alike are told apart by the margin alone: preferring the
/// nearer of those was tried and removed, because it moved the prayer on
/// evidence that named two places equally well.
///
/// One implementation for the prayer, the Settings check and the bench: a
/// diagnosis that does not run the code being diagnosed is worth nothing.
Placing explain(Recitation set, String heard, {int? cursor}) {
  final t = set.tuning;
  final tail = _tail(heard, t.tailLetters);
  // Fewer letters than a word is not a place, it is a noise.
  if (set.isEmpty || tail.length < 4) {
    return (
      verdict: Verdict.tooLittle,
      word: -1,
      score: 0,
      needed: 0,
      rival: 0,
      margin: 0,
      repeats: 0,
      letters: tail.length,
    );
  }

  final scores = [
    for (final end in set.ends)
      _alike(tail, set.expected(end, tail.length + t.slack)),
  ];
  int wordOf(int i) => set.wordAt(set.ends[i] - 1);
  final best = _best(scores, t.tie);
  double asked(int i) => max(
    t.marginFloor,
    t.margin * (1 - set.sameText(set.ends[best], set.ends[i], tail.length)),
  );

  final repeats = [
    for (var i = 0; i < scores.length; i++)
      if (i == best ||
          ((wordOf(i) - wordOf(best)).abs() >= 2 &&
              // Cheap first: no place further behind than the full margin
              // can be a repeat, and most of the set is.
              scores[best] - scores[i] < t.margin &&
              set.sameText(set.ends[best], set.ends[i], tail.length) >=
                  t.repeat &&
              scores[best] - scores[i] < asked(i)))
        i,
  ];
  final taken = repeats.length == 1
      ? best
      : _nextRepeat(repeats, wordOf, cursor, t.repeatReach);

  // The rival: a reciter with an accent agrees with the muṣḥaf less well
  // everywhere, so how high the score is says as much about the voice as
  // about the place. What does not depend on the voice is whether one place
  // fits better than the rest. Settled repeats are no rivals of each other.
  final at = taken ?? best;
  final near = [
    for (final i in taken == null ? [best] : repeats) wordOf(i),
  ];
  var rival = 0.0, margin = t.margin, headroom = double.infinity;
  for (var i = 0; i < scores.length; i++) {
    if (near.any((w) => (wordOf(i) - w).abs() < 2)) continue;
    final gap = scores[at] - scores[i];
    // Clears even the margin asked of two unrelated places: no need to ask
    // the set how alike they are.
    if (gap >= t.margin && gap - t.margin >= headroom) continue;
    final need = asked(i);
    if (gap - need < headroom) {
      headroom = gap - need;
      rival = scores[i];
      margin = need;
    }
  }

  // A short window is weak evidence wherever it agrees, because a handful of
  // letters finds agreement almost anywhere in a run of them. It clears a
  // higher bar rather than being thrown away: Ḥuṣarī at a teaching pace puts
  // two words in a window and is followed correctly, a reader at speed puts
  // five in and is followed on the same rule.
  final needed = t.threshold + (t.tailLetters - tail.length) * t.perLetterShort;
  final score = scores[at];
  return (
    verdict: score < needed
        ? Verdict.lowFit
        : taken == null
        ? Verdict.repeatNotAhead
        : score - rival < margin
        ? Verdict.unclear
        : Verdict.move,
    word: wordOf(at),
    score: score,
    needed: needed,
    rival: rival,
    margin: margin,
    repeats: repeats.length,
    letters: tail.length,
  );
}

/// What was heard, folded the way the set is, and cut to its last [letters].
String _tail(String heard, int letters) {
  final spoken = StringBuffer();
  for (final word in heard.split(RegExp(r'\s+'))) {
    spoken.write(recitationKey(word));
  }
  final all = spoken.toString();
  return all.length > letters ? all.substring(all.length - letters) : all;
}

/// The best score's index, or the earliest within [tie] of it. Measured from
/// the top rather than chained from the first, so a run of scores rising by
/// less than [tie] each still ends at its peak.
int _best(List<double> scores, double tie) {
  final top = scores.reduce(max);
  return scores.indexWhere((s) => s >= top - tie);
}

/// Of [repeats], the one whose word is at or after [cursor] and within
/// [reach] of it, the nearest first; null when there is none, or no cursor.
int? _nextRepeat(
  List<int> repeats,
  int Function(int) wordOf,
  int? cursor,
  int reach,
) {
  if (cursor == null) return null;
  int? taken;
  for (final i in repeats) {
    final w = wordOf(i);
    if (w < cursor || w > cursor + reach) continue;
    if (taken == null || w < wordOf(taken)) taken = i;
  }
  return taken;
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
