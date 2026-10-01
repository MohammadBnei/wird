import 'dart:math';

import 'package:flutter/material.dart';

import '../../data/root_repo.dart';
import '../../data/sets.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/nocturne.dart';
import '../../widgets/nocturne_button.dart';
import '../../widgets/nocturne_tag.dart';
import 'lemma_ring.dart';
import '../root/root_sections.dart' show irabWork;
import 'study_chrome.dart' show DashedRule;

/// Everything the root sheet shows for one word, read together so the sheet
/// never draws one word's root beside another word's counts.
typedef SheetWord = ({
  StudyWord word,
  RootReading? root,
  List<Lemma> lemmas,
  int inSurah,
  List<RootAya> ayas,
  List<IrabSegment> irab,
});

/// The lower half of the reading screen: the open word's root, and a
/// horizontal swipe to the word before or after it.
///
/// Arabic reads leftward, so the next word comes in from the left: a drag to
/// the right moves on. The arrows in the hint row do the same thing for a
/// reader who cannot drag, and for a screen reader (ADR 0013).
class RootSheet extends StatefulWidget {
  const RootSheet({
    super.key,
    required this.sheet,
    required this.expanded,
    required this.previous,
    required this.next,
    required this.onPrevious,
    required this.onNext,
    required this.onToggle,
    required this.onExpand,
    required this.onAya,
    required this.scroll,
    required this.onRoot,
    required this.onJudge,
    required this.onConstellation,
  });

  final SheetWord sheet;
  final bool expanded;

  /// The words either side, for the hint row; null at the ends of the sūra.
  final StudyWord? previous;
  final StudyWord? next;

  /// Null where there is no word to step to.
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  final VoidCallback onToggle;
  final VoidCallback onExpand;
  final void Function(RootAya aya) onAya;

  /// The sheet's own scroll, which the screen puts back at the top when the
  /// word changes.
  final ScrollController scroll;

  /// Opens the root's own screen: its dial or spine, its constellation and
  /// its parsing, which the sheet has no room for.
  final void Function(String letters) onRoot;

  /// The reader's yes or no on the root's sense (ADR 0010).
  final void Function(String root, bool good) onJudge;

  /// Opens the deep dive: this aya and this root's whole family, drawn as a
  /// constellation where the window is wide enough.
  final void Function(String letters) onConstellation;

  @override
  State<RootSheet> createState() => _RootSheetState();
}

class _RootSheetState extends State<RootSheet> {
  /// How far the word block has been dragged, and whether a finger is on it.
  double _dx = 0;
  bool _dragging = false;

  /// A drag that started within reach of the screen's edge belongs to the
  /// drawer or to the system's back gesture, not to the walk.
  bool _ignored = false;

  static const _edge = 24.0;
  static const _threshold = 60.0;

  void _start(DragStartDetails d) {
    final width = MediaQuery.sizeOf(context).width;
    _ignored =
        d.globalPosition.dx < _edge || d.globalPosition.dx > width - _edge;
  }

  void _update(DragUpdateDetails d) {
    if (_ignored) return;
    final dx = _dx + d.delta.dx;
    // Resisted where there is nowhere to go.
    final stuck =
        (dx > 0 && widget.onNext == null) ||
        (dx < 0 && widget.onPrevious == null);
    setState(() {
      _dragging = true;
      _dx = stuck ? _dx + d.delta.dx * 0.25 : dx;
    });
  }

  void _end(DragEndDetails _) {
    if (_ignored) return;
    final go = _dx > _threshold
        ? widget.onNext
        : _dx < -_threshold
        ? widget.onPrevious
        : null;
    setState(() {
      _dragging = false;
      _dx = 0;
    });
    go?.call();
  }

