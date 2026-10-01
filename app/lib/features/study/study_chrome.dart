import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../app.dart';
import '../../data/db.dart';
import '../../data/sets.dart';
import '../../nav.dart';
import '../../shell/wird_shell.dart';
import '../../theme/nocturne.dart';
import '../../widgets/nocturne_button.dart';
import '../../widgets/nocturne_tag.dart';
import 'root_sheet.dart' show JudgeSense;
// Shown, not imported whole, for two reasons that both bite. root_sections.dart
// declares a DashedRule of its own — painted with ThreadPainter rather than the
// _DashPainter below — so an unqualified import makes every `DashedRule` in this
// file an ambiguous_import, on lines this change does not touch. And it
// `export`s family.dart, which reaches the deep dive's constellation, so an
// unqualified import would drag that into the study feature.
import '../root/root_sections.dart' show CoreSense;

/// Where the reader is — and, since this screen carries the shell's row
/// itself, the way out of it as well.
///
/// It is one row: the burger, the set's title with the sūra's own name beside
/// it, the fold, and the act the reading is for. Under it the aya markers are
/// the bar's rule, three pixels of the reader's place in the set rather than a
/// line. Unfolding adds the revelation kicker and the sentence spelling out
/// which ayas are marked, and nothing else — the title is already in the row,
/// and a second, larger copy of it was the screen saying "where am I" twice.
///
/// The burger used to sit in a row of the shell's above all of this, which on
/// a 402x874 phone meant three lines of chrome before the first aya. Now there
/// is one, and [WirdShell.bar] is how the shell is told to draw none.
///
/// Which fold state it is in is the reader's, and is held in [Prefs] rather
/// than here, so it survives the screen being rebuilt, left, and come back to.
class StudyHeader extends StatelessWidget {
  const StudyHeader({
    super.key,
    required this.set,
    required this.order,
    required this.visiting,
    required this.open,
    required this.onToggle,
    required this.onBackToTheWalk,
  });

  final StudySet set;
  final ReadingOrder order;

  /// The reader asked for this aya rather than being handed it by the walk.
  /// Nothing else on the screen says so, so it survives the fold — ADR-0003.
  final bool visiting;

  final bool open;
  final VoidCallback onToggle;
  final VoidCallback onBackToTheWalk;

  @override
  Widget build(BuildContext context) {
    final n = Nocturne.of(context);
    final l10n = AppLocalizations.of(context)!;
    final first = set.ayas.first;
    // The place is the sūra's own `revelation_place` out of the corpus —
    // makkah or madinah — so it is capitalised and handed on rather than
    // translated: it is a place name, and the only other spelling of it would
    // be a second table nobody maintains.
    final place = _capitalise(first.revelationPlace);
    final where = order == ReadingOrder.nuzul
        ? l10n.study_revelationKicker(first.revelationOrder, place)
        : l10n.study_surahKicker(first.surahId, place);
    return Padding(
      padding: EdgeInsets.fromLTRB(n.space('3'), n.space('2'), n.space('6'), 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              // The shell draws no row above this one, so the way out is the
              // first thing in it.
              const ShellBurger(),
              Expanded(
                child: GestureDetector(
                  key: const Key('toggle header'),
                  behavior: HitTestBehavior.opaque,
                  onTap: onToggle,
                  child: Row(
                    children: [
                      Flexible(child: _oneLine(context, n)),
                      SizedBox(width: n.space('2')),
                      Icon(
                        open ? Icons.expand_less : Icons.expand_more,
                        size: 16,
                        color: n.textAt(0.45),
                      ),
                    ],
                  ),
                ),
              ),
              if (visiting)
                NocturneButton(
                  variant: NocturneButtonVariant.ghost,
                  onPressed: onBackToTheWalk,
                  child: Text(
                    l10n.study_backToTheWalk,
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              // The preferences the tune icon used to open have a screen of
              // their own now, and this is what belongs beside the set
              // instead: the act the reading is for.
              NocturneButton(
                key: const Key('pray the set'),
                variant: NocturneButtonVariant.ghost,
                onPressed: () => prayTheSet(context, set),
                child: Text(
                  l10n.study_prayThisSet,
                  style: const TextStyle(fontSize: 11),
                ),
              ),
            ],
          ),
          if (open)
            Padding(
              padding: EdgeInsets.only(top: n.space('1')),
              // The row above already says the reader is visiting, so this
              // says only where they are.
              child: _kicker(n, where),
            ),
          _progress(l10n, n),
        ],
      ),
    );
  }

  Widget _kicker(Nocturne n, String text) => Text(
    text.toUpperCase(),
    style: TextStyle(
      fontSize: 10,
      height: 1.2,
      letterSpacing: 0.11 * 10,
      color: n.accent,
    ),
  );

  /// The folded header. The title carries the whole answer to "where am I";
  /// the sūra's own name follows it in Arabic. They are two spans rather than
  /// one string because a Latin title and an Arabic name in one [Text] are
  /// reordered by the bidi algorithm.
  Widget _oneLine(BuildContext context, Nocturne n) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (visiting) ...[
        _kicker(n, AppLocalizations.of(context)!.study_visiting),
        SizedBox(width: n.space('2')),
      ],
      Flexible(
        child: Text(
          set.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: Nocturne.headingFamily,
            fontVariations: Nocturne.headingVariations,
            fontSize: 14,
            height: 1.2,
            color: n.text,
          ),
        ),
      ),
      // The sūra's own name goes when the reader is visiting: the aya number
      // is the answer to "where am I" then, and it competes for the line with
      // the marker and the way back to the walk.
      if (!visiting) ...[
        SizedBox(width: n.space('2')),
        Text(
          set.ayas.first.surahNameAr,
          textDirection: TextDirection.rtl,
          style: TextStyle(
            fontFamily: Nocturne.arabicFamily,
            fontSize: 13,
            color: n.textAt(0.5),
          ),
        ),
      ],
    ],
  );

  /// One segment per aya, lit when it is understood.
  ///
  /// It is the rule under the bar rather than a row of its own: three pixels
  /// is what the reader's place in the set costs, and every other screen pays
  /// the same height for a line that says nothing. Without it a folded header
  /// could not say how far through the set the reader is, and the only other
  /// place that answers is screen 1d. The sentence spelling out which ayas is
  /// what unfolding adds.
  Widget _progress(AppLocalizations l10n, Nocturne n) => Padding(
    padding: EdgeInsets.only(top: n.space(open ? '6' : '2')),
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
        if (open) ...[
          SizedBox(height: n.space('2')),
          Text(
            progressCaption(l10n, set.ayas),
            style: TextStyle(fontSize: 10.5, color: n.textAt(0.42)),
          ),
        ],
      ],
    ),
  );
}

