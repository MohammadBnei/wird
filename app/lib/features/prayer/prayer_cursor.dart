import 'package:flutter/foundation.dart';

/// Which word of the set the reciter is on.
///
/// It moves in either direction, because a reciter does. Repeating an aya, or
/// a phrase, or starting the set again for the next rakʿa is ordinary prayer,
/// and the rule this class used to carry — *advance or freeze, never rewind* —
/// made the app structurally unable to follow any of it.
///
/// That rule was written to protect a reader from a screen that jumps. It was
/// resting on a fallback that does not exist: during ṣalāh the phone lies on
/// the floor and the reader cannot touch it until the prayer ends. A screen
/// that refuses to move is not being careful, it is failed for the rest of the
/// prayer, and nobody can correct it. What replaced the rule is upstream, in
/// `alignment.dart`: nothing moves the prayer unless one place in the set fits
/// what was heard better than every other place by a clear margin.
///
/// Never throws: nothing on this screen may fail in front of someone praying.
class PrayerCursor extends ChangeNotifier {
  /// A cursor built anywhere but the first word is a prayer already under
  /// way — something put it there — so the word it names is worth pointing
  /// at. One built at the first word is a prayer nobody has begun.
  PrayerCursor(int words, {int at = 0})
    : words = words < 1 ? 1 : words,
      _at = at.clamp(0, (words < 1 ? 1 : words) - 1),
      _sure = at != 0;

  /// How many words the set has.
  final int words;

  int _at;

  /// Whether the word — rather than the aya it sits in — is worth pointing
  /// at. A prayer opens on the first word without anybody having said it, so
  /// nothing is singled out until something is heard or tapped: the aya
  /// stands as still to come and the word inside it waits to be earned.
  bool _sure;

  /// The word being recited, 0 to [words] - 1.
  int get at => _at;

  /// Whether a word has been named at all — by the voice, the pace or a tap —
  /// rather than the cursor standing where a rakʿah put it before anything
  /// was said. Until then the screen draws the aya as still to come.
  ///
  /// The voice used to name a word only above its sure score and leave the
  /// rest unsure; a reader whose voice placed at 0.7 then saw their aya never
  /// light. Every place the matcher moves to now names its word.
  bool get sure => _sure;

  /// Which aya of the set that word belongs to is the screen's business, not
  /// this class's: it holds a place in the recitation, not a layout.
  ///
  /// Silent when nothing changes. A voice answers several times a second and
  /// mostly answers the same place twice, and rebuilding the prayer on every
  /// one of those would flicker a screen somebody is praying in front of.
  void moveTo(int word, {bool sure = true}) {
    final next = word.clamp(0, words - 1);
    if (next == _at && sure == _sure) return;
    _at = next;
    _sure = sure;
    notifyListeners();
  }
}