  @override
  Widget build(BuildContext context) {
    final n = Nocturne.of(context);
    final l = AppLocalizations.of(context)!;
    final sheet = widget.sheet;
    final root = sheet.root;
    return Container(
      decoration: BoxDecoration(
        color: n.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x59000000),
            blurRadius: 30,
            offset: Offset(0, -10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            label: widget.expanded
                ? l.study_collapseSheet
                : l.study_expandSheet,
            child: GestureDetector(
              key: const Key('sheet handle'),
              behavior: HitTestBehavior.opaque,
              onTap: widget.onToggle,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 8, 0, 4),
                child: Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: n.color('neutral-700'),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
          ),
          _hints(n, l),
          Expanded(
            child: NotificationListener<ScrollUpdateNotification>(
              onNotification: (note) {
                if (!widget.expanded && note.metrics.pixels > 24) {
                  widget.onExpand();
                }
                return false;
              },
              child: SingleChildScrollView(
                controller: widget.scroll,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    GestureDetector(
                      key: const Key('swipe'),
                      behavior: HitTestBehavior.opaque,
                      onHorizontalDragStart: _start,
                      onHorizontalDragUpdate: _update,
                      onHorizontalDragEnd: _end,
                      child: AnimatedOpacity(
                        duration: _dragging
                            ? Duration.zero
                            : const Duration(milliseconds: 200),
                        opacity: _dx == 0 ? 1 : max(0.35, 1 - _dx.abs() / 260),
                        child: AnimatedContainer(
                          duration: _dragging
                              ? Duration.zero
                              : const Duration(milliseconds: 200),
                          transform: Matrix4.translationValues(_dx, 0, 0),
                          padding: const EdgeInsets.fromLTRB(18, 6, 18, 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (root != null)
                                ..._rooted(n, l, root)
                              else
                                _particle(n, l),
                              _inThisVerse(n, l),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (!widget.expanded) _moreRow(n, l),
                    if (root != null) _secondary(n, l, root),
                    if (root == null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
                        child: Text(
                          l.study_particleNote,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.5,
                            color: n.textAt(0.55),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// "‹ next · swipe · previous ›" — the words a drag would land on, and the
  /// two ways to get there without one.
  Widget _hints(Nocturne n, AppLocalizations l) {
    final hint = TextStyle(fontSize: 11, color: n.textAt(0.5));
    final arabic = TextStyle(
      fontFamily: Nocturne.arabicFamily,
      fontSize: 15,
      color: n.textAt(0.5),
    );
    Widget side(StudyWord? word, VoidCallback? go, String label, bool next) =>
        Expanded(
          child: Semantics(
            button: true,
            enabled: go != null,
            label: label,
            child: GestureDetector(
              key: Key(next ? 'next word' : 'previous word'),
              behavior: HitTestBehavior.opaque,
              onTap: go,
              child: Row(
                mainAxisAlignment: next
                    ? MainAxisAlignment.start
                    : MainAxisAlignment.end,
                children: [
                  if (next) Text('‹ ', style: hint),
                  if (word != null)
                    Flexible(
                      child: Text(
                        word.text,
                        textDirection: TextDirection.rtl,
                        overflow: TextOverflow.ellipsis,
                        style: arabic,
                      ),
                    ),
                  if (!next) Text(' ›', style: hint),
                ],
              ),
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Row(
        children: [
          side(widget.next, widget.onNext, l.study_nextWord, true),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(l.study_swipe, style: hint),
          ),
          side(widget.previous, widget.onPrevious, l.study_previousWord, false),
        ],
      ),
    );
  }

  List<Widget> _rooted(Nocturne n, AppLocalizations l, RootReading root) {
    final word = widget.sheet.word;
    final senses = root.coreSense
        ?.split('; ')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    return [
      Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Semantics(
            button: true,
            label: l.study_openRoot(root.translit),
            child: GestureDetector(
              key: const ValueKey('open-root'),
              onTap: () => widget.onRoot(root.letters),
              child: Text(
                root.display,
                textDirection: TextDirection.rtl,
                style: TextStyle(
                  fontFamily: Nocturne.arabicFamily,
                  fontSize: 38,
                  height: 1.35,
                  letterSpacing: 38 * 0.14,
                  color: n.text,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Gives way first when the row is short of room: at a large system
          // text size the root and the word fill it between them.
          Expanded(
            child: Text(
              root.translit,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, color: n.textAt(0.62)),
            ),
          ),
          _wordItself(n, word, 20),
        ],
      ),
      if (senses != null && senses.isNotEmpty) ...[
        const SizedBox(height: 12),
        _kicker(n, l.study_senses),
        const SizedBox(height: 4),
        for (final (i, sense) in senses.indexed)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                SizedBox(
                  width: 18,
                  child: Text(
                    '${i + 1}',
                    style: TextStyle(fontSize: 11, color: n.textAt(0.4)),
                  ),
                ),
                Expanded(
                  child: Text(
                    sense,
                    style: TextStyle(
                      fontSize: 13.5,
                      height: 1.4,
                      color: n.textAt(0.7),
                    ),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 4),
        JudgeSense(
          key: ValueKey('judge ${root.letters}'),
          root: root.letters,
          onJudge: widget.onJudge,
        ),
      ],
    ];
  }

  Widget _particle(Nocturne n, AppLocalizations l) => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      _wordItself(n, widget.sheet.word, 34, end: false),
      const Spacer(),
      NocturneTag(l.study_wordHasNoRoot),
    ],
  );

  Widget _wordItself(
    Nocturne n,
    StudyWord word,
    double size, {
    bool end = true,
  }) => Column(
    crossAxisAlignment: end ? CrossAxisAlignment.end : CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        word.text,
        textDirection: TextDirection.rtl,
        style: TextStyle(
          fontFamily: Nocturne.arabicFamily,
          fontSize: size,
          height: 1.4,
          color: n.color('accent-200'),
        ),
      ),
      if (word.translit != null)
        Text(
          word.translit!,
          style: TextStyle(fontSize: 11, color: n.textAt(0.6)),
        ),
    ],
  );

  /// What the word is doing in this aya: its gloss, and how the corpus parses
  /// it. The design also gives a sentence on its meaning here and a note on
  /// what its form adds; Wird has neither, so neither is drawn.
  Widget _inThisVerse(Nocturne n, AppLocalizations l) {
    final word = widget.sheet.word;
    final gloss = word.glossIn(Localizations.localeOf(context)) ?? '';
    final irab = widget.sheet.irab;
    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Color.alphaBlend(n.accent.withValues(alpha: 0.10), n.bg),
        borderRadius: BorderRadius.circular(n.radius('lg')),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.study_inThisVerse(gloss).toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              letterSpacing: 1.1,
              color: n.color('accent-300'),
            ),
          ),
          if (irab.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: const DashedRule(),
            ),
            for (final segment in irab)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: segment.role,
                        style: TextStyle(color: n.color('accent-200')),
                      ),
                      if (segment.features.isNotEmpty)
                        TextSpan(
                          text: ' · ${segment.features.join(' · ')}',
                          style: TextStyle(color: n.textAt(0.76)),
                        ),
                    ],
                  ),
                  style: const TextStyle(fontSize: 12.5, height: 1.5),
                ),
              ),
            Text(
              l.root_irabProvenance(irabWork),
              style: TextStyle(
                fontSize: 10,
                height: 1.5,
                color: n.textAt(0.45),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _moreRow(Nocturne n, AppLocalizations l) => GestureDetector(
    key: const Key('more row'),
    behavior: HitTestBehavior.opaque,
    onTap: widget.onExpand,
    child: Container(
      margin: const EdgeInsets.fromLTRB(18, 6, 18, 0),
      height: 40,
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: n.divider)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              l.study_moreRow,
              style: TextStyle(fontSize: 12.5, color: n.textAt(0.7)),
            ),
          ),
          Icon(Icons.expand_less, size: 16, color: n.textAt(0.7)),
        ],
      ),
    ),
  );

  Widget _secondary(Nocturne n, AppLocalizations l, RootReading root) {
    final sheet = widget.sheet;
    final lemma = sheet.lemmas
        .where((x) => x.key == sheet.word.lemmaKey)
        .firstOrNull;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _kicker(n, l.study_acrossQuran),
          const SizedBox(height: 8),
          Row(
            spacing: 8,
            children: [
              _tile(n, '${root.occurrences}', Text(l.study_countRoot)),
              if (lemma != null)
                _tile(
                  n,
                  '${lemma.occurrences}',
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: '${l.study_countLemma} '),
                        TextSpan(
                          text: lemma.text,
                          style: const TextStyle(
                            fontFamily: Nocturne.arabicFamily,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              _tile(n, '${sheet.inSurah}', Text(l.study_countSurah)),
            ],
          ),
          if (sheet.lemmas.isNotEmpty) ...[
            const SizedBox(height: 10),
            LemmaRing(
              root: root.display,
              lemmas: sheet.lemmas,
              current: sheet.word.lemmaKey,
            ),
            Center(
              child: Text(
                l.study_ringCaption,
                style: TextStyle(fontSize: 10.5, color: n.textAt(0.55)),
              ),
            ),
            Center(
              child: TextButton(
                key: const Key('constellation'),
                onPressed: () => widget.onConstellation(root.letters),
                child: Text(l.study_constellation),
              ),
            ),
          ],
          if (sheet.ayas.isNotEmpty) ...[
            const SizedBox(height: 20),
            _kicker(n, l.study_otherAyas),
            const SizedBox(height: 4),
            for (final aya in sheet.ayas) _ayaRow(n, aya),
          ],
        ],
      ),
    );
  }

