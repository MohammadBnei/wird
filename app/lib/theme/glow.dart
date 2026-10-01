import 'package:flutter/painting.dart';

import 'nocturne.dart';

/// The two ways a word is lit, and the only two.
///
/// [recited] is the word the reader is saying in prayer: near-white, with a
/// wide glow, because during a prayer it is the one thing on the screen.
/// [reading] is the word the reader has open, or a root's word inside an aya:
/// the accent itself, so it never reads as the prayer's word. Its glow is kept
/// tight. A 24px blur in the reader's row of words reached the next word,
/// which is the spill that got the old box glow rejected.
enum Glow { recited, reading }

TextStyle glowing(Nocturne n, Glow glow) => switch (glow) {
  Glow.recited => TextStyle(
    color: n.color('accent-200'),
    shadows: [Shadow(color: n.accent.withValues(alpha: 0.65), blurRadius: 28)],
  ),
  Glow.reading => TextStyle(
    color: n.accent,
    shadows: [Shadow(color: n.accent.withValues(alpha: 0.8), blurRadius: 12)],
  ),
};
