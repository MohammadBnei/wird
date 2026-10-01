import 'package:flutter/material.dart';

import '../../data/root_repo.dart';
import '../../data/sets.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/glow.dart';
import '../../theme/nocturne.dart';
import '../../widgets/lit_aya.dart';
import '../../widgets/nocturne_kicker.dart';
import '../../widgets/nocturne_tag.dart';
import '../root/root_sections.dart' show irabWork;
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
  const RootSheet({
    super.key,
    required this.sheet,
    required this.expanded,
    required this.previous,
    required this.next,
    required this.swipe,
    required this.onPrevious,
    required this.onNext,
    required this.onToggle,
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

  /// The slide the arrows drive, so a step by arrow moves like a swipe.
  final GlobalKey<WordSwipeState> swipe;

  /// Null where there is no word to step to.
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  final VoidCallback onToggle;
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
  Widget build(BuildContext context) {
    final n = Nocturne.of(context);
    final l = AppLocalizations.of(context)!;
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
      clipBehavior: Clip.hardEdge,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _topBar(n, l),
          Expanded(
            child: SingleChildScrollView(
              controller: scroll,
              child: WordSwipe(
                key: swipe,
                wordId: sheet.word.id,
                onNext: onNext,
                onPrevious: onPrevious,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 6, 18, 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _wordRow(context, n, l, root),
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
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The handle and the hint row, one bar: a tap anywhere on it opens or
  /// closes the lower half, except on its two ends, which step a word.
  Widget _topBar(Nocturne n, AppLocalizations l) {
    final hint = TextStyle(fontSize: 11, color: n.textAt(0.5));
    final arabic = TextStyle(
      fontFamily: Nocturne.arabicFamily,
      fontSize: 15,
      color: n.textAt(0.5),
    );
    Widget side(StudyWord? word, bool forward) {
      final go = forward ? onNext : onPrevious;
      return Expanded(
        child: Semantics(
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
            child: Row(
              mainAxisAlignment: forward
                  ? MainAxisAlignment.start
                  : MainAxisAlignment.end,
              children: [
                if (forward) Text('‹ ', style: hint),
                if (word != null)
                  Flexible(
                    child: Text(
                      word.text,
                      textDirection: TextDirection.rtl,
                      overflow: TextOverflow.ellipsis,
                      style: arabic,
                    ),
                  ),
                if (!forward) Text(' ›', style: hint),
              ],
            ),
          ),
        ),
      );
    }

    return Semantics(
      button: true,
      label: expanded ? l.study_collapseSheet : l.study_expandSheet,
      child: GestureDetector(
        key: const Key('sheet handle'),
        behavior: HitTestBehavior.opaque,
        onTap: onToggle,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
          child: Column(
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: n.color('neutral-700'),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  side(next, true),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(l.study_swipe, style: hint),
                  ),
                  side(previous, false),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The root, the word as this aya writes it, and what it means here — or,
  /// for a word with no root, the tag that says so where the root would be.
  Widget _wordRow(
    BuildContext context,
    Nocturne n,
    AppLocalizations l,
    RootReading? root,
  ) {
    final word = sheet.word;
    final meaning = word.glossIn(Localizations.localeOf(context));
    return Row(
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
              style: TextStyle(
                fontFamily: Nocturne.arabicFamily,
                fontSize: 24,
                height: 1.4,
              ).merge(glowing(n, Glow.reading)),
            ),
            if (word.translit != null)
              Text(
                word.translit!,
                style: TextStyle(fontSize: 11, color: n.textAt(0.6)),
              ),
          ],
        ),
        if (meaning != null)
          Expanded(
            child: Text(
              meaning,
              key: const Key('meaning here'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 15, height: 1.35, color: n.text),
            ),
          ),
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
                onPressed: () => onConstellation(root.letters),
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