  Widget _tile(Nocturne n, String number, Widget label) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: n.bg,
        borderRadius: BorderRadius.circular(n.radius('md')),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            number,
            style: TextStyle(
              fontFamily: Nocturne.headingFamily,
              fontSize: 20,
              color: n.text,
            ),
          ),
          DefaultTextStyle.merge(
            style: TextStyle(fontSize: 11, color: n.textAt(0.6)),
            child: label,
          ),
        ],
      ),
    ),
  );

  Widget _ayaRow(Nocturne n, RootAya aya) => InkWell(
    key: Key('other aya ${aya.ayahId}'),
    onTap: () => widget.onAya(aya),
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: n.divider)),
      ),
      child: Row(
        spacing: 12,
        children: [
          SizedBox(
            width: 52,
            child: Text(
              ayahRef(aya.ayahId),
              style: TextStyle(fontSize: 11.5, color: n.color('accent-300')),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  aya.text,
                  textDirection: TextDirection.rtl,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: Nocturne.arabicFamily,
                    fontSize: 18,
                    height: 1.6,
                    color: n.text,
                  ),
                ),
                if (aya.translation != null)
                  Text(
                    aya.translation!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: n.textAt(0.66),
                    ),
                  ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, size: 15, color: n.textAt(0.5)),
        ],
      ),
    ),
  );

  Widget _kicker(Nocturne n, String text) => Text(
    text.toUpperCase(),
    style: TextStyle(fontSize: 10, letterSpacing: 1.1, color: n.textAt(0.55)),
  );
}