/// The root under the word the reader is looking at, below the set.
///
/// Folded it is the root's letters, its transliteration and how often it
/// occurs — enough to say which root is open, on 12% of the screen rather
/// than 27%. The gloss, the kin and the way to the constellation are what
/// unfolding is for, and the word's own gloss is drawn on the word itself
/// either way. "Mark set understood" is reachable in both, because it is the
/// act that moves the reader through the Qur'an.
class RootPanel extends StatelessWidget {
  const RootPanel({
    super.key,
    required this.root,
    required this.word,
    required this.open,
    required this.onToggle,
    required this.onVisit,
    required this.onKin,
    required this.allUnderstood,
    required this.onMark,
    required this.onJudge,
    required this.onPrevious,
    required this.onNext,
  });

  final RootDetail? root;

  /// The word whose root this is, or null before any word has been opened.
  final StudyWord? word;

  final bool open;
  final VoidCallback onToggle;

  /// Pushes a screen that answers with an aya — the root, the constellation.
  final void Function(String route, Object arguments) onVisit;

  /// Opens the aya a kin is first met in.
  final void Function(int ayahId) onKin;

  /// Every aya in the set is understood, so the one thing left to do is walk
  /// on rather than mark it again.
  final bool allUnderstood;

  final VoidCallback onMark;

  /// A reader's verdict on the sense drawn for this root.
  final void Function(String root, bool good) onJudge;

