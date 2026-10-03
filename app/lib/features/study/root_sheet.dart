import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../data/root_repo.dart';
import '../../data/sets.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/glow.dart';
import '../../theme/nocturne.dart';
import '../../widgets/lit_aya.dart';
import '../../widgets/nocturne_kicker.dart';
import '../../widgets/nocturne_tag.dart';
import 'lemma_ring.dart';
import 'word_swipe.dart';

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

/// The lower half of the reading screen: the open word, its root, and a
/// sideways swipe to the word before or after it ([WordSwipe]).
///
/// It reads in one order: the root, the word as this aya writes it and what
/// it means here; then the root's senses; then the word's form. The top bar
/// opens and closes the lower half — the counts, the forms and the other
/// ayas — and scrolling never does.
class RootSheet extends StatelessWidget {
  /// The space above and below the handle's mark. A folded sheet is this
  /// strip and nothing else, so it is the target a thumb has to find.
  static const handlePad = 12.0;

  /// How tall a folded sheet is: the handle, its mark and its room.
  static const handleHeight = handlePad * 2 + 3;

  const RootSheet({
    super.key,
    required this.sheet,
    required this.expanded,
    this.hidden = false,
    this.folding = false,
    this.onHidden,
    required this.swipe,
    required this.onPrevious,
    required this.onNext,
    required this.onToggle,
    this.onExpand,
    this.onCollapse,
    required this.onAya,
    required this.scroll,
    required this.onRoot,
    required this.onJudge,
    required this.onConstellation,
    required this.translations,
    this.previous,
    this.next,
  });

  final SheetWord sheet;

  /// The words either side, once they have been read, which a swipe drags
  /// in beside this one.
  final SheetWord? previous;
  final SheetWord? next;
  final bool expanded;

  /// Folded down to its handle, so the sūra has the screen to itself: a
  /// reader who only wants to read has no use for the root under every word.
  final bool hidden;

  /// Still going down after [hidden] was set: the root stays drawn until it
  /// has gone, while the handle already answers as a folded sheet's does, so
  /// a drag back up brings the sheet back rather than expanding it.
  final bool folding;

  /// Folds the sheet down to its handle, or back up. A drag on the handle
  /// does it; a tap on a folded handle brings the sheet back.
  final ValueChanged<bool>? onHidden;

  /// The slide the arrows drive, so a step by arrow moves like a swipe.
  final GlobalKey<WordSwipeState> swipe;

  /// Null where there is no word to step to. Each completes once the step
  /// has landed, or has come to nothing.
  final Future<void> Function()? onPrevious;
  final Future<void> Function()? onNext;

  final VoidCallback onToggle;

  /// Opens the lower half, and does nothing if it is open: a drag up on the
  /// handle asks for it on every move.
  final VoidCallback? onExpand;

  /// Closes the lower half, and does nothing if it is closed.
  final VoidCallback? onCollapse;
  final void Function(RootAya aya) onAya;

  /// The sheet's own scroll, which the screen puts back at the top when the
  /// word changes.
  final ScrollController scroll;

  /// Opens the root's own screen: its dial or spine, its constellation and
  /// its parsing, which the sheet has no room for.
  final void Function(String letters) onRoot;

  /// The reader's yes or no on the root's sense (ADR 0010).
  final void Function(String root, bool good) onJudge;

  /// Opens the deep dive on an aya and a root's whole family, drawn as a
  /// constellation where the window is wide enough.
  final void Function(int ayahId, String letters) onConstellation;

  /// Whether the reader shows translations, which the other ayas follow.
  final bool translations;