/// Yes or no on the sense above, and then nothing.
///
/// Stateful only to stop asking once answered: a control that stays live invites a
/// second press, and two verdicts from one reader on one root is noise in the one
/// signal this feature exists to collect. It does not undo — a reader who
/// mis-taps has said something true about how clear the sense was.
class JudgeSense extends StatefulWidget {
  const JudgeSense({super.key, required this.root, required this.onJudge});

  final String root;
  final void Function(String root, bool good) onJudge;

  @override
  State<JudgeSense> createState() => _JudgeSenseState();
}

class _JudgeSenseState extends State<JudgeSense> {
  bool _answered = false;

  void _say(bool good) {
    if (_answered) return;
    setState(() => _answered = true);
    widget.onJudge(widget.root, good);
  }

  @override
  Widget build(BuildContext context) {
    final n = Nocturne.of(context);
    final l = AppLocalizations.of(context)!;
    final quiet = TextStyle(fontSize: 10.5, color: n.textAt(0.45));
    if (_answered) {
      return Text(l.root_senseJudgeThanks, style: quiet);
    }
    // Two thumbs and no question. The sense is directly above them, so what is
    // being judged needs no naming; a screen reader gets the naming through the
    // Semantics label, which is the one thing here that is not an icon.
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (good, icon, semantics) in [
          (true, Icons.thumb_up_outlined, l.root_senseJudgeGoodLabel),
          (false, Icons.thumb_down_outlined, l.root_senseJudgeBadLabel),
        ])
          Padding(
            padding: EdgeInsets.only(right: n.space('2')),
            child: Semantics(
              button: true,
              label: semantics,
              child: NocturneButton(
                key: Key('judge sense ${good ? 'good' : 'bad'}'),
                variant: NocturneButtonVariant.icon,
                onPressed: () => _say(good),
                child: Icon(icon, size: 16),
              ),
            ),
          ),
      ],
    );
  }
}