  /// The word before and after this one in the passage, or null at its two
  /// ends, which draws that arrow dark. A word carrying no root is not an end:
  /// the walk goes through particles, it does not stop at them.
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final n = Nocturne.of(context);
    final l10n = AppLocalizations.of(context)!;
    final root = this.root;
    final letters = word?.root;
    return Container(
      key: const Key('root panel'),
      padding: EdgeInsets.fromLTRB(
        n.space('6'),
        n.space('4'),
        n.space('6'),
        n.space(open ? '8' : '4'),
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
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The body scrolls, the action does not. The screen caps this panel
          // at half the window, and a cap over a scroll view is a clip: put
          // the whole panel inside one and `Mark set understood` — the only
          // way through the Qur'an — goes off the bottom with no scrollbar to
          // hint at it. So only what is above it is scrollable, and the button
          // keeps its place at the foot of the panel at every window size and
          // every text scale.
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!open)
                    // Folded, the one line is the handle: it unfolds rather
                    // than opening the root screen. The word's own line where
                    // the word has no root, or a folded panel walked onto a
                    // particle is a strip the reader cannot reopen.
                    GestureDetector(
                      key: const Key('toggle root panel'),
                      behavior: HitTestBehavior.opaque,
                      onTap: onToggle,
                      child: _handle(context, n, trailing: Icons.expand_less),
                    )
                  else ...[
                    Row(
                      children: [
                        // The design reaches 3a by tapping a word in 1a, but the
                        // word's gestures are spoken for — a tap speaks it, a long
                        // press swaps this panel — so the root the panel names opens
                        // the root screen.
                        Expanded(
                          child: GestureDetector(
                            key: const ValueKey('open-root'),
                            behavior: HitTestBehavior.opaque,
                            onTap: letters == null
                                ? null
                                : () => onVisit(Routes.root, letters),
                            child: _handle(context, n),
                          ),
                        ),
                        SizedBox(width: n.space('2')),
                        NocturneButton(
                          key: const Key('toggle root panel'),
                          variant: NocturneButtonVariant.icon,
                          onPressed: onToggle,
                          child: const Icon(Icons.expand_more, size: 16),
                        ),
                      ],
                    ),
                    if (word != null)
                      Padding(
                        padding: EdgeInsets.symmetric(vertical: n.space('3')),
                        child: const DashedRule(),
                      ),
                    // A particle or a proper noun. Said here rather than
                    // going blank; study_noRootInSet is about the whole set
                    // and would be a lie on a set full of roots.
                    if (root == null)
                      Text(
                        l10n.study_wordHasNoRoot,
                        style: TextStyle(fontSize: 12.5, color: n.textAt(0.6)),
                      )
                    else ...[
                      // The root the panel is holding already carries its sense: `root`
                      // is a RootReading, the same object the root screen, the spine and
                      // the deep dive all hand to CoreSense. This was the only one of the
                      // four that did not ask, and printed the word's gloss alone.
                      //
                      // Unguarded, like the other three. Where a root ships no sense
                      // CoreSense says so in words, because a root whose sense Wird
                      // declined to claim must not read as a section someone forgot: the
                      // machine chose the absence and the reader is told it chose.
                      //
                      // The dash above supplies the gap over it; the gap under it is
                      // here, or the sentence butts into the IN THIS AYA kicker.
                      Padding(
                        padding: EdgeInsets.only(bottom: n.space('4')),
                        child: CoreSense(reading: root),
                      ),
                      // Whether the sense above is right, asked of the one person
                      // who can tell. The sense is written from lexicography and
                      // checked against the Qurʼan for contradiction, and neither
                      // can see whether it is COMPLETE — ر ح م shipped without
                      // "womb" past a gate scoring six terms.
                      //
                      // Only where there is a sense to judge: CoreSense draws a
                      // refusal notice when a root has none, and asking a reader to
                      // rate a refusal asks them nothing.
                      if (root.coreSense != null)
                        Padding(
                          padding: EdgeInsets.only(bottom: n.space('4')),
                          child: JudgeSense(
                            root: root.letters,
                            onJudge: onJudge,
                          ),
                        ),
                      // "Open constellation" used to sit beside "Mark set understood"
                      // at equal weight. One of the two moves the reader through the
                      // Qur'an and the other is an occasional detour, so the detour is
                      // demoted into the panel it belongs to and the bottom of the
                      // screen carries one action.
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              l10n.inThisAya,
                              style: TextStyle(
                                fontSize: 10,
                                letterSpacing: 0.11 * 10,
                                color: n.accent,
                              ),
                            ),
                          ),
                          if (letters != null)
                            NocturneButton(
                              variant: NocturneButtonVariant.ghost,
                              onPressed: () => onVisit(Routes.deepDive, (
                                ayahId: word!.id ~/ 1000,
                                letters: letters,
                              )),
                              child: Text(
                                l10n.study_constellation,
                                style: const TextStyle(fontSize: 11),
                              ),
                            ),
                        ],
                      ),
                      SizedBox(height: n.space('1')),
                      Text(
                        word?.glossIn(Localizations.localeOf(context)) ?? '—',
                        style: TextStyle(
                          fontSize: 13.5,
                          height: 1.5,
                          color: n.text,
                        ),
                      ),
                      SizedBox(height: n.space('3')),
                      Wrap(
                        spacing: n.space('2'),
                        runSpacing: n.space('2'),
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          // The tag sets everything about its label but the family, so
                          // the Arabic face reaches it through the default style.
                          for (final kin in root.kin)
                            GestureDetector(
                              // Keyed by the form as well as the aya: two derivatives
                              // are first met in the same aya often enough, and the two
                              // tags cannot carry one key.
                              key: ValueKey('kin-${kin.text}-${kin.ayahId}'),
                              behavior: HitTestBehavior.opaque,
                              onTap: () => onKin(kin.ayahId),
                              child: DefaultTextStyle.merge(
                                style: const TextStyle(
                                  fontFamily: Nocturne.arabicFamily,
                                ),
                                child: NocturneTag(
                                  kin.text,
                                  variant: NocturneTagVariant.neutral,
                                ),
                              ),
                            ),
                          // The corpus attribution stood here and is gone:
                          // ADR 0013. About > Sources carries the name, the
                          // notice and the link the licence asks for, and
                          // IrabSection says it again on 3a, 2b and 1c.
                        ],
                      ),
                      SizedBox(height: n.space('2')),
                      Text(
                        l10n.study_kinOpensItsAya,
                        style: TextStyle(fontSize: 10.5, color: n.textAt(0.45)),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
          SizedBox(height: n.space('3')),
          // The arrows flank the act rather than taking a band of their own.
          // A band cost the panel 48px of scrolling body, which put the kin
          // out of sight on the phone the design is drawn for; here they cost
          // nothing, and they are pinned, so the walk never scrolls away.
          Row(
            spacing: n.space('3'),
            children: [
              NocturneStep(
                key: const Key('previous word'),
                label: l10n.study_previousWord,
                icon: Icons.chevron_left,
                onPressed: onPrevious,
              ),
              Expanded(
                child: NocturneButton(
                  block: true,
                  variant: NocturneButtonVariant.primary,
                  onPressed: onMark,
                  child: Text(
                    allUnderstood ? l10n.nextSet : l10n.markSetUnderstood,
                  ),
                ),
              ),
              NocturneStep(
                key: const Key('next word'),
                label: l10n.study_nextWord,
                icon: Icons.chevron_right,
                onPressed: onNext,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// The panel's top line: the root where there is one, else the word the
  /// arrows walked onto, else the sentence that says the set has no root at
  /// all. It is the fold handle too, so it is never nothing.
  Widget _handle(BuildContext context, Nocturne n, {IconData? trailing}) {
    final root = this.root;
    final word = this.word;
    if (root != null) return _rootLine(n, root, trailing: trailing);
    if (word != null) return _wordLine(context, n, word, trailing: trailing);
    return Text(
      AppLocalizations.of(context)!.study_noRootInSet,
      style: TextStyle(fontSize: 13, color: n.textAt(0.62)),
    );
  }

  /// A word with no root, drawn where the root line goes: the word itself and
  /// its meaning, which is all there is to say about it.
  Widget _wordLine(
    BuildContext context,
    Nocturne n,
    StudyWord word, {
    IconData? trailing,
  }) => Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Text(
        word.text,
        textDirection: TextDirection.rtl,
        style: TextStyle(
          fontFamily: Nocturne.arabicFamily,
          fontSize: 26,
          color: n.text,
        ),
      ),
      SizedBox(width: n.space('3')),
      Expanded(
        child: Text(
          word.glossIn(Localizations.localeOf(context)) ?? '',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12.5, color: n.textAt(0.6)),
        ),
      ),
      if (trailing != null) ...[
        SizedBox(width: n.space('2')),
        Icon(trailing, size: 16, color: n.textAt(0.45)),
      ],
    ],
  );

  Widget _rootLine(Nocturne n, RootDetail root, {IconData? trailing}) => Row(
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
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11,
            letterSpacing: 0.06 * 11,
            color: n.textAt(0.55),
          ),
        ),
      ),
      NocturneTag('${root.occurrences}×', variant: NocturneTagVariant.outline),
      if (trailing != null) ...[
        SizedBox(width: n.space('2')),
        Icon(trailing, size: 16, color: n.textAt(0.45)),
      ],
    ],
  );
}

/// The design's separators are dashes, not rules: 2 px on, 5 px off.
class DashedRule extends StatelessWidget {
  const DashedRule({super.key});

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    height: 1,
    child: CustomPaint(
      painter: _DashPainter(Nocturne.of(context).textAt(0.22)),
    ),
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

String _capitalise(String word) =>
    word.isEmpty ? word : word[0].toUpperCase() + word.substring(1);

String progressCaption(AppLocalizations l10n, List<StudyAya> ayas) {
  final done = [
    for (final a in ayas)
      if (a.understood) a.number,
  ];
  final open = [
    for (final a in ayas)
      if (!a.understood) a.number,
  ];
  if (done.isEmpty) return l10n.study_noAyaUnderstoodYet;
  if (open.isEmpty) return l10n.study_everyAyaUnderstood;
  return l10n.study_progressSplit(_numbers(l10n, done), _numbers(l10n, open));
}

String _numbers(AppLocalizations l10n, List<int> numbers) => numbers.length == 1
    ? '${numbers.first}'
    : l10n.study_numbersAnd(
        numbers.sublist(0, numbers.length - 1).join(', '),
        numbers.last,
      );
