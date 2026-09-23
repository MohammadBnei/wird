import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../data/sets.dart';
import '../../theme/nocturne.dart';
import '../../widgets/nocturne_button.dart';
import 'prayer_cursor.dart';

/// Screen 1b — the set recited inside the prayer.
///
/// It runs in a room that usually has no signal, while the reader recites from
/// memory and is not looking at the phone. So it reads nothing, asks for
/// nothing and downloads nothing: the set arrives from screen 1a already read,
/// which is what leaves this screen with no dialog, no error and no spinner to
/// show. The recitation is the reader's own voice, so the audio the app holds
/// stays silent here.
///
/// The design reads "nothing to tap". Until voice-follow lands in phase 11 the
/// cursor is moved by hand, so the field is split into two tap zones — a large
/// one that goes on and a smaller one that steps back — sized to be hit
/// without being looked at. The deviation is recorded in the plan.
class PrayerScreen extends StatefulWidget {
  const PrayerScreen({
    super.key,
    required this.db,
    required this.set,
    this.cursor,
    this.wakelock = WakelockPlus.toggle,
  });

  final Database db;
  final StudySet set;

  /// Supplied by the golden, which needs the prayer held on one frame.
  final PrayerCursor? cursor;

  /// Supplied by the test that has to prove the phone is kept awake for the
  /// whole prayer and let go of afterwards.
  final Future<void> Function({required bool enable}) wakelock;

  static const nextZone = Key('prayer next');
  static const backZone = Key('prayer back');

  @override
  State<PrayerScreen> createState() => _PrayerScreenState();
}

/// The design's own geometry, in its own numbers. The space scale stops at
/// 22.4 and the rhythm of this screen is set by its type, so the gaps between
/// the lines are read off the mockup where no step carries them.
const _side = 26.0;
const _foot = 46.0;
const _previewSize = 25.0;
const _previewHeight = 1.9;
const _reciting = 52.0;

class _PrayerScreenState extends State<PrayerScreen> {
  late final List<({StudyAya aya, StudyWord word})> _flat = [
    for (final aya in widget.set.ayas)
      for (final word in aya.words) (aya: aya, word: word),
  ];
  late final PrayerCursor _cursor = widget.cursor ?? PrayerCursor(_flat.length);

  @override
  void initState() {
    super.initState();
    _cursor.addListener(_redraw);
    unawaited(_keepAwake(true));
  }

  @override
  void dispose() {
    _cursor.removeListener(_redraw);
    unawaited(_keepAwake(false));
    if (widget.cursor == null) _cursor.dispose();
    super.dispose();
  }

  void _redraw() => setState(() {});

