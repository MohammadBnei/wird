import 'dart:math';

import 'package:flutter/material.dart';

import '../../data/root_repo.dart';
import '../../theme/nocturne.dart';

/// A root at the centre and its lemmas on one ring around it, the one the
/// word on screen is lit.
///
/// The design draws a second, outer ring of related roots. Wird has no record
/// of which roots are related, so that ring is not drawn rather than drawn
/// with nothing on it.
///
/// ponytail: the [_most] commonest lemmas. علم has some thirty, and a ring of
/// thirty labels is a smudge; the counts tile still says how many the word's
/// own lemma has. Spread them over a second ring if the cap ever hides one a
/// reader goes looking for.
class LemmaRing extends StatelessWidget {
  const LemmaRing({
    super.key,
    required this.root,
    required this.lemmas,
    required this.current,
  });

  /// The radicals spaced apart, as the sheet prints them.
  final String root;
  final List<Lemma> lemmas;

  /// The lemma key of the word on screen.
  final String? current;

  static const _most = 8;
  static const _height = 230.0;
  static const _radius = 74.0;

  @override
  Widget build(BuildContext context) {
    final n = Nocturne.of(context);
    final shown = lemmas.take(_most).toList();
    return LayoutBuilder(
      builder: (context, box) {
        final centre = Offset(box.maxWidth / 2, _height / 2);
        final at = [
          for (var k = 0; k < shown.length; k++)
            centre +
                Offset.fromDirection(
                  -pi / 2 + k * 2 * pi / shown.length,
                  _radius,
                ),
        ];
        return SizedBox(
          height: _height,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _Spokes(
                    centre,
                    at,
                    n.accent.withValues(alpha: 0.45),
                  ),
                ),
              ),
              for (var k = 0; k < shown.length; k++)
                _node(n, at[k], shown[k], shown[k].key == current),
              Positioned(
                left: centre.dx - 34,
                top: centre.dy - 34,
                child: Container(
                  width: 68,
                  height: 68,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: n.color('accent-900'),
                    border: Border.all(color: n.accent),
                    boxShadow: [
                      BoxShadow(
                        color: n.accent.withValues(alpha: 0.3),
                        blurRadius: 30,
                      ),
                    ],
                  ),
                  child: Text(
                    root,
                    textDirection: TextDirection.rtl,
                    style: TextStyle(
                      fontFamily: Nocturne.arabicFamily,
                      fontSize: 18,
                      letterSpacing: 1.8,
                      color: n.text,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _node(Nocturne n, Offset at, Lemma lemma, bool on) => Positioned(
    left: at.dx - 50,
    top: at.dy - 7,
    width: 100,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: on ? 9 : 6,
          height: on ? 9 : 6,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: on ? n.color('accent-200') : n.accent,
            boxShadow: on
                ? [BoxShadow(color: n.accent, blurRadius: 10)]
                : const [],
          ),
        ),
        Text(
          lemma.text,
          textDirection: TextDirection.rtl,
          style: TextStyle(
            fontFamily: Nocturne.arabicFamily,
            fontSize: 16,
            height: 1.4,
            color: on ? n.color('accent-100') : n.text,
          ),
        ),
        Text(
          '${lemma.occurrences}×',
          style: TextStyle(fontSize: 9, color: n.textAt(0.55)),
        ),
      ],
    ),
  );
}

class _Spokes extends CustomPainter {
  const _Spokes(this.centre, this.ends, this.colour);

  final Offset centre;
  final List<Offset> ends;
  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = colour
      ..strokeWidth = 1;
    for (final end in ends) {
      // Stopped short of the dot, as the design does.
      final towards = end - centre;
      canvas.drawLine(
        centre,
        centre + towards * ((towards.distance - 6) / towards.distance),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_Spokes old) =>
      old.centre != centre || old.ends != ends || old.colour != colour;
}
