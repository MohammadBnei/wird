import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../data/root_repo.dart';
import '../../theme/nocturne.dart';

/// The design draws the constellation as an SVG on a 620×420 viewBox, and
/// every coordinate below is read off that markup rather than invented.
const constellationBox = Size(620, 420);

const _centre = Offset(310, 210);

/// The four places a kin form is drawn, in the order the design lists them.
const _kinSlots = [
  Offset(118, 104),
  Offset(500, 100),
  Offset(104, 316),
  Offset(512, 312),
];

/// The place kept for the form being recited right now. It is the only node
/// drawn as a ring around a lit core, which is what tells the reader which of
/// the root's forms is the one in front of them.
const _thisAyaSlot = Offset(310, 366);

/// One node of the constellation: a form of the root, where it is drawn, and
/// whether it is the form the reader has open.
typedef Star = ({Derivative derivative, Offset at, bool thisAya});

/// Which of a root's forms reach the five places the design draws, and which
/// one is marked as the aya being read.
///
/// [wordInAya] is how this aya spells the root's form. A root read in an aya
/// that does not contain it gets no marked node at all: a node captioned
/// "THIS AYA" over a form from somewhere else tells the reader the Qur'an
/// says something it does not.
List<Star> constellation(List<Derivative> derivatives, String? wordInAya) {
  final here = _formRead(derivatives, wordInAya);
  final kin = [for (final d in derivatives) if (d != here) d];
  return [
    for (var i = 0; i < _kinSlots.length && i < kin.length; i++)
      (derivative: kin[i], at: _kinSlots[i], thisAya: false),
    if (here != null) (derivative: here, at: _thisAyaSlot, thisAya: true),
  ];
}

/// The derivative this aya spells. The corpus keeps a recitation mark on the
/// word it follows while the derivative is held without it, so the aya's word
/// carries the form rather than always equalling it.
Derivative? _formRead(List<Derivative> derivatives, String? wordInAya) {
  if (wordInAya == null) return null;
  for (final d in derivatives) {
    if (d.text == wordInAya) return d;
  }
  for (final d in derivatives) {
    if (wordInAya.startsWith(d.text)) return d;
  }
  return null;
}

/// The constellation itself. Flutter has no SVG, so the design's own geometry
/// is painted: same viewBox, same coordinates, scaled to fit the pane the way
/// an SVG with the default `preserveAspectRatio` does.
class Constellation extends StatelessWidget {
  const Constellation({
    super.key,
    required this.display,
    required this.stars,
    required this.ayahId,
  });

  /// The radicals spaced apart, drawn in the middle of the ring.
  final String display;
  final List<Star> stars;
  final int ayahId;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.infinite,
    painter: _ConstellationPainter(
      display: display,
      stars: stars,
      ayahId: ayahId,
      n: Nocturne.of(context),
    ),
  );
}

class _ConstellationPainter extends CustomPainter {
  _ConstellationPainter({
    required this.display,
    required this.stars,
    required this.ayahId,
    required this.n,
  });

  final String display;
  final List<Star> stars;
  final int ayahId;
  final Nocturne n;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = (size.width / constellationBox.width).clamp(
      0.0,
      size.height / constellationBox.height,
    );
    canvas.save();
    canvas.translate(
      (size.width - constellationBox.width * scale) / 2,
      (size.height - constellationBox.height * scale) / 2,
    );
    canvas.scale(scale);

    final thread = Paint()
      ..color = n.accent.withValues(alpha: 0.28)
      ..strokeWidth = 1;
    for (final star in stars) {
      canvas.drawLine(_centre, star.at, thread);
    }

    canvas
      ..drawCircle(_centre, 52, Paint()..color = n.color('accent-900'))
      ..drawCircle(
        _centre,
        52,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = n.accent,
      )
      ..drawCircle(
        _centre,
        66,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = n.accent.withValues(alpha: 0.22),
      );
    _text(
      canvas,
      display,
      at: const Offset(310, 218),
      style: TextStyle(
        fontFamily: Nocturne.arabicFamily,
        fontSize: 30,
        letterSpacing: 3,
        color: n.text,
      ),
      rtl: true,
    );

    for (final star in stars) {
      star.thisAya ? _thisAya(canvas, star) : _kin(canvas, star);
    }
    canvas.restore();
  }

  void _kin(Canvas canvas, Star star) {
    canvas.drawCircle(star.at, 6, Paint()..color = n.accent);
    _text(
      canvas,
      star.derivative.text,
      at: star.at.translate(0, -24),
      style: TextStyle(
        fontFamily: Nocturne.arabicFamily,
        fontSize: 25,
        color: n.text,
      ),
      rtl: true,
    );
    _text(
      canvas,
      '${_caption(star.derivative)} · ${ayahRef(star.derivative.ayahId)}',
      at: star.at.translate(0, 22),
      style: TextStyle(
        fontFamily: Nocturne.bodyFamily,
        fontSize: 11,
        color: n.color('neutral-500'),
      ),
    );
  }

  void _thisAya(Canvas canvas, Star star) {
    canvas
      ..drawCircle(
        star.at,
        8,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = n.accent,
      )
      ..drawCircle(star.at, 3.5, Paint()..color = n.color('accent-300'));
    _text(
      canvas,
      star.derivative.text,
      at: star.at.translate(0, -24),
      style: TextStyle(
        fontFamily: Nocturne.arabicFamily,
        fontSize: 26,
        color: n.color('accent-300'),
      ),
      rtl: true,
    );
    _text(
      canvas,
      'THIS AYA · ${ayahRef(ayahId)}',
      at: star.at.translate(0, 26),
      style: TextStyle(
        fontFamily: Nocturne.bodyFamily,
        fontSize: 11,
        letterSpacing: 1,
        color: n.accent,
      ),
    );
  }

  /// Draws one label centred on [at], which is where the SVG puts the text's
  /// baseline rather than its top.
  void _text(
    Canvas canvas,
    String label, {
    required Offset at,
    required TextStyle style,
    bool rtl = false,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: label, style: style),
      textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout();
    final baseline = painter.computeDistanceToActualBaseline(
      TextBaseline.alphabetic,
    );
    painter.paint(canvas, Offset(at.dx - painter.width / 2, at.dy - baseline));
  }

  /// What the design writes under each kin form: what it means, or — where
  /// the corpus glossed no occurrence of it — what shape it is.
  String _caption(Derivative derivative) =>
      derivative.gloss ??
      (derivative.form == null
          ? '${derivative.occurrences}×'
          : 'form ${derivative.form}');

  @override
  bool shouldRepaint(_ConstellationPainter old) =>
      old.display != display ||
      old.ayahId != ayahId ||
      !listEquals(old.stars, stars);
}
