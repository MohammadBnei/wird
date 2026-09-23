import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import '../../nav.dart';
import '../../theme/nocturne.dart';
import '../../widgets/nocturne_button.dart';
import '../../widgets/nocturne_rule.dart';
import '../../widgets/nocturne_tag.dart';
import 'passage.dart';

/// The design's own page gutter on this screen; it is not a step of the
/// space scale.
const _gutter = 20.0;

/// Screen 1d — how much of the Qur'an has been understood, not merely read.
class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key, required this.db});

  final Database db;

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  Passage? _passage;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final passage = await readPassage(widget.db);
    if (mounted) setState(() => _passage = passage);
  }

  /// "All 114" means all 114 sūras, which is the index and not the kept list.
  /// The aya the reader picks there is passed down to screen 1a, the one screen
  /// that reads an aya, rather than opened on top of this one.
  Future<void> _openIndex() async {
    final chosen = await Navigator.of(context).pushNamed(Routes.index);
    if (mounted && chosen != null) Navigator.of(context).pop(chosen);
  }

  @override
  Widget build(BuildContext context) {
    final n = Nocturne.of(context);
    final passage = _passage;
    return Scaffold(
      backgroundColor: n.bg,
      body: SafeArea(
        child: passage == null
            ? const SizedBox.shrink()
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _header(n),
                    SizedBox(height: n.space('2')),
                    _ring(n, passage),
                    _tiles(n, passage),
                    _whereYouAre(n, passage),
                    SizedBox(height: n.space('6')),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _header(Nocturne n) => Padding(
    padding: const EdgeInsets.fromLTRB(_gutter, 8, _gutter, 0),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: n.space('3'),
      children: [
        // The design draws no way back off this screen. A pushed screen needs
        // one on the platforms with no back gesture, so it is the same 32px
        // icon button the root screen is drawn with.
        NocturneButton(
          variant: NocturneButtonVariant.icon,
          onPressed: () => Navigator.of(context).maybePop(),
          child: const Icon(Icons.arrow_back_ios_new, size: 16),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Understood, not merely read'.toUpperCase(),
                style: TextStyle(
                  fontSize: 10,
                  height: 1.2,
                  letterSpacing: 0.11 * 10,
                  color: n.accent,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                'Your passage',
                style: Theme.of(context).textTheme.displaySmall,
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _ring(Nocturne n, Passage passage) {
    final ayas =
        '${_grouped(passage.understood)} of ${_grouped(ayasInTheQuran)} ayas';
    return Semantics(
      label:
          '${_percent(passage)} of the Qur\'an understood, $ayas. '
          'Juz ${passage.currentJuz}, set ${passage.currentSet}.',
      child: SizedBox(
        height: 250,
        child: Center(
          child: SizedBox(
            width: 360,
            height: 250,
            child: CustomPaint(
              painter: _JuzRing(
                juz: passage.juz,
                percent: _percent(passage),
                ayas: ayas,
                here: 'JUZ ${passage.currentJuz} · SET ${passage.currentSet}',
                text: n.text,
                accent: n.accent,
                spent: n.color('neutral-800'),
                caption: n.color('neutral-500'),
                edge: n.color('neutral-600'),
                inner: n.color('neutral-900'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _tiles(Nocturne n, Passage passage) {
    final ratio = passage.prayersPerSet;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: _gutter),
      child: Row(
        spacing: 9,
        children: [
          _tile(n, _grouped(passage.setsUnderstood), 'sets understood'),
          _tile(n, _grouped(passage.prayers), 'prayers on them'),
          // An em dash, never a division by zero: a reader who has understood
          // no sets has not prayed any per set either.
          _tile(
            n,
            ratio == null ? '—' : ratio.toStringAsFixed(1),
            'prayers per set',
          ),
        ],
      ),
    );
  }

  Widget _tile(Nocturne n, String value, String label) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: n.surface,
        borderRadius: BorderRadius.circular(n.radius('md')),
        boxShadow: n.shadow('sm'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 1,
        children: [
          Text(
            value,
            style: TextStyle(
              fontFamily: Nocturne.headingFamily,
              fontVariations: Nocturne.headingVariations,
              fontSize: 22,
              height: 1.12,
              letterSpacing: -0.015 * 22,
              color: n.text,
            ),
          ),
          Text(
            label,
            style: TextStyle(fontSize: 10, height: 1.2, color: n.textAt(0.5)),
          ),
        ],
      ),
    ),
  );

  Widget _whereYouAre(Nocturne n, Passage passage) => Padding(
    padding: const EdgeInsets.fromLTRB(_gutter, _gutter, _gutter, 0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Where you are'.toUpperCase(),
              style: TextStyle(
                fontFamily: Nocturne.headingFamily,
                fontVariations: Nocturne.headingVariations,
                fontSize: 13,
                height: 1.12,
                letterSpacing: 0.08 * 13,
                color: n.textAt(0.6),
              ),
            ),
            NocturneButton(
              variant: NocturneButtonVariant.ghost,
              onPressed: _openIndex,
              child: const Text('All 114', style: TextStyle(fontSize: 11)),
            ),
          ],
        ),
        const NocturneRule(fade: 30),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 11,
          children: [for (final sura in passage.suras) _suraRow(n, sura)],
        ),
        SizedBox(height: n.space('6')),
        _rootsKnown(n, passage),
      ],
    ),
  );

  Widget _suraRow(Nocturne n, SuraPassage sura) => Row(
    spacing: 11,
    children: [
      SizedBox(
        width: 74,
        child: Text(
          sura.nameAr,
          textAlign: TextAlign.right,
          textDirection: TextDirection.rtl,
          style: TextStyle(
            fontFamily: Nocturne.arabicFamily,
            fontSize: 19,
            color: sura.current ? n.text : n.textAt(0.6),
          ),
        ),
      ),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DefaultTextStyle.merge(
              style: TextStyle(
                fontSize: 11,
                color: sura.current ? n.text : n.textAt(0.75),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('${sura.id} · ${sura.nameEn}'),
                  Text(
                    '${sura.understood} / ${sura.ayahCount}',
                    style: sura.current ? TextStyle(color: n.accent) : null,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            _bar(n, sura),
          ],
        ),
      ),
    ],
  );

  Widget _bar(Nocturne n, SuraPassage sura) => ClipRRect(
    borderRadius: BorderRadius.circular(2),
    child: Container(
      height: 3,
      color: n.color('neutral-800'),
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: sura.fraction,
        child: Container(
          decoration: BoxDecoration(
            color: sura.current ? n.accent : n.color('accent-700'),
            boxShadow: sura.current
                ? [
                    BoxShadow(
                      color: n.accent.withValues(alpha: 0.7),
                      blurRadius: 8,
                    ),
                  ]
                : null,
          ),
        ),
      ),
    ),
  );

  Widget _rootsKnown(Nocturne n, Passage passage) {
    final rest = passage.rootsKnownCount - passage.rootsKnown.length;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: n.surface,
        borderRadius: BorderRadius.circular(n.radius('md')),
        boxShadow: n.shadow('sm'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Roots you now know'.toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              height: 1.2,
              letterSpacing: 0.1 * 10,
              color: n.accent,
            ),
          ),
          if (passage.rootsKnown.isNotEmpty) ...[
            const SizedBox(height: 7),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final root in passage.rootsKnown) _rootTag(n, root),
                if (rest > 0) NocturneTag('+ $rest'),
              ],
            ),
          ],
          const SizedBox(height: 5),
          Text(
            passage.rootsKnownCount == 0
                ? 'The roots of every set you understand are collected here.'
                : '${_grouped(passage.rootsKnownCount)} roots cover '
                      '${passage.coverageAhead}% of the words ahead of you.',
            style: TextStyle(fontSize: 11, height: 1.4, color: n.textAt(0.5)),
          ),
        ],
      ),
    );
  }

  /// The design sets the Arabic tags on this card at 14px with the lexicon's
  /// letter spacing, which the shared tag does not carry.
  Widget _rootTag(Nocturne n, String letters) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
    decoration: BoxDecoration(
      color: n.color('accent-800'),
      borderRadius: BorderRadius.circular(n.radius('md') * 0.75),
    ),
    child: Text(
      letters,
      textDirection: TextDirection.rtl,
      style: TextStyle(
        fontFamily: Nocturne.arabicFamily,
        fontSize: 14,
        height: 1.2,
        letterSpacing: 0.1 * 14,
        color: n.color('accent-100'),
      ),
    ),
  );

  String _percent(Passage passage) =>
      '${(passage.fraction * 100).toStringAsFixed(1)}%';
}

