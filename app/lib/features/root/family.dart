import 'package:flutter/material.dart';

import '../../data/root_repo.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/nocturne.dart';
import 'root_dial.dart';

/// A root's family: its derivatives, drawn as ways to move rather than as a
/// picture of themselves.
///
/// The app draws a family in two places — the ring and spine of screen 3a,
/// and the same ring and spine on screen 1c. They are arrangements of one
/// thing, so what a member IS ([Derivative]), what
/// it opens ([openAya]) and how a row of one reads ([KinSpine]) are decided
/// here, once, instead of at each drawing.

/// Opens the aya a member of the family names.
///
/// This is the whole of what navigation from a family means, and every
/// drawing calls it: a kin row's reference, the card under the dial. A
/// reference the reader can see is a reference the reader
/// can follow.
///
/// A family is only ever drawn on a screen pushed from the one reading screen,
/// so the aya is answered DOWN to it rather than stacked on top of it. A second
/// 1a takes the application's one recitation over, and the first — which loads
/// once and never again — goes on drawing its own set's words over the new
/// aya's player. See ADR-0003.
void openAya(BuildContext context, int ayahId) =>
    Navigator.of(context).pop(ayahId);

/// An aya reference, printed the way a reference is printed and opening the
/// aya it names.
///
/// It carries its own padding: the reference is 10.5pt type and a tap target
/// the size of the glyphs is not one a thumb can hit.
class AyaRef extends StatelessWidget {
  const AyaRef({super.key, required this.ayahId, this.lit = false});

  final int ayahId;

  /// The row this reference sits on is the one being read.
  final bool lit;

  @override
  Widget build(BuildContext context) {
    final n = Nocturne.of(context);
    return Semantics(
      button: true,
      label: AppLocalizations.of(context)!.root_openAya(ayahRef(ayahId)),
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => openAya(context, ayahId),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 6, 2, 6),
          child: Text(
            ayahRef(ayahId),
            style: TextStyle(
              fontSize: 10.5,
              color: lit ? n.accent : n.textAt(0.6),
            ),
          ),
        ),
      ),
    );
  }
}

/// The derivatives read down the page instead of round the ring: a dotted
/// thread with one node per form, and every reference on it a door.
class KinSpine extends StatelessWidget {
  const KinSpine({
    super.key,
    required this.derivatives,
    this.selected,
    this.onTap,
    this.here,
  });

  final List<Derivative> derivatives;

  /// The form the dial is pointing at. The spine lights the same one, so the
  /// two never disagree about what is being read.
  final int? selected;
  final ValueChanged<int>? onTap;

  /// The form the aya on screen spells, if the family is being read beside
  /// one.
  final Derivative? here;

  @override
  Widget build(BuildContext context) {
    final n = Nocturne.of(context);
    final l = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.only(left: 26),
      child: Stack(
        // The thread and its nodes hang to the left of the rows they belong
        // to, which is off the edge of this stack.
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: -21,
            top: 6,
            bottom: 20,
            width: 1,
            child: CustomPaint(painter: ThreadPainter(n.textAt(0.26))),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < derivatives.length; i++)
                _row(n, l, derivatives[i], i),
            ],
          ),
        ],
      ),
    );
  }

  Widget _row(Nocturne n, AppLocalizations l, Derivative derivative, int i) {
    final lit = i == selected;
    return Padding(
      padding: EdgeInsets.only(bottom: i == derivatives.length - 1 ? 0 : 14),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap == null ? null : () => onTap!(i),
        child: Container(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(n.radius('md')),
            color: lit ? n.accent.withValues(alpha: 0.13) : null,
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: -34,
                top: lit ? 12 : 13,
                child: lit ? _litNode(n) : _node(n),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    spacing: 9,
                    children: [
                      Text(
                        derivative.text,
                        textDirection: TextDirection.rtl,
                        maxLines: 1,
                        style: TextStyle(
                          fontFamily: Nocturne.arabicFamily,
                          fontSize: lit ? 23 : 22,
                          height: 1.4,
                          color: lit ? n.color('accent-200') : n.text,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          derivative.gloss ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: n.textAt(0.78),
                          ),
                        ),
                      ),
                      // The mark and the reference are two different facts:
                      // this is the form the aya on screen reads, and this is
                      // the aya the form is first met in. One row, so the
                      // reference still opens where it says it does.
                      if (here != null && derivative == here)
                        Text(
                          l.root_thisAya,
                          style: TextStyle(
                            fontSize: 9.5,
                            letterSpacing: 0.1 * 9.5,
                            color: n.accent,
                          ),
                        ),
                      AyaRef(ayahId: derivative.ayahId, lit: lit),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      derivative.note == null
                          ? derivativeWeight(l, derivative)
                          : '${derivativeWeight(l, derivative)} · '
                              '${derivative.note}',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.5,
                        color: n.textAt(0.7),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _node(Nocturne n) => Container(
    width: 9,
    height: 9,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: n.color('accent-600'),
    ),
  );

  Widget _litNode(Nocturne n) => Container(
    width: 11,
    height: 11,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: n.bg,
      border: Border.all(color: n.accent, width: 1.5),
      boxShadow: [
        BoxShadow(
          color: n.accent.withValues(alpha: 0.55),
          blurRadius: 10,
        ),
      ],
    ),
  );
}

