import 'package:flutter/material.dart';

import '../../app.dart';
import '../../data/sets.dart';
import '../../theme/nocturne.dart';

/// What a word on screen IS.
///
/// None of this used to exist as a value. Whether a word bears a root,
/// whether its recitation is on the phone, whether it is the one sounding,
/// whether its root is the one open below — every answer was worked out
/// inside the tile's own build, one of them an `existsSync` per word per
/// frame, and they reached the drawing as a ternary ladder. So the tile could
/// not say which gesture was the primary one, and being the word the reader
/// is looking at was a colour branch rather than a state.
///
/// A word says what it is once, here, and the tile only draws it.
/// The key a word tile carries, and the reason it is a type of its own.
///
/// Anything that walks the tree looking for words has to be able to say which
/// widgets are words. Having a `ValueKey<int>` was the convention, and it is
/// not a statement anything can enforce: the reading screen's own scroll view is
/// keyed by the aya it starts at, which is also an int, and it joined the set
/// the moment a reader could open a whole sūra. What follows is worse than a
/// wrong count — an aya id was handed to a lookup expecting a word id, and
/// three journeys died on a word that does not exist.
///
/// Two kinds of id that cannot be told apart is the defect. A type tells them
/// apart, and nothing can wander into this one by accident.
@immutable
final class WordKey extends ValueKey<int> {
  const WordKey(super.value);
}

class WordFace {
  const WordFace(this.word, {required this.hearable});

  final StudyWord word;

  /// Its aya's recitation is on the phone, so a press on it will sound.
  /// Decided when the set loads and again when a download lands — never
  /// while drawing.
  final bool hearable;

  /// It carries a root, so there is something under it to open.
  bool get rooted => word.root != null;

  /// What this word is doing with the recitation this instant.
  WordVoice voice({int? sounding, int? unheard}) {
    if (word.id == sounding) return WordVoice.sounding;
    if (word.id == unheard) return WordVoice.unheard;
    return hearable ? WordVoice.hearable : WordVoice.mute;
  }
}

/// A word's voice: what it is doing with the recitation.
///
/// It is one axis and bearing a root is another, because the two are true at
/// once: the word whose root the reader opened is exactly the word they may
/// then want to hear. Each gets its own paint — the voice takes the fill and
/// the transliteration, the root takes the line under the Arabic — so that
/// neither can go dark because the other is.
enum WordVoice {
  /// Its aya was never downloaded. The row leaves it plain rather than
  /// promising a sound the phone cannot make.
  mute,

  /// On the phone, and it will answer a press.
  hearable,

  /// Sounding now.
  sounding,

  /// Pressed, and nothing came. The transliteration stands in for the
  /// recitation that is not there — one word at a time, and never a shout.
  unheard,
}

/// One aya as the row draws it: its words' faces, and the aya itself for the
/// mark that closes it.
typedef AyaFace = ({StudyAya aya, List<WordFace> words});

/// One aya as the row draws it.
///
/// Per aya rather than per set: a sūra's words arrive a chunk at a time, so
/// there is no moment at which every face in the passage is known.
AyaFace faceOf(StudyAya aya, List<StudyWord> words, Set<int> hearable) => (
  aya: aya,
  words: [
    for (final word in words)
      WordFace(word, hearable: hearable.contains(word.id)),
  ],
);

/// One word of the set.
///
/// A tap asks what the word MEANS; a press asks what it SOUNDS like. The
/// reader tried it the other way round, used it, and reversed it: the root is
/// the far more frequent intent, and the frequent intent belongs on the
/// cheaper gesture. Both calls are recorded in docs/walkthrough.md finding 13
/// so that neither is quietly undone.
///
/// A word carrying no root is not a dead tile. Its tap falls through to its
/// sound, because a tap means "tell me about this word" and a word with no
/// root has one answer left to give.
class WordTile extends StatelessWidget {
  const WordTile({
    super.key,
    required this.face,
    required this.voice,
    required this.open,
    required this.prefs,
    required this.onOpen,
    required this.onHear,
  });

  final WordFace face;
  final WordVoice voice;

  /// Its root is the one in the panel below. Said on the same line that says
  /// the word has a root at all, at full accent against the quiet grey the
  /// other rooted words wear: one lit rule on a page of dim ones, which is
  /// legible at arm's length without anything being drawn near the glyph.
  final bool open;

  final Prefs prefs;
  final void Function(StudyWord word) onOpen;
  final void Function(StudyWord word) onHear;