  Future<void> _keepAwake(bool awake) async {
    try {
      await widget.wakelock(enable: awake);
    } on Object {
      // A phone that will not hold the screen open is still a phone someone
      // is praying with. There is nothing to say about it here.
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = Nocturne.of(context);
    final here = _flat.isEmpty ? null : _flat[_cursor.word % _flat.length];
    final ayas = widget.set.ayas;
    final at = here == null ? -1 : ayas.indexOf(here.aya);
    return Scaffold(
      backgroundColor: n.bg,
      body: DecoratedBox(
        // The design's ground: a bloom of the accent behind the reciter,
        // falling back to the page. Its `#1b1d31` is that bloom at five
        // percent over the background, and an ellipse where Flutter draws a
        // circle.
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -0.32),
            radius: 1.2,
            colors: [
              Color.alphaBlend(n.accent.withValues(alpha: 0.05), n.bg),
              n.bg,
            ],
            stops: const [0, 0.62],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _chrome(n),
              Expanded(
                child: _field(
                  n,
                  here,
                  at > 0 ? ayas[at - 1] : null,
                  at >= 0 && at < ayas.length - 1 ? ayas[at + 1] : null,
                ),
              ),
              _strip(n),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chrome(Nocturne n) => Padding(
    padding: EdgeInsets.fromLTRB(n.space('8'), n.space('4'), n.space('8'), 0),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          spacing: n.space('3'),
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: n.accent,
                boxShadow: [BoxShadow(color: n.accent, blurRadius: 8)],
              ),
            ),
            // The design says "Following your voice". Nothing is listening
            // until phase 11 turns voice-follow on, and a screen that claims
            // to hear the reader when it does not is worse than a plain one.
            Text(
              'IN PRAYER',
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 0.13 * 10,
                color: n.accent,
              ),
            ),
          ],
        ),
        NocturneButton(
          variant: NocturneButtonVariant.ghost,
          onPressed: () => Navigator.of(context).maybePop(),
          child: Text(
            'Exit',
            style: TextStyle(fontSize: 12, color: n.textAt(0.6)),
          ),
        ),
      ],
    ),
  );

  Widget _field(
    Nocturne n,
    ({StudyAya aya, StudyWord word})? here,
    StudyAya? before,
    StudyAya? after,
  ) {
    final gloss = here == null
        ? ''
        : [
            for (final w in here.aya.words)
              if (w.gloss != null) w.gloss!,
          ].join(' ');
    final note = here?.word.gloss ?? here?.word.translit;
    return Stack(
      children: [
        // An aya too long for the field runs off the top and bottom of it
        // rather than striping an overflow banner across the prayer: 2:282 is
        // a page by itself and the word budget lets it be a set on its own.
        Positioned.fill(
          child: IgnorePointer(
            child: ClipRect(
              child: OverflowBox(
                // The field is tight, so the minimum has to be let go of too
                // or the column is stretched to it and paints from the top.
                minHeight: 0,
                maxHeight: double.infinity,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: _side),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _preview(n, before, 0.24),
                      const SizedBox(height: 18),
                      if (here != null) _recited(n, here),
                      const SizedBox(height: 24),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 34),
                        child: _DottedRule(),
                      ),
                      SizedBox(height: n.space('6')),
                      if (gloss.isNotEmpty)
                        Text(
                          gloss,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            height: 1.55,
                            color: n.textAt(0.72),
                          ),
                        ),
                      SizedBox(height: n.space('2')),
                      if (here != null)
                        Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: here.word.text,
                                style: const TextStyle(
                                  fontFamily: Nocturne.arabicFamily,
                                ),
                              ),
                              if (note != null) TextSpan(text: ' · $note'),
                            ],
                          ),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11.5,
                            height: 1.5,
                            color: n.textAt(0.4),
                          ),
                        ),
                      const SizedBox(height: 34),
                      _preview(n, after, 0.18),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        // The whole field advances the prayer; a narrower strip at its left
        // edge steps back. A person mid-prayer is not aiming at anything.
        Positioned.fill(
          child: Row(
            children: [
              Expanded(
                child: _zone(
                  PrayerScreen.backZone,
                  'Back a word',
                  _cursor.back,
                ),
              ),
              Expanded(
                flex: 2,
                child: _zone(
                  PrayerScreen.nextZone,
                  'On to the next word',
                  _cursor.next,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _zone(Key key, String label, VoidCallback onTap) => Semantics(
    button: true,
    label: label,
    child: GestureDetector(
      key: key,
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: const SizedBox.expand(),
    ),
  );

  /// The aya before or after the one being recited, kept to a single line so
  /// the frame under the reciter never reflows as the prayer moves.
  Widget _preview(Nocturne n, StudyAya? aya, double opacity) => SizedBox(
    height: _previewSize * _previewHeight,
    child: aya == null
        ? null
        : Text(
            [for (final w in aya.words) w.text].join(' '),
            textDirection: TextDirection.rtl,
            textAlign: TextAlign.center,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: Nocturne.arabicFamily,
              fontSize: _previewSize,
              height: _previewHeight,
              color: n.textAt(opacity),
            ),
          ),
  );

  Widget _recited(Nocturne n, ({StudyAya aya, StudyWord word}) here) => Wrap(
    textDirection: TextDirection.rtl,
    alignment: WrapAlignment.center,
    crossAxisAlignment: WrapCrossAlignment.end,
    spacing: 16,
    children: [
      for (final word in here.aya.words)
        Text(
          word.text,
          key: ValueKey(word.id),
          textDirection: TextDirection.rtl,
          style: TextStyle(
            fontFamily: Nocturne.arabicFamily,
            fontSize: _reciting,
            height: 1.95,
            color: word.id == here.word.id
                ? n.color('accent-200')
                : word.id < here.word.id
                ? n.text
                : n.textAt(0.3),
            shadows: word.id == here.word.id
                ? [
                    Shadow(
                      color: n.accent.withValues(alpha: 0.65),
                      blurRadius: 28,
                    ),
                  ]
                : null,
          ),
        ),
    ],
  );

  Widget _strip(Nocturne n) {
    final through = (_cursor.word + 1) / _cursor.words;
    return Padding(
      padding: const EdgeInsets.fromLTRB(_side, 0, _side, _foot),
      child: Column(
        children: [
          Row(
            spacing: n.space('4'),
            children: [
              Expanded(
                child: Container(
                  height: 2,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(2),
                    gradient: LinearGradient(
                      colors: [
                        n.accent,
                        n.accent,
                        n.color('neutral-800'),
                        n.color('neutral-800'),
                      ],
                      stops: [0, through, through, 1],
                    ),
                  ),
                ),
              ),
              Text(
                '${_ordinal(_cursor.reading)} reading',
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 0.08 * 10,
                  color: n.textAt(0.58),
                ),
              ),
            ],
          ),
          SizedBox(height: n.space('4')),
          Text(
            'Screen stays awake · tap to go on · left edge steps back',
            style: TextStyle(fontSize: 10.5, color: n.textAt(0.58)),
          ),
        ],
      ),
    );
  }
}

String _ordinal(int count) {
  final teen = count % 100;
  final suffix = teen >= 11 && teen <= 13
      ? 'th'
      : switch (count % 10) {
          1 => 'st',
          2 => 'nd',
          3 => 'rd',
          _ => 'th',
        };
  return '$count$suffix';
}

/// ponytail: screen 1a has its own copy at a different period, and
/// lib/widgets/ belongs to one owner this phase. Lift them into a shared
/// widget the next time a third screen wants a dotted line.
class _DottedRule extends StatelessWidget {
  const _DottedRule();

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    height: 1,
    child: CustomPaint(painter: _DotPainter(Nocturne.of(context).textAt(0.2))),
  );
}

class _DotPainter extends CustomPainter {
  const _DotPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    for (var x = 0.0; x < size.width; x += 8) {
      canvas.drawRect(Rect.fromLTWH(x, 0, 2, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(_DotPainter old) => old.color != color;
}
