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
  PrayerCursor(int words, {int at = 0})
    : words = words < 1 ? 1 : words,
      _at = at.clamp(0, (words < 1 ? 1 : words) - 1);

  /// How many words the set has.
  final int words;

  int _at;
  var _sure = true;

  /// The word being recited, 0 to [words] - 1.
  int get at => _at;

  /// Whether the word — rather than the aya it sits in — is worth pointing at.
  ///
  /// The aya is always right enough to light: the screen shows one at a time
  /// and a word either side of the truth is invisible at a metre. The word
  /// inside it is only worth singling out when the recitation named one place
  /// clearly, and saying so faintly is honest where saying so brightly would
  /// be a claim the matcher did not make. A tap is always sure: the reader
  /// knows where they are.
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