/// One form's weight, in the fewest words that still say it: which shape it is
/// and how often it is read.
///
/// This used to be a sentence — "Form I. Occurs 11 times in the Qur'an." —
/// under every row of the spine. Thirty of ṣ-b-r's thirty-eight rows wrote the
/// same one, and the two facts that differ were the two words buried inside
/// it. A list where every row reads the same is a list nobody reads.
///
/// [l] rather than a context: the row this is drawn on is built from a
/// [Nocturne] the caller has already read off its own context, and one of the
/// two shapes is a count and a multiplication sign with no words in it at all.
String derivativeWeight(AppLocalizations l, Derivative derivative) =>
    derivative.form == null
    ? '${derivative.occurrences}×'
    : l.root_weightWithForm(derivative.form!, derivative.occurrences);

/// A root's family as the ring with the spine under it, at any width.
///
/// The design also drew it as a star chart of the members around the root.
/// It said nothing the spine does not, reached only screens
/// wide enough to read its captions, and was removed (ADR 0033).
class RootFamily extends StatefulWidget {
  const RootFamily({
    super.key,
    required this.reading,
    required this.ayahId,
    this.wordInAya,
  });

  final RootReading reading;

  /// The aya the family is being read beside.
  final int ayahId;

  /// How that aya spells the root, when it carries it at all.
  final String? wordInAya;

  @override
  State<RootFamily> createState() => _RootFamilyState();
}

class _RootFamilyState extends State<RootFamily> {
  late final Derivative? _here = widget.reading.spelled(widget.wordInAya);

  /// The ring opens on the form the aya in front of the reader spells, which
  /// is the one thing they are certain to be looking for.
  late int _index = _here == null
      ? 0
      : widget.reading.derivatives.indexOf(_here);

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final n = Nocturne.of(context);
      final ring = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!widget.reading.readsAsSpine)
            // The dial is drawn at the width screen 3a gives it, which is
            // wider than a phone column with two pairs of gutters inside it.
            FittedBox(
              fit: BoxFit.scaleDown,
              child: SizedBox(
                width: dialBoxWidth,
                child: RootDial(
                  reading: widget.reading,
                  index: _index,
                  onIndex: (i) => setState(() => _index = i),
                ),
              ),
            ),
          SizedBox(height: n.space('4')),
          KinSpine(
            derivatives: widget.reading.derivatives,
            selected: widget.reading.readsAsSpine ? null : _index,
            onTap: widget.reading.readsAsSpine
                ? null
                : (i) => setState(() => _index = i),
            here: _here,
          ),
        ],
      );
      return constraints.hasBoundedHeight
          ? SingleChildScrollView(child: ring)
          : ring;
    },
  );
}

/// Two pixels of line every seven, the way the design's repeating gradient
/// draws it.
class ThreadPainter extends CustomPainter {
  const ThreadPainter(this.colour, {this.across = false});

  final Color colour;
  final bool across;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = colour
      ..strokeWidth = 1;
    final length = across ? size.width : size.height;
    for (var at = 0.0; at < length; at += 7) {
      final end = (at + 2).clamp(0.0, length);
      canvas.drawLine(
        across ? Offset(at, 0) : Offset(0, at),
        across ? Offset(end, 0) : Offset(0, end),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(ThreadPainter old) =>
      old.colour != colour || old.across != across;
}