  @override
  Widget build(BuildContext context) {
    final n = Nocturne.of(context);
    final l = AppLocalizations.of(context)!;
    return Container(
      decoration: BoxDecoration(
        color: n.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        // A soft edge rather than a lid: the sheet sits under the sūra, it
        // does not cover it.
        boxShadow: const [
          BoxShadow(
            color: Color(0x2E000000),
            blurRadius: 16,
            offset: Offset(0, -4),
          ),
        ],
      ),
      clipBehavior: Clip.hardEdge,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _topBar(n, l),
          if (!hidden || folding)
            Expanded(
              child: WordSwipe(
                key: swipe,
                wordId: sheet.word.id,
                onNext: onNext,
                onPrevious: onPrevious,
                nextId: next?.word.id,
                next: _beside(next),
                previousId: previous?.word.id,
                previous: _beside(previous),
                child: SingleChildScrollView(
                  controller: scroll,
                  child: _content(context, n, l),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// This sheet as it would be drawn for [word], for the swipe to show beside
  /// it. Built only while the swipe is under way.
  WidgetBuilder? _beside(SheetWord? word) => word == null
      ? null
      : (context) => RootSheet(
          sheet: word,
          expanded: expanded,
          swipe: swipe,
          onPrevious: onPrevious,
          onNext: onNext,
          onToggle: onToggle,
          onAya: onAya,
          scroll: scroll,
          onRoot: onRoot,
          onJudge: onJudge,
          onConstellation: onConstellation,
          translations: translations,
        )._content(context, Nocturne.of(context), AppLocalizations.of(context)!);

  /// The word, its root's senses, its form, and below them the counts, the
  /// forms and the other ayas.
  Widget _content(BuildContext context, Nocturne n, AppLocalizations l) {
    final root = sheet.root;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The arrows sit at the sheet's edges; the rest is indented as the
        // design draws it.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: _wordRow(context, n, l, root),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (root != null) ..._senses(n, l, root),
              _form(n, l),
            ],
          ),
        ),
        if (!expanded) _moreRow(n, l),
        if (root != null)
          _secondary(n, l, root)
        else
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
    );
  }

  /// The handle: a tap on it opens or closes the lower half, and a drag
  /// folds the sheet away or brings it back.
  Widget _topBar(Nocturne n, AppLocalizations l) => Semantics(
    button: true,
    label: hidden
        ? l.study_showRoot
        : expanded
        ? l.study_collapseSheet
        : l.study_expandSheet,
    customSemanticsActions: {
      if (onHidden != null && !hidden)
        CustomSemanticsAction(label: l.study_hideRoot): () => onHidden!(true),
    },
    child: _Handle(
      key: const Key('sheet handle'),
      expanded: expanded,
      onTap: hidden ? () => onHidden?.call(false) : onToggle,
      onDrag: onHidden == null
          ? null
          : (dy, {required fromExpanded}) {
              if (dy > 0) {
                fromExpanded ? onCollapse?.call() : onHidden!(true);
              } else if (dy < 0) {
                hidden ? onHidden!(false) : onExpand?.call();
              }
            },
      // A faint mark with room around it to tap and to drag.
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: handlePad),
        child: Center(
          child: Container(
            width: 28,
            height: 3,
            decoration: BoxDecoration(
              color: n.textAt(0.14),
              borderRadius: BorderRadius.circular(1.5),
            ),
          ),
        ),
      ),
    ),
  );

  /// A step to the word on one side. Arabic reads leftward, so the next word
  /// is the one on the left. It slides the sheet the way a swipe does.
  Widget _arrow(Nocturne n, AppLocalizations l, {required bool forward}) {
    final go = forward ? onNext : onPrevious;
    return Semantics(
      button: true,
      enabled: go != null,
      label: forward ? l.study_nextWord : l.study_previousWord,
      child: GestureDetector(
        key: Key(forward ? 'next word' : 'previous word'),
        behavior: HitTestBehavior.opaque,
        onTap: go == null
            ? null
            : () => forward
                  ? swipe.currentState?.slideNext()
                  : swipe.currentState?.slidePrevious(),
        child: SizedBox(
          width: 28,
          height: 44,
          child: Icon(
            forward ? Icons.chevron_left : Icons.chevron_right,
            size: 22,
            color: go == null ? n.textAt(0.15) : n.textAt(0.6),
          ),
        ),
      ),
    );
  }

  /// ‹ root · the word as this aya writes it · what it means here › — the
  /// arrows at either end step a word. A word with no root carries the tag
  /// that says so where the root would be.
  Widget _wordRow(
    BuildContext context,
    Nocturne n,
    AppLocalizations l,
    RootReading? root,
  ) {
    final word = sheet.word;
    final meaning = word.glossIn(Localizations.localeOf(context));
    return Row(
      children: [
        _arrow(n, l, forward: true),
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            crossAxisAlignment: CrossAxisAlignment.center,
            spacing: 14,
            children: [
              if (root != null)
                Semantics(
                  button: true,
                  label: l.study_openRoot(root.translit),
                  child: GestureDetector(
                    key: const ValueKey('open-root'),
                    onTap: () => onRoot(root.letters),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          root.display,
                          textDirection: TextDirection.rtl,
                          style: TextStyle(
                            fontFamily: Nocturne.arabicFamily,
                            fontSize: 34,
                            height: 1.35,
                            letterSpacing: 34 * 0.14,
                            color: n.text,
                          ),
                        ),
                        Text(
                          root.translit,
                          style: TextStyle(fontSize: 11, color: n.textAt(0.6)),
                        ),
                      ],
                    ),
                  ),
                )
              else
                NocturneTag(l.study_wordHasNoRoot),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    word.text,
                    textDirection: TextDirection.rtl,
                    // Not glowing: the glow marks the word inside its aya.
                    style: TextStyle(
                      fontFamily: Nocturne.arabicFamily,
                      fontSize: 24,
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
              ),
              if (meaning != null)
                Flexible(
                  child: Text(
                    meaning,
                    key: const Key('meaning here'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 15, height: 1.35, color: n.text),
                  ),
                ),
            ],
          ),
        ),
        _arrow(n, l, forward: false),
      ],
    );
  }

  /// The root's senses, numbered, with the reader's verdict on them at the
  /// head of the list. A root with no sense written has nothing to judge.
  List<Widget> _senses(Nocturne n, AppLocalizations l, RootReading root) {
    final senses = root.coreSense
        ?.split('; ')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (senses == null || senses.isEmpty) return const [];
    return [
      const SizedBox(height: 14),
      Row(
        children: [
          NocturneKicker(l.study_senses),
          const Spacer(),
          JudgeSense(
            key: ValueKey('judge ${root.letters}'),
            root: root.letters,
            onJudge: onJudge,
          ),
        ],
      ),
      const SizedBox(height: 2),
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
    ];
  }

  /// How the corpus parses this occurrence of the word, with its attribution.
  Widget _form(Nocturne n, AppLocalizations l) {
    final irab = sheet.irab;
    if (irab.isEmpty) return const SizedBox.shrink();
    return Padding(
      key: const Key('form'),
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          NocturneKicker(l.study_form),
          const SizedBox(height: 6),
          for (final segment in irab)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
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
            style: TextStyle(fontSize: 10, height: 1.5, color: n.textAt(0.45)),
          ),
        ],
      ),
    );
  }

  Widget _moreRow(Nocturne n, AppLocalizations l) => GestureDetector(
    key: const Key('more row'),
    behavior: HitTestBehavior.opaque,
    onTap: onToggle,
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
    final lemma = sheet.lemmas
        .where((x) => x.key == sheet.word.lemmaKey)
        .firstOrNull;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NocturneKicker(l.study_acrossQuran),
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
                onPressed: () =>
                    onConstellation(ayahOfWord(sheet.word.id), root.letters),
                child: Text(l.study_constellation),
              ),
            ),
          ],
          if (sheet.ayas.isNotEmpty) ...[
            const SizedBox(height: 20),
            NocturneKicker(l.study_otherAyas),
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

  /// One other aya, as a line around the root's word in it, so the word it is
  /// listed for is never cut off the end.
  Widget _ayaRow(Nocturne n, RootAya aya) => InkWell(
    key: Key('other aya ${aya.ayahId}'),
    onTap: () => onAya(aya),
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
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
                LitAya.window(
                  aya.words,
                  glow: Glow.reading,
                  style: TextStyle(
                    fontFamily: Nocturne.arabicFamily,
                    fontSize: 18,
                    height: 1.6,
                    color: n.text,
                  ),
                ),
                if (translations && aya.translation != null)
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
}

/// Yes or no on the sense below, and then nothing.
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
    if (_answered) {
      return Text(
        l.root_senseJudgeThanks,
        style: TextStyle(fontSize: 10.5, color: n.textAt(0.45)),
      );
    }
    // Two small thumbs on the senses' own heading, and no question: what is
    // being judged is the list under them. A screen reader gets the naming
    // through the Semantics label. Each keeps a 32px target around a 14px
    // icon, so a small mark is not a small target.
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (good, icon, semantics) in [
          (true, Icons.thumb_up_outlined, l.root_senseJudgeGoodLabel),
          (false, Icons.thumb_down_outlined, l.root_senseJudgeBadLabel),
        ])
          Semantics(
            button: true,
            label: semantics,
            child: InkWell(
              key: Key('judge sense ${good ? 'good' : 'bad'}'),
              customBorder: const CircleBorder(),
              onTap: () => _say(good),
              child: SizedBox.square(
                dimension: 32,
                child: Icon(icon, size: 14, color: n.textAt(0.55)),
              ),
            ),
          ),
      ],
    );
  }
}

/// The sheet's handle, which remembers whether the sheet was expanded when a
/// drag began.
///
/// Past the drag slop, the direction alone says what the reader meant. Up
/// brings a folded sheet back and then opens its lower half, so one long drag
/// up opens it whole. Down from an expanded sheet stops at its usual height,
/// and only the next drag down folds it away: the reader who meant to put
/// away the counts did not mean to put away the root.
class _Handle extends StatefulWidget {
  const _Handle({
    super.key,
    required this.expanded,
    required this.onTap,
    required this.onDrag,
    required this.child,
  });

  final bool expanded;
  final VoidCallback? onTap;
  final void Function(double dy, {required bool fromExpanded})? onDrag;
  final Widget child;

  @override
  State<_Handle> createState() => _HandleState();
}

class _HandleState extends State<_Handle> {
  var _fromExpanded = false;

  @override
  Widget build(BuildContext context) {
    final drag = widget.onDrag;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onVerticalDragStart: drag == null
          ? null
          : (_) => _fromExpanded = widget.expanded,
      onVerticalDragUpdate: drag == null
          ? null
          : (d) => drag(d.primaryDelta ?? 0, fromExpanded: _fromExpanded),
      child: widget.child,
    );
  }
}
