import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import '../../data/db.dart';
import '../../data/sets.dart';
import '../../theme/nocturne.dart';
import '../../widgets/nocturne_button.dart';
import '../../widgets/nocturne_segmented.dart';
import '../../widgets/nocturne_tag.dart';

/// Screen 1a — the set the reader studies before praying it.
///
/// The recitation bar and "Mark set understood" are drawn disabled: the audio
/// and the outbox op behind them belong to later phases, and a control that
/// looks live and does nothing is worse than one that says it is not ready.
class StudyScreen extends StatefulWidget {
  const StudyScreen({super.key, required this.db});

  final Database db;

  @override
  State<StudyScreen> createState() => _StudyScreenState();
}

class _StudyScreenState extends State<StudyScreen> {
  StudySet? _set;
  RootDetail? _root;
  StudyWord? _word;
  String? _reciter;
  ReadingOrder _order = ReadingOrder.nuzul;
  bool _loaded = false;
  bool _settingsOpen = false;
  int _display = 0;
  double _arabicSize = 31;

  bool get _showGloss => _display == 0 || _display == 2;
  bool get _showTranslit => _display == 1 || _display == 2;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final order = await readingOrder(widget.db);
    final set = await nextSet(widget.db, order);
    final reciter = await reciterLabel(widget.db);
    final rooted =
        set?.ayas.expand((a) => a.words).where((w) => w.root != null).toList() ??
        const <StudyWord>[];
    final first = rooted.isEmpty ? null : rooted.first;
    final root = first == null
        ? null
        : await rootDetail(widget.db, first.root!);
    if (!mounted) return;
    setState(() {
      _order = order;
      _set = set;
      _reciter = reciter;
      _word = first;
      _root = root;
      _loaded = true;
    });
  }

  /// The panel keeps the root it is showing until the next one has been read,
  /// so a tap never blanks the screen the reader is looking at.
  Future<void> _openRoot(StudyWord word) async {
    final detail = await rootDetail(widget.db, word.root!);
    if (!mounted || detail == null) return;
    setState(() {
      _word = word;
      _root = detail;
    });
  }

  @override
  Widget build(BuildContext context) {
    final n = Nocturne.of(context);
    final set = _set;
    return Scaffold(
      backgroundColor: n.bg,
      body: SafeArea(
        child: !_loaded
            ? const SizedBox.shrink()
            : set == null
            ? _finished(n)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _header(n, set),
                  _progress(n, set),
                  if (_settingsOpen) _settings(n),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          _ayas(n, set),
                          Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: n.space('6'),
                            ),
                            child: _audioBar(n),
                          ),
                          SizedBox(height: n.space('6')),
                        ],
                      ),
                    ),
                  ),
                  _rootPanel(n),
                ],
              ),
      ),
    );
  }

  Widget _finished(Nocturne n) => Center(
    child: Padding(
      padding: EdgeInsets.all(n.space('8')),
      child: Text(
        'Every aya is understood. There is nothing left to serve.',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.headlineSmall,
      ),
    ),
  );

  Widget _header(Nocturne n, StudySet set) {
    final first = set.ayas.first;
    final place = first.revelationPlace;
    final kicker = _order == ReadingOrder.nuzul
        ? 'Revelation ${first.revelationOrder} · ${_capitalise(place)}'
        : 'Sūra ${first.surahId} · ${_capitalise(place)}';
    return Padding(
      padding: EdgeInsets.fromLTRB(n.space('6'), n.space('2'), n.space('6'), 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  kicker.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    height: 1.2,
                    letterSpacing: 0.11 * 10,
                    color: n.accent,
                  ),
                ),
                SizedBox(height: n.space('1')),
                Text(set.title, style: Theme.of(context).textTheme.displaySmall),
                SizedBox(height: n.space('1')),
                Text(
                  first.surahNameAr,
                  textDirection: TextDirection.rtl,
                  style: TextStyle(
                    fontFamily: Nocturne.arabicFamily,
                    fontSize: 13,
                    color: n.textAt(0.5),
                  ),
                ),
              ],
            ),
          ),
          NocturneButton(
            variant: NocturneButtonVariant.icon,
            child: const Icon(Icons.bookmark_border),
          ),
          SizedBox(width: n.space('1')),
          NocturneButton(
            variant: NocturneButtonVariant.icon,
            onPressed: () => setState(() => _settingsOpen = !_settingsOpen),
            child: const Icon(Icons.tune),
          ),
        ],
      ),
    );
  }

  Widget _progress(Nocturne n, StudySet set) => Padding(
    padding: EdgeInsets.fromLTRB(
      n.space('6'),
      n.space('6'),
      n.space('6'),
      0,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          spacing: n.space('2'),
          children: [
            for (final aya in set.ayas)
              Expanded(
                child: Container(
                  height: 3,
                  decoration: BoxDecoration(
                    color: aya.understood ? n.accent : n.color('neutral-800'),
                    borderRadius: BorderRadius.circular(2),
                    boxShadow: aya.understood
                        ? [
                            BoxShadow(
                              color: n.accent.withValues(alpha: 0.6),
                              blurRadius: 10,
                            ),
                          ]
                        : null,
                  ),
                ),
              ),
          ],
        ),
        SizedBox(height: n.space('2')),
        Text(
          _progressCaption(set.ayas),
          style: TextStyle(fontSize: 10.5, color: n.textAt(0.42)),
        ),
      ],
    ),
  );

  Widget _settings(Nocturne n) => Padding(
    padding: EdgeInsets.fromLTRB(
      n.space('6'),
      n.space('4'),
      n.space('6'),
      0,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        NocturneSegmented(
          options: const ['Gloss', 'Translit', 'Both', 'Neither'],
          selected: _display,
          onChanged: (i) => setState(() => _display = i),
        ),
        Row(
          children: [
            Text(
              'Arabic ${_arabicSize.round()} px',
              style: TextStyle(fontSize: 11, color: n.textAt(0.55)),
            ),
            Expanded(
              child: SliderTheme(
                data: SliderThemeData(
                  activeTrackColor: n.accent,
                  inactiveTrackColor: n.color('neutral-800'),
                  thumbColor: n.accent,
                  overlayColor: n.accent.withValues(alpha: 0.12),
                  trackHeight: 2,
                ),
                child: Slider(
                  min: 24,
                  max: 44,
                  divisions: 20,
                  value: _arabicSize,
                  onChanged: (v) => setState(() => _arabicSize = v),
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _ayas(Nocturne n, StudySet set) => Padding(
    padding: EdgeInsets.fromLTRB(
      n.space('6'),
      n.space('6'),
      n.space('6'),
      n.space('6'),
    ),
    child: Column(
      children: [
        for (final (i, aya) in set.ayas.indexed) ...[
          if (i > 0)
            Padding(
              padding: EdgeInsets.symmetric(vertical: n.space('2')),
              child: const _DashedRule(),
            ),
          Wrap(
            textDirection: TextDirection.rtl,
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.end,
            spacing: 14,
            runSpacing: n.space('1'),
            children: [
              for (final word in aya.words) _wordTile(n, word),
              _ayaMark(n, aya.number),
            ],
          ),
        ],
      ],
    ),
  );

  Widget _wordTile(Nocturne n, StudyWord word) {
    final hasRoot = word.root != null;
    final underline = !hasRoot
        ? Colors.transparent
        : word.id == _word?.id
        ? n.accent
        : n.color('accent-700');
    return GestureDetector(
      // Keyed by the corpus id so the tile keeps its element across a rebuild,
      // rather than being matched by position against a different word.
      key: ValueKey(word.id),
      onTap: hasRoot ? () => _openRoot(word) : null,
      child: Container(
        padding: EdgeInsets.fromLTRB(3, n.space('1'), 3, n.space('1')),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: underline, width: 2)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              word.text,
              textDirection: TextDirection.rtl,
              style: TextStyle(
                fontFamily: Nocturne.arabicFamily,
                fontSize: _arabicSize,
                height: 1.75,
                color: n.text,
              ),
            ),
            if (_showTranslit && word.translit != null)
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
            if (_showGloss && word.gloss != null)
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

  Widget _ayaMark(Nocturne n, int number) => Container(
    width: 26,
    height: 26,
    margin: const EdgeInsets.only(bottom: 22),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(color: n.color('accent-700')),
    ),
    child: Text(
      _arabicDigits(number),
      textDirection: TextDirection.rtl,
      style: TextStyle(
        fontFamily: Nocturne.arabicFamily,
        fontSize: 12,
        color: n.color('accent-300'),
      ),
    ),
  );

  Widget _audioBar(Nocturne n) => Container(
    padding: EdgeInsets.symmetric(
      horizontal: n.space('3'),
      vertical: n.space('2'),
    ),
    decoration: BoxDecoration(
      color: n.surface,
      borderRadius: BorderRadius.circular(n.radius('md')),
      boxShadow: n.shadow('sm'),
    ),
    child: Row(
      spacing: n.space('3'),
      children: [
        NocturneButton(
          variant: NocturneButtonVariant.icon,
          child: const Icon(Icons.play_arrow),
        ),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            spacing: 2.5,
            children: [
              for (final (i, height) in const [20.0, 14.0, 18.0, 9.0, 6.0]
                  .indexed)
                Container(
                  width: 2.5,
                  height: height,
                  decoration: BoxDecoration(
                    color: i < 3
                        ? n.accent
                        : n.color(i == 3 ? 'accent-600' : 'accent-700'),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              const Expanded(
                child: Padding(
                  padding: EdgeInsets.only(bottom: 9),
                  child: _DashedRule(),
                ),
              ),
            ],
          ),
        ),
        if (_reciter != null)
          Text(
            _reciter!,
            style: TextStyle(fontSize: 10.5, color: n.textAt(0.55)),
          ),
      ],
    ),
  );

  Widget _rootPanel(Nocturne n) {
    final root = _root;
    return Container(
      padding: EdgeInsets.fromLTRB(
        n.space('6'),
        n.space('4'),
        n.space('6'),
        n.space('8'),
      ),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: n.divider)),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: const [0, 0.7],
          colors: [
            n.accent.withValues(alpha: 0.07),
            n.accent.withValues(alpha: 0),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (root == null)
            Text(
              'No word in this set carries a root.',
              style: TextStyle(fontSize: 13, color: n.textAt(0.62)),
            )
          else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  root.display,
                  textDirection: TextDirection.rtl,
                  style: TextStyle(
                    fontFamily: Nocturne.arabicFamily,
                    fontSize: 26,
                    letterSpacing: 0.14 * 26,
                    color: n.color('accent-300'),
                  ),
                ),
                SizedBox(width: n.space('3')),
                Expanded(
                  child: Text(
                    root.translit,
                    style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 0.06 * 11,
                      color: n.textAt(0.55),
                    ),
                  ),
                ),
                NocturneTag(
                  '${root.occurrences}×',
                  variant: NocturneTagVariant.outline,
                ),
              ],
            ),
            Padding(
              padding: EdgeInsets.symmetric(vertical: n.space('3')),
              child: const _DashedRule(),
            ),
            // The design's "core sense" prose is lexicon text, which arrives
            // over the network in a later phase. What the corpus itself knows
            // about this word is its gloss in this aya, so that is what the
            // section says it is.
            Text(
              'IN THIS AYA',
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 0.11 * 10,
                color: n.accent,
              ),
            ),
            SizedBox(height: n.space('1')),
            Text(
              _word?.gloss ?? '—',
              style: TextStyle(fontSize: 13.5, height: 1.5, color: n.text),
            ),
            SizedBox(height: n.space('3')),
            Wrap(
              spacing: n.space('2'),
              runSpacing: n.space('2'),
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                // The tag sets everything about its label but the family, so
                // the Arabic face reaches it through the default style.
                for (final kin in root.kin.take(4))
                  DefaultTextStyle.merge(
                    style: const TextStyle(fontFamily: Nocturne.arabicFamily),
                    child: NocturneTag(
                      kin.text,
                      variant: NocturneTagVariant.neutral,
                    ),
                  ),
                Text(
                  root.sources.join(', '),
                  style: TextStyle(fontSize: 11, color: n.textAt(0.45)),
                ),
              ],
            ),
          ],
          SizedBox(height: n.space('3')),
          Row(
            spacing: n.space('3'),
            children: [
              const Expanded(
                child: NocturneButton(child: Text('Open constellation')),
              ),
              const Expanded(
                child: NocturneButton(
                  variant: NocturneButtonVariant.primary,
                  child: Text('Mark set understood'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String _capitalise(String word) =>
    word.isEmpty ? word : word[0].toUpperCase() + word.substring(1);

String _arabicDigits(int number) => number
    .toString()
    .split('')
    .map((d) => String.fromCharCode(0x0660 + int.parse(d)))
    .join();

String _progressCaption(List<StudyAya> ayas) {
  final done = [for (final a in ayas) if (a.understood) a.number];
  final open = [for (final a in ayas) if (!a.understood) a.number];
  if (done.isEmpty) return 'No aya marked understood yet';
  if (open.isEmpty) return 'Every aya in this set is understood';
  return 'Aya ${_numbers(done)} marked understood · aya ${_numbers(open)} open';
}

String _numbers(List<int> numbers) => numbers.length == 1
    ? '${numbers.first}'
    : '${numbers.sublist(0, numbers.length - 1).join(', ')} and ${numbers.last}';

/// The design's separators are dashes, not rules: 2 px on, 5 px off.
class _DashedRule extends StatelessWidget {
  const _DashedRule();

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    height: 1,
    child: CustomPaint(painter: _DashPainter(Nocturne.of(context).textAt(0.22))),
  );
}

class _DashPainter extends CustomPainter {
  const _DashPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    for (var x = 0.0; x < size.width; x += 7) {
      canvas.drawRect(Rect.fromLTWH(x, 0, 2, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(_DashPainter old) => old.color != color;
}