  @override
  Widget build(BuildContext context) {
    final n = Nocturne.of(context);
    final word = face.word;
    final arabic = TextStyle(
      fontFamily: Nocturne.arabicFamily,
      fontSize: prefs.arabicSize,
      height: 1.75,
      color: n.text,
    );
    // What the word is drawn against. The halo below carves the rule, so it
    // has to be the colour behind the rule rather than a grey guess.
    // ponytail: the page under the aya is flat. Put a gradient there and the
    // halo shows as a smudge, and the rule wants a painter that erases with
    // a blend mode instead of a second copy of the word.
    final behind = voice == WordVoice.sounding
        ? Color.alphaBlend(n.accent.withValues(alpha: 0.16), n.bg)
        : n.bg;
    return GestureDetector(
      onTap: () => face.rooted ? onOpen(word) : onHear(word),
      onLongPress: () => onHear(word),
      child: Container(
        padding: EdgeInsets.all(n.space('1')),
        // The fill is the recitation's, and nothing else is drawn around the
        // word. A frame and a glow were tried here and both reached the
        // Arabic: the blur paints through a transparent box, so the tile read
        // as a solid accent block that spilled onto its neighbour, and the
        // frame ran across the leading hamza of aqra'. A box sized to the
        // text's metrics will always cut the marks that sit above and below
        // the line, so the word's states are said under the word instead.
        decoration: BoxDecoration(
          color: voice == WordVoice.sounding
              ? n.accent.withValues(alpha: 0.16)
              : null,
          borderRadius: BorderRadius.circular(n.radius('sm')),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // The line belongs to the Arabic rather than to the tile: on the
            // tile it sits under the gloss, and a two-line gloss drops it out
            // of the row.
            Container(
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: _line(n), width: 2)),
              ),
              // Arabic hangs below its baseline by a variable amount: 0.27 em
              // in the shallowest word of the corpus and 1.22 em in the
              // deepest, against the 0.60 em this line box gives. So one in
              // thirteen words was drawn through, and no lower line fixes it —
              // a rule that clears the deepest mark sits half a finger under
              // the ordinary word and reads as a divider, not a mark. The word
              // gives way instead: a copy of it stroked in the colour behind
              // carves the rule where the glyphs cross, which is the skip-ink
              // a browser does for a descender.
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _Halo(word.text, arabic, behind),
                    ),
                  ),
                  Text(
                    word.text,
                    textDirection: TextDirection.rtl,
                    style: arabic,
                  ),
                ],
              ),
            ),
            if ((prefs.showTranslit || voice == WordVoice.unheard) &&
                word.translit != null)
              Text(
                word.translit!,
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 9.5,
                  letterSpacing: 0.02 * 9.5,
                  color: n.color('accent-400'),
                ),
              ),
            if (prefs.showGloss && word.gloss != null)
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 88),
                child: Text(
                  word.gloss!,
                  textDirection: TextDirection.ltr,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.25,
                    // The open word's gloss is lit with its line. One 2px
                    // rule changing colour is not enough to find at arm's
                    // length on a page of rules, and the gloss is what the
                    // panel below is expanding, so it lights with it. It sits
                    // under the Arabic, where nothing it does can reach a
                    // harakat.
                    color: open ? n.color('accent-300') : n.textAt(0.66),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// The line under the Arabic answers to the word, not to the audio.
  ///
  /// It says there is a root under this word and the accent says it is the
  /// one open — the two things a tap acts on. Round D handed the line to
  /// `WordVoice` instead, which meant a phone with nothing downloaded showed
  /// every word mute and every line transparent: a page of plain Arabic with
  /// no sign that any of it could be opened, on the first run, which is the
  /// run that has to teach the gesture.
  ///
  /// Whether a word can be heard is not drawn. It is a fact about the aya's
  /// file rather than about the word, so it is the same for every word on a
  /// line and tells the reader nothing a per-word mark could act on; the
  /// transport says it once for the set. Sounding is per word and keeps the
  /// fill; unheard is per word and puts up the transliteration.
  Color _line(Nocturne n) {
    if (open) return n.accent;
    return face.rooted ? n.textAt(0.20) : Colors.transparent;
  }
}

/// The word stroked in the colour behind it, painted under the word itself so
/// that the glyphs carve the rule they hang over.
///
/// It is a painter rather than a second [Text] on purpose: a second Text is a
/// second node in the tree, which a screen reader reads out twice and every
/// finder trips over.
class _Halo extends CustomPainter {
  const _Halo(this.text, this.style, this.colour);

  final String text;
  final TextStyle style;
  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    final stroked = style.copyWith(
      color: null,
      foreground: Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeJoin = StrokeJoin.round
        ..color = colour,
    );
    final painter = TextPainter(
      text: TextSpan(text: text, style: stroked),
      textDirection: TextDirection.rtl,
    )..layout(maxWidth: size.width);
    painter.paint(canvas, Offset.zero);
  }

  @override
  bool shouldRepaint(_Halo old) =>
      old.text != text || old.style != style || old.colour != colour;
}

/// The mark that closes an aya. It is lit on an aya the set was pulled
/// across: that aya is recited with the rest, and its mark says it is already
/// counted.
///
/// The row aligns tops, so the mark is let down onto the Arabic's baseline by
/// hand — a line box of 1.75 puts the baseline about 1.175 em below its top,
/// and the tile's own padding sits above that. Centred on the line box
/// instead it floats above the words, which is not where the design draws it.
///
/// The drop follows the tile: when the tile carried a 1.5px frame the mark
/// was let down by that much again, and it has to come back up now that
/// nothing is drawn around the word.
class AyaMark extends StatelessWidget {
  const AyaMark({super.key, required this.aya, required this.arabicSize});

  final StudyAya aya;
  final double arabicSize;

  @override
  Widget build(BuildContext context) {
    final n = Nocturne.of(context);
    return Container(
      width: 26,
      height: 26,
      margin: EdgeInsets.only(top: n.space('1') + arabicSize * 1.175 - 13),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: aya.understood
            ? n.accent.withValues(alpha: 0.16)
            : Colors.transparent,
        border: Border.all(
          color: n.color(aya.understood ? 'accent-300' : 'accent-700'),
        ),
      ),
      child: Text(
        arabicDigits(aya.number),
        textDirection: TextDirection.rtl,
        style: TextStyle(
          fontFamily: Nocturne.arabicFamily,
          fontSize: 12,
          color: n.color('accent-300'),
        ),
      ),
    );
  }
}

String arabicDigits(int number) => number
    .toString()
    .split('')
    .map((d) => String.fromCharCode(0x0660 + int.parse(d)))
    .join();
