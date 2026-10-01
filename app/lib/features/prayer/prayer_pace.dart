import 'dart:async';

import 'prayer_cursor.dart';

/// How long the voice may go without naming a place before the pace takes
/// the text on. Long enough for a breath between two ayas and the pause a
/// reciter takes to swallow; short enough that someone who has lost the
/// recogniser is not left staring at a word they finished long ago.
const lostAfter = Duration(seconds: 3);

/// The pace, and the voice it stands in for.
///
/// The two can both be on, but they never run together: the voice leads, and
/// the pace only moves the text while the voice has said nothing sure for
/// [lostAfter]. The first sure word heard after that puts the text where the
/// reciter is and stops the pace again. Neither on, the text waits for a tap.
///
/// The pace moves the cursor as surely as the voice does, because the word it
/// stands on is lit either way. What tells them apart is that only
/// [recognised] — the voice — resets the clock, so the pace's own steps never
/// count as the reciter having been found.
class PrayerPace {
  PrayerPace(
    this._cursor, {
    required this.voice,
    required this.pace,
    required int wpm,
    required this.onEnd,
  }) : _step = Duration(microseconds: 60000000 ~/ wpm);

  final PrayerCursor _cursor;
  final bool voice;
  final bool pace;
  final Duration _step;

  /// The pace has stepped past the last word: the rakʿah is over.
  final void Function() onEnd;

  Timer? _timer;
  var _paused = true;

  /// Whether the pace is moving the text now, rather than waiting on the voice.
  bool get pacing => _pacing;
  var _pacing = false;

  /// Starts this rakʿah's clock: the pace at once when there is no voice to
  /// wait for, and otherwise after the voice has had [lostAfter] to begin.
  void start() {
    _paused = false;
    _arm();
  }

  /// The voice named a place surely, the same word again included: a reciter
  /// holding a long vowel is found, not lost.
  void recognised() {
    if (_paused) return;
    _pacing = false;
    _arm();
  }

  /// The reader moved the text by hand. The pace goes on from there, after a
  /// full step, so the word they chose stands long enough to be seen.
  void restartFrom() {
    if (_paused) return;
    _arm();
  }

  /// The app went to the background, or the rakʿah ended. Nothing moves until
  /// [start] again.
  void pause() {
    _paused = true;
    _pacing = false;
    _timer?.cancel();
    _timer = null;
  }

  void dispose() => pause();

  void _arm() {
    _timer?.cancel();
    _timer = null;
    if (!pace) return;
    if (voice && !_pacing) {
      _timer = Timer(lostAfter, () {
        _pacing = true;
        _arm();
      });
      return;
    }
    _pacing = true;
    _timer = Timer(_step, _stepOn);
  }

  void _stepOn() {
    if (_paused) return;
    if (_cursor.at + 1 >= _cursor.words) {
      pause();
      onEnd();
      return;
    }
    _cursor.moveTo(_cursor.at + 1);
    _timer = Timer(_step, _stepOn);
  }
}
