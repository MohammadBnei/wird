import 'dart:math';

import 'package:flutter/material.dart';

import '../../data/root_repo.dart';
import '../../theme/nocturne.dart';
import '../../widgets/nocturne_button.dart';

const dialBoxWidth = 360.0;
const dialBoxHeight = 344.0;
const dialRadius = 121.0;
const _labelMaxWidth = 144.0;
const _labelHalfHeight = 18.0;
const _centreDiameter = 132.0;
const _dialTurn = Duration(milliseconds: 500);
const _dialCurve = Cubic(0.22, 0.7, 0.2, 1);

/// Where derivative [i]'s label sits, measured from the centre of the ring,
/// when the dial stands at [position] — which is a whole number while the ring
/// is at rest and a fraction of a step while it turns.
///
/// The ring carries the labels round; the labels themselves never turn, which
/// is the counter-rotation the design writes as a second transform inside the
/// first. Turning the ring by one whole step leaves derivative i+1 exactly
/// where derivative i was.
Offset satelliteOffset(int i, double position, int count) {
  final angle = (i - position) * 2 * pi / count;
  return Offset(dialRadius * sin(angle), -dialRadius * cos(angle));
}

/// The position the ring should travel to in order to show derivative
/// [target], starting from where it stands now.
///
/// It is the same derivative whichever way round the ring goes, so it takes
/// the short way: stepping off the last derivative onto the first is one step
/// forward, not a spin backwards past every other form of the root.
double nearestPosition(double from, int target, int count) {
  final turns = ((from - target) / count).roundToDouble();
  return target + turns * count;
}

/// The ring of derivatives, its centre, and the prev/next row under it.
class RootDial extends StatefulWidget {
  const RootDial({
    super.key,
    required this.reading,
    required this.index,
    required this.onIndex,
  });

  final RootReading reading;
  final int index;
  final ValueChanged<int> onIndex;

  @override
  State<RootDial> createState() => _RootDialState();
}

class _RootDialState extends State<RootDial> {
  late double _position = widget.index.toDouble();

  int get _count => widget.reading.derivatives.length;

  @override
  void didUpdateWidget(RootDial old) {
    super.didUpdateWidget(old);
    if (widget.index != old.index) {
      setState(
        () => _position = nearestPosition(_position, widget.index, _count),
      );
    }
  }

  void _step(int by) =>
      widget.onIndex((widget.index + by + _count) % _count);

  @override
  Widget build(BuildContext context) {
    final n = Nocturne.of(context);
    final reading = widget.reading;
    return Container(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0, -0.2),
          radius: 0.86,
          colors: [
            // The design lifts the background a little under the ring. The
            // lift sits between the two surface tokens rather than beside
            // them, so it is mixed from both instead of written as a hex.
            Color.lerp(n.bg, n.surface, 0.5)!,
            n.bg,
          ],
          stops: const [0, 0.76],
        ),
      ),
      child: Column(
        children: [
          GestureDetector(
            onHorizontalDragEnd: (details) {
              final velocity = details.primaryVelocity ?? 0;
              if (velocity != 0) _step(velocity < 0 ? 1 : -1);
            },
            child: SizedBox(
              width: dialBoxWidth,
              height: dialBoxHeight,
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: _position),
                duration: _dialTurn,
                curve: _dialCurve,
                builder: (context, position, _) =>
                    _ring(n, reading, position),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              spacing: 16,
              children: [
                _round(
                  n,
                  'Previous',
                  Icons.chevron_left,
                  () => _step(-1),
                ),
                Text(
                  '${widget.index + 1} of $_count · swipe the ring',
                  style: TextStyle(
                    fontSize: 10.5,
                    letterSpacing: 0.06 * 10.5,
                    color: n.textAt(0.55),
                  ),
                ),
                _round(n, 'Next', Icons.chevron_right, () => _step(1)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _ring(Nocturne n, RootReading reading, double position) {
    const centre = Offset(dialBoxWidth / 2, dialBoxHeight / 2);
    final labelWidth = min(
      _labelMaxWidth,
      2 * pi * dialRadius / _count * 0.92,
    );
    return Stack(
      children: [
        Positioned(
          left: centre.dx - dialRadius,
          top: centre.dy - dialRadius,
          child: Container(
            width: dialRadius * 2,
            height: dialRadius * 2,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: n.textAt(0.1)),
            ),
          ),
        ),
        for (var i = 0; i < _count; i++)
          _satellite(n, reading.derivatives[i], i, position, labelWidth),
        Positioned(
          left: centre.dx - _centreDiameter / 2,
          top: centre.dy - _centreDiameter / 2,
          child: _centreDisc(n, reading),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: 6,
          child: Center(
            child: CustomPaint(
              size: const Size(16, 10),
              painter: _MarkerPainter(n.accent),
            ),
          ),
        ),
      ],
    );
  }

  Widget _satellite(
    Nocturne n,
    Derivative derivative,
    int i,
    double position,
    double labelWidth,
  ) {
    final at = satelliteOffset(i, position, _count);
    return Positioned(
      left: dialBoxWidth / 2 + at.dx - labelWidth / 2,
      top: dialBoxHeight / 2 + at.dy - _labelHalfHeight,
      width: labelWidth,
      child: GestureDetector(
        onTap: () => widget.onIndex(i),
        behavior: HitTestBehavior.opaque,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            derivative.text,
            textDirection: TextDirection.rtl,
            style: TextStyle(
              fontFamily: Nocturne.arabicFamily,
              fontSize: 22,
              height: 1.6,
              color: n.text,
            ),
          ),
        ),
      ),
    );
  }

  Widget _centreDisc(Nocturne n, RootReading reading) => Container(
    width: _centreDiameter,
    height: _centreDiameter,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: n.color('accent-900'),
      boxShadow: [
        BoxShadow(color: n.accent, spreadRadius: 1),
        BoxShadow(
          color: n.accent.withValues(alpha: 0.28),
          blurRadius: 40,
        ),
      ],
    ),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      spacing: 2,
      children: [
        Text(
          reading.display,
          textDirection: TextDirection.rtl,
          style: TextStyle(
            fontFamily: Nocturne.arabicFamily,
            fontSize: 27,
            letterSpacing: 0.14 * 27,
            color: n.text,
          ),
        ),
        Text(
          '${reading.translit} · ${reading.occurrences}×',
          style: TextStyle(fontSize: 10, color: n.color('accent-300')),
        ),
      ],
    ),
  );

  Widget _round(
    Nocturne n,
    String label,
    IconData icon,
    VoidCallback onPressed,
  ) => DecoratedBox(
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(color: n.divider),
    ),
    child: NocturneButton(
      variant: NocturneButtonVariant.icon,
      onPressed: onPressed,
      child: Semantics(label: label, child: Icon(icon, size: 15)),
    ),
  );
}

class _MarkerPainter extends CustomPainter {
  const _MarkerPainter(this.colour);

  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width / 2, size.height)
      ..lineTo(0, 0)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(path, Paint()..color = colour);
  }

  @override
  bool shouldRepaint(_MarkerPainter old) => old.colour != colour;
}
