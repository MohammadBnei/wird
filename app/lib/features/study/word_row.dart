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
class WordFace {
  const WordFace(this.word, {required this.hearable});

  final StudyWord word;

  /// Its aya's recitation is on the phone, so a press on it will sound.
  /// Decided when the set loads and again when a download lands — never
  /// while drawing.
  final bool hearable;

  /// It carries a root, so there is something under it to open.
  bool get rooted => word.root != null;

  /// What the line under this word says this instant.
  WordVoice voice({int? sounding, int? unheard}) {
    if (word.id == sounding) return WordVoice.sounding;
    if (word.id == unheard) return WordVoice.unheard;
    return hearable ? WordVoice.hearable : WordVoice.mute;
  }
}

/// A word's voice, which is drawn as the line under its Arabic.
///
/// It is one axis and being the open word is another, because the two are
/// true at once: the word whose root the reader opened is exactly the word
/// they may then want to hear.
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

/// The set as the row draws it.
List<AyaFace> facesOf(StudySet set, Set<int> hearable) => [
  for (final aya in set.ayas)
    (
      aya: aya,
      words: [
        for (final word in aya.words)
          WordFace(word, hearable: hearable.contains(word.id)),
      ],
    ),
];

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

  /// Its root is the one in the panel below. Drawn as a lit frame around the
  /// word: on a bright phone held at arm's length a step along the accent
  /// ramp is no signal at all, and the reader could not tell which word the
  /// panel belonged to.
  final bool open;

  final Prefs prefs;
  final void Function(StudyWord word) onOpen;
  final void Function(StudyWord word) onHear;

  @override
  Widget build(BuildContext context) {
    final n = Nocturne.of(context);
    final word = face.word;
    return GestureDetector(
      onTap: () => face.rooted ? onOpen(word) : onHear(word),
      onLongPress: () => onHear(word),
      child: Container(
        padding: EdgeInsets.all(n.space('1')),
        decoration: BoxDecoration(
          color: voice == WordVoice.sounding
              ? n.accent.withValues(alpha: 0.16)
              : null,
          borderRadius: BorderRadius.circular(n.radius('sm')),
          // The frame is drawn around every word and lit on one, so opening a
          // root moves no other word on the line.
          border: Border.all(
            color: open ? n.accent : Colors.transparent,
            width: 1.5,
          ),
          // A line and a glow, which is how this system carries the accent.
          boxShadow: open
              ? [
                  BoxShadow(
                    color: n.accent.withValues(alpha: 0.45),
                    blurRadius: 12,
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // The line belongs to the Arabic rather than to the tile: on the
            // tile it sits under the gloss, and a two-line gloss drops it out
            // of the row.
            Container(
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: _line(n), width: 2),
                ),
              ),
              child: Text(
                word.text,
                textDirection: TextDirection.rtl,
                style: TextStyle(
                  fontFamily: Nocturne.arabicFamily,
                  fontSize: prefs.arabicSize,
                  height: 1.75,
                  color: n.text,
                ),
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
                    color: n.textAt(0.66),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Color _line(Nocturne n) => switch (voice) {
    WordVoice.sounding => n.accent,
    WordVoice.hearable => n.color('accent-700'),
    WordVoice.mute || WordVoice.unheard => Colors.transparent,
  };
}

/// The mark that closes an aya. It is lit on an aya the set was pulled
/// across: that aya is recited with the rest, and its mark says it is already
/// counted.
///
/// The row aligns tops, so the mark is let down onto the Arabic's baseline by
/// hand — a line box of 1.75 puts the baseline about 1.175 em below its top,
/// and the tile's own padding sits above that. Centred on the line box
/// instead it floats above the words, which is not where the design draws it.
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
      margin: EdgeInsets.only(
        top: n.space('1') + 1.5 + arabicSize * 1.175 - 13,
      ),
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
