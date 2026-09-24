import 'package:flutter/foundation.dart';

/// Where the reciter is in the set, counted in words straight through every
/// repetition of it: the second reading of the first word is a later position
/// than the first reading of it, never the same position arriving again. That
/// is what lets the rule below be literal rather than nearly true.
///
/// Advance or freeze. Never rewind: a rewind mid-prayer reads as the app
/// losing the reciter. Never throw: nothing on this screen may fail in front
/// of someone praying.
class PrayerCursor extends ChangeNotifier {
  PrayerCursor(int words, {int position = 0})
    : words = words < 1 ? 1 : words,
      _position = position < 0 ? 0 : position;

  /// How many words one reading of the set has.
  final int words;

  int _position;
  int get position => _position;

  /// Which word of the set is being recited, and which time through it.
  int get word => _position % words;
  int get reading => _position ~/ words + 1;

  /// Whatever drives the prayer says where it believes the reciter now is: a
  /// tap today, a voice in phase 11. Anything that is not further on than
  /// where the screen already stands leaves the screen exactly as it is.
  /// A report further ahead than one whole reading is the driver being wrong
  /// about the reciter rather than someone who recited a thousand words in a
  /// second, so the cursor takes a reading's worth and lets the next report
  /// carry it the rest of the way. That ceiling is also what keeps the
  /// position out of the arithmetic that would otherwise wrap the reading
  /// count negative.
  void follow(int position) {
    if (position <= _position) return;
    final ceiling = _position + words;
    _position = position < ceiling ? position : ceiling;
    notifyListeners();
  }

  void next() => follow(_position + 1);

  /// Back to somewhere the reader has already been. This is the reader's own
  /// hand rather than a driver's opinion about where the voice went, which is
  /// why it is the one way the prayer moves backwards at all. It still never
  /// moves the prayer on — that is [follow]'s to give — and never off the
  /// start of the first reading.
  void rewind(int position) {
    if (position >= _position) return;
    _position = position < 0 ? 0 : position;
    notifyListeners();
  }

  void back() => rewind(_position - 1);
}