/// Thousands separated the way the design prints them: 1,148.
String _grouped(int n) {
  final digits = n.toString();
  final out = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return out.toString();
}

/// The ring: thirty arcs, one per juz, lit by how much of each the reader has
/// understood.
class _JuzRing extends CustomPainter {
  const _JuzRing({
    required this.juz,
    required this.percent,
    required this.ayas,
    required this.here,
    required this.text,
    required this.accent,
    required this.spent,
    required this.caption,
    required this.edge,
    required this.inner,
  });

  final List<double> juz;
  final String percent;
  final String ayas;
  final String here;
  final Color text;
  final Color accent;
  final Color spent;
  final Color caption;
  final Color edge;
  final Color inner;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width / 2, 138);
    canvas.drawCircle(
      centre,
      104,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = spent.withValues(alpha: 0.5),
    );
    canvas.drawCircle(
      centre,
      86,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = inner,
    );

    // A twelfth of the circle per pair of juz, and the gap has to be wider
    // than the stroke or the round caps close it and the ring reads as one
    // unbroken line.
    const pitch = 2 * math.pi / 30;
    const gap = pitch * 0.46;
    final box = Rect.fromCircle(center: centre, radius: 95);
    for (var i = 0; i < juz.length; i++) {
      final done = juz[i];
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..strokeCap = StrokeCap.round
        // A juz never opened stays the colour of the ring itself; one only
        // partly understood is the accent held back to how far it got.
        ..color = done == 0
            ? spent
            : accent.withValues(alpha: done >= 1 ? 1 : 0.35 + 0.5 * done);
      canvas.drawArc(box, -math.pi / 2 + i * pitch, pitch - gap, false, paint);
    }

    _write(
      canvas,
      percent,
      centre.dx,
      130,
      TextStyle(
        fontFamily: Nocturne.headingFamily,
        fontVariations: Nocturne.headingVariations,
        fontSize: 38,
        color: text,
      ),
    );
    _write(
      canvas,
      ayas,
      centre.dx,
      152,
      TextStyle(fontFamily: Nocturne.bodyFamily, fontSize: 11, color: caption),
    );
    _write(
      canvas,
      here,
      centre.dx,
      174,
      TextStyle(
        fontFamily: Nocturne.bodyFamily,
        fontSize: 10,
        letterSpacing: 1.2,
        color: accent,
      ),
    );
    _write(
      canvas,
      'JUZ 1',
      centre.dx,
      18,
      TextStyle(
        fontFamily: Nocturne.bodyFamily,
        fontSize: 9.5,
        letterSpacing: 1.6,
        color: edge,
      ),
    );
  }

  /// Draws one line centred on [x] with its baseline on [baseline], which is
  /// how the design places every label in the ring.
  void _write(
    Canvas canvas,
    String line,
    double x,
    double baseline,
    TextStyle style,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: line, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    final top =
        baseline -
        painter.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    painter.paint(canvas, Offset(x - painter.width / 2, top));
  }

  @override
  bool shouldRepaint(_JuzRing old) =>
      old.percent != percent || old.here != here || old.juz != juz;
}
