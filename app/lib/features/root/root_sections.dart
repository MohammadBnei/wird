import 'package:flutter/material.dart';

import '../../data/root_repo.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/nocturne.dart';
import '../../widgets/nocturne_button.dart';
import '../../widgets/nocturne_rule.dart';
import 'family.dart';

// A family's own widgets live in family.dart. They are exported here so a
// screen reading a root asks one file for the sections and the spine both.
export 'family.dart';

/// Which commentaries the tafsir section will quote once the fetch exists.
/// Naming them is not a claim about what they say.
///
/// Not localised, and not localisable: these are three men's names, and a
/// translated authority is a different authority.
const tafsirSources = ['Al-Ṭabarī', 'Ibn Kathīr', 'Al-Rāzī'];


/// An `h6`: 13px, uppercase, widely tracked.
class SectionHeading extends StatelessWidget {
  const SectionHeading(this.label, {super.key, this.trailing});

  final String label;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final n = Nocturne.of(context);
    final heading = Text(
      label.toUpperCase(),
      style: TextStyle(
        fontFamily: Nocturne.headingFamily,
        fontVariations: Nocturne.headingVariations,
        fontSize: 13,
        height: 1.12,
        letterSpacing: 0.08 * 13,
        color: n.textAt(0.6),
      ),
    );
    if (trailing == null) return heading;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        heading,
        const Spacer(),
        Text(
          trailing!,
          style: TextStyle(fontSize: 10.5, color: n.textAt(0.55)),
        ),
      ],
    );
  }
}

/// The dashed hairline the design draws inside the detail card.
class DashedRule extends StatelessWidget {
  const DashedRule({super.key});

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    height: 1,
    child: CustomPaint(
      painter: ThreadPainter(Nocturne.of(context).textAt(0.22), across: true),
    ),
  );
}

/// A section whose text is fetched, on a build where the fetch does not exist.
/// It names the works it will quote and says plainly that it is quoting none
/// of them, rather than drawing an empty box or borrowing someone else's words.
class PendingSection extends StatelessWidget {
  const PendingSection({
    super.key,
    required this.heading,
    required this.explanation,
    this.sources = const [],
  });

  final String heading;
  final List<String> sources;
  final String explanation;

  @override
  Widget build(BuildContext context) {
    final n = Nocturne.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeading(heading),
        SizedBox(height: n.space('3')),
        for (final source in sources)
          Padding(
            padding: EdgeInsets.only(bottom: n.space('1')),
            child: Text(
              source,
              style: TextStyle(fontSize: 11, color: n.accent),
            ),
          ),
        SizedBox(height: n.space('1')),
        Text(
          explanation,
          style: TextStyle(fontSize: 12.5, height: 1.55, color: n.textAt(0.6)),
        ),
      ],
    );
  }
}

/// Core sense: what the root means, and whose reading that is.
///
/// The sense is Wird's own, and it arrives from the server rather than in the
/// binary (ADR 0010). A reader cannot be left to guess whether it is that or a
/// quotation from a lexicon, because a version of this feature was already
/// reverted for shipping invented prose under two lexicographers' names. So
/// the line saying whose reading it is sits under the sentence, and what the
/// sense rests on — including, for a served draft, the fact that no person has
/// read it — is one tap further.
///
/// The old wording here said the sense was "written from the root's own words
/// in this corpus and kept only where their glosses bore it out". That was the
/// corpus-derivation standard, and it is not the standard the served drafts
/// were written to; it is not repeated.
class CoreSense extends StatelessWidget {
  const CoreSense({
    super.key,
    required this.reading,
    this.senseSize = 13.5,
    this.judge,
  });

  final RootReading reading;

  /// The reader's thumbs on the sense, drawn at the end of its heading. Null
  /// where the screen has no database to queue a verdict through.
  final Widget? judge;

  /// The deep dive reads the same sentence a point larger than the two root
  /// screens do.
  final double senseSize;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final sense = reading.coreSense;
    if (sense == null) {
      // Two facts, two sentences. "Nobody has written a sense for this root"
      // and "this phone has fetched no senses at all" are different, and one
      // string for both told a reader who has never had a signal 1,642 times
      // that nobody had written anything — which is false, and blames the
      // absence on the work rather than on the download. ADR 0010 names this.
      return PendingSection(
        heading: l.root_coreSense,
        explanation: reading.sensesFetched
            ? l.root_senseRefused
            : l.root_senseNotFetched,
      );
    }
    final n = Nocturne.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (judge == null)
          SectionHeading(l.root_coreSense)
        else
          Row(
            children: [
              Expanded(child: SectionHeading(l.root_coreSense)),
              judge!,
            ],
          ),
        SizedBox(height: n.space('2')),
        Text(
          sense,
          style: TextStyle(fontSize: senseSize, height: 1.5, color: n.text),
        ),
        SizedBox(height: n.space('2')),
        _whose(context, n),
      ],
    );
  }

  /// Who is speaking, in the one shape that cannot be misread.
  ///
  /// The source is a column, and it held "Wird" for every one of the 523
  /// senses that ship. Interpolated, that drew "Wird's own reading" — which
  /// has the shape of a cited authority, and Wird is itself an Arabic word,
  /// so a reader who has not met the app's name reads it as the scholar this
  /// round exists to distinguish the sense from. Naming a real authority the
  /// same way as the app is the defect, not the wording of either.
  ///
  /// So the app says it is the app. A sense that ever does come from a named
  /// work names that work, and the two no longer look alike.
  String _whoseWords(AppLocalizations l, String? source, int words) {
    final borne = words == 0 ? '' : l.root_senseBorne(words);
    // 'Wird' is the value the column holds, not a word on the screen: it is
    // compared, never drawn, so it is not localised.
    return source == null || source == 'Wird'
        ? l.root_senseByApp(borne)
        : l.root_senseBySource(source, borne);
  }

  /// Always a door, and that is the fix rather than the polish.
  ///
  /// This drew a flat [Text] when the sense carried no evidence words, and
  /// [showSenseEvidence] has exactly one caller — the [InkWell] below. Since
  /// [SenseEvidence] is the only place [RootReading.senseBasis] is drawn
  /// anywhere in the app, and a served sense carries no evidence words at all,
  /// the sentence saying the sense is an unread machine draft was reachable on
  /// no root in the corpus. ADR 0010's one named risk is that prose not
  /// reaching the reader, so the tap is the mitigation.
  /// The one case where it is NOT a door: a sense carrying neither a basis nor
  /// evidence words has nothing behind the tap, and an underlined line opening
  /// onto a heading over blank space is the same defect this fixed, one field
  /// along. The wire makes `basis` optional, so this is reachable rather than
  /// theoretical.
  Widget _whose(BuildContext context, Nocturne n) {
    final l = AppLocalizations.of(context)!;
    final source = reading.senseSource;
    final words = reading.senseEvidence.length;
    final basis = reading.senseBasis?.trim() ?? '';
    if (basis.isEmpty && words == 0) {
      return Text(
        '${_whoseWords(l, source, 0)}.',
        style: TextStyle(fontSize: 12, height: 1.5, color: n.textAt(0.62)),
      );
    }
    // Underlined rather than given a chevron. The line wraps at the width of
    // the deep dive's centre pane, and a trailing icon lands alone on the
    // second row; an underline follows the words however they break.
    return InkWell(
      onTap: () => showSenseEvidence(context, reading),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Text(
          _whoseWords(l, source, words),
          style: TextStyle(
            fontSize: 12,
            height: 1.5,
            color: n.accent,
            decoration: TextDecoration.underline,
            decorationColor: n.accent.withValues(alpha: 0.5),
          ),
        ),
      ),
    );
  }
}

/// The words behind a sense, raised over the screen that claims it. They are
/// not printed in place: eleven words and their glosses under every root
/// would bury the one sentence they exist to support.
Future<void> showSenseEvidence(BuildContext context, RootReading reading) =>
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Nocturne.of(context).surface,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.82,
          ),
          child: SenseEvidence(reading: reading),
        ),
      ),
    );

/// What makes the sense checkable rather than trusted: the root's own words,
/// each with the gloss the corpus carries for it and the shape it is in.
class SenseEvidence extends StatelessWidget {
  const SenseEvidence({super.key, required this.reading});

  final RootReading reading;

  @override
  Widget build(BuildContext context) {
    final n = Nocturne.of(context);
    final l = AppLocalizations.of(context)!;
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          spacing: 10,
          children: [
            Text(
              reading.display,
              textDirection: TextDirection.rtl,
              style: TextStyle(
                fontFamily: Nocturne.arabicFamily,
                fontSize: 24,
                letterSpacing: 0.14 * 24,
                color: n.color('accent-200'),
              ),
            ),
            Expanded(
              child: Text(
                reading.translit,
                style: TextStyle(fontSize: 11, color: n.textAt(0.6)),
              ),
            ),
          ],
        ),
        SizedBox(height: n.space('3')),
        Text(
          reading.coreSense ?? '',
          style: TextStyle(fontSize: 14, height: 1.5, color: n.text),
        ),
        const NocturneRule(),
        // Unconditional, unlike the words below, and deliberately so. This is
        // the sentence the tap exists to reach; a served pack always carries it
        // — one Go const beside the handler, written into every row — and an
        // `isNotEmpty` guard here is the exact shape of the defect this round
        // fixed: a condition on served content that quietly closes the door.
        // If this ever draws blank, the server stopped sending a basis, which
        // is worth seeing rather than hiding.
        SectionHeading(l.root_whoseReading),
        SizedBox(height: n.space('2')),
        Text(
          reading.senseBasis ?? '',
          style: TextStyle(fontSize: 12.5, height: 1.55, color: n.textAt(0.7)),
        ),
        // Dropped whole when there are none, rather than drawn as a heading
        // over nothing and a count of zero. Every served sense is in that
        // state — the drafts were not read off a word list — and the sheet's
        // other half, the basis above, is the reason it opens at all.
        if (reading.senseEvidence.isNotEmpty) ...[
          const NocturneRule(),
          SectionHeading(
            l.root_wordsReadFrom,
            trailing: l.root_wordCount(reading.senseEvidence.length),
          ),
          SizedBox(height: n.space('3')),
          // The stored order is the bar's own, grouped by morphological shape,
          // so it is kept rather than sorted: the grouping is the argument.
          for (final word in reading.senseEvidence) _word(n, l, word),
        ],
      ],
    );
  }

  Widget _word(Nocturne n, AppLocalizations l, String word) {
    // ponytail: the word is matched back to its derivative by a linear scan
    // over the family. Index it if a root ever carries evidence past a dozen
    // words, which the shipped set does not.
    final kin = reading.spelled(word);
    final gloss = kin?.gloss;
    final form = kin?.form;
    return Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        spacing: 12,
        children: [
          SizedBox(
            width: 112,
            child: Text(
              word,
              textDirection: TextDirection.rtl,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontFamily: Nocturne.arabicFamily,
                fontSize: 19,
                height: 1.5,
                color: n.text,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (gloss != null)
                  Text(
                    gloss,
                    style: TextStyle(fontSize: 12.5, color: n.textAt(0.82)),
                  ),
                if (form != null)
                  Text(
                    l.root_formTag(form),
                    style: TextStyle(
                      fontSize: 10,
                      height: 1.6,
                      letterSpacing: 0.1 * 10,
                      color: n.accent,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// ponytail: a [Builder] rather than a `BuildContext` parameter. The heading
/// and the explanation are read strings now, and this is a bare function two
/// screens call — the wrapper is one line here instead of a signature change
/// at every call site.
Widget tafsirSection(String? ref) => Builder(
  builder: (context) {
    final l = AppLocalizations.of(context)!;
    return PendingSection(
      heading: ref == null ? l.root_tafsir : l.root_tafsirAt(ref),
      sources: tafsirSources,
      explanation: l.root_tafsirPending,
    );
  },
);

/// The parsing of one word, segment by segment, out of the bundle.
///
/// It names the occurrence it is showing, and that is not decoration. Case and
/// mood are assigned by the syntax of the verse — the shipped corpus carries
/// 12,629 genitives, 10,331 accusatives and 8,954 nominatives of the same
/// spellings — so a parsing drawn under a root with no aya beside it silently
/// presents one arbitrary occurrence's role as the form's own.
///
/// The provenance is drawn here and not by the screen around it: the tags and
/// features are Dukes's annotation under the GPL and the role names are written
/// for Wird, and a notice that lives on one of the two bodies that mount this
/// section is a notice that does not reach the other reader. data/SOURCES.md
/// records attribution that is in the data and not on the screen as a release
/// blocker.
///
/// [word] is drawn in the Arabic face rather than put in the heading: the
/// heading face is Inter, which has no Arabic and would print the word as
/// boxes. No segment's own spelling is drawn at all — the morphology file writes
/// those in Buckwalter, and the only Arabic the corpus has for a segment is the
/// whole word above it.
class IrabSection extends StatelessWidget {
  const IrabSection({
    super.key,
    required this.segments,
    required this.word,
    required this.where,
  });

  final List<IrabSegment> segments;

  /// The word as the aya spells it.
  final String word;

  /// The occurrence being parsed, the way a reference is written.
  final String where;

  @override
  Widget build(BuildContext context) {
    final n = Nocturne.of(context);
    final l = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeading(l.root_irab, trailing: l.root_irabAsReadAt(where)),
        SizedBox(height: n.space('3')),
        Text(
          word,
          textDirection: TextDirection.rtl,
          style: TextStyle(
            fontFamily: Nocturne.arabicFamily,
            fontSize: 21,
            height: 1.6,
            color: n.color('accent-200'),
          ),
        ),
        SizedBox(height: n.space('2')),
        // Unreachable while the ETL's own gate holds — it refuses a corpus with
        // a word whose segments are not all parsed — and said rather than drawn
        // as a gap, because an absent section reads as an oversight.
        if (segments.isEmpty)
          Text(
            l.root_noParsing,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.55,
              color: n.textAt(0.6),
            ),
          ),
        for (final segment in segments) _segment(n, segment),
        SizedBox(height: n.space('2')),
        Text(
          l.root_irabProvenance(irabWork),
          style: TextStyle(fontSize: 10.5, height: 1.5, color: n.textAt(0.45)),
        ),
      ],
    );
  }

  Widget _segment(Nocturne n, IrabSegment segment) => Padding(
    padding: const EdgeInsets.only(bottom: 9),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          segment.role,
          style: TextStyle(fontSize: 12.5, height: 1.45, color: n.textAt(0.86)),
        ),
        if (segment.features.isNotEmpty)
          Text(
            segment.features.join(' · '),
            style: TextStyle(fontSize: 10.5, height: 1.5, color: n.accent),
          ),
      ],
    ),
  );
}

/// Screen 2b's body: the same root with the dial taken away. A root with more
/// derivatives than the ring can hold is read here instead.
class RootSpineView extends StatefulWidget {
  const RootSpineView({super.key, required this.reading, this.judge});

  final RootReading reading;

  /// Handed to [CoreSense.judge].
  final Widget? judge;

  @override
  State<RootSpineView> createState() => _RootSpineViewState();
}

class _RootSpineViewState extends State<RootSpineView> {
  /// The form whose parsing is drawn below the spine. The dial's index is the
  /// same idea; here the spine itself is the only control, so it starts on the
  /// first form rather than on nothing.
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final n = Nocturne.of(context);
    final l = AppLocalizations.of(context)!;
    final reading = widget.reading;
    final selected = reading.derivatives[_index];
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 34),
      children: [
        Padding(
          padding: EdgeInsets.only(bottom: n.space('4')),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                spacing: 10,
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
                  Expanded(
                    child: Text(
                      l.root_spineWeight(
                        reading.translit,
                        reading.occurrences,
                        reading.surahCount,
                      ),
                      style: TextStyle(fontSize: 11, color: n.textAt(0.6)),
                    ),
                  ),
                ],
              ),
              SizedBox(height: n.space('4')),
              CoreSense(reading: reading, judge: widget.judge),
            ],
          ),
        ),
        Container(height: 1, color: n.divider),
        SizedBox(height: n.space('4')),
        SectionHeading(
          l.root_kinHeading,
          trailing: l.root_formCount(reading.derivatives.length),
        ),
        SizedBox(height: n.space('4')),
        KinSpine(
          derivatives: reading.derivatives,
          selected: _index,
          onTap: (i) => setState(() => _index = i),
        ),
        const NocturneRule(),
        // Screen 2b is the reading a third of the roots get — 516 of the 1,642
        // in the corpus have more derivatives than the ring holds — and the
        // route a reader takes to ask for the spine outright. The parsing was
        // drawn only by the dial body, so those readers saw none of it.
        IrabSection(
          segments: reading.irab[selected.wordId] ?? const [],
          word: selected.text,
          where: ayahRef(selected.ayahId),
        ),
        const NocturneRule(),
        // The lexicon section stood under this heading and is gone: Lane is
        // ruled out twice over in docs/research/lane-lexicon.md, and CoreSense above
        // answers what the placeholder stood in for. What is left under Sources
        // is the provenance line, which is what the heading was always for.
        //
        // The server's own /v1/roots/{letters}/lexicon, Store.Lexicon and the
        // lexicon_entries table are left standing on purpose: taking a route
        // and a table out is a separate call from taking a screen section out.
        SectionHeading(l.root_sourcesHeading),
        SizedBox(height: n.space('3')),
        Text(
          l.root_provenance(reading.sources.join(', ')),
          style: TextStyle(fontSize: 10.5, color: n.textAt(0.45)),
        ),
      ],
    );
  }
}

/// The back-and-keep row both root screens carry.
///
/// ponytail: [kept] is a bool and not the kept row's id. This draws an icon and
/// a label and has nothing to do with an id; the screen that holds the id is
/// the one that presses [onKeep].
class RootChrome extends StatelessWidget {
  const RootChrome({
    super.key,
    required this.kicker,
    required this.kept,
    required this.onKeep,
  });

  final String kicker;
  final bool kept;

  /// Null while the screen's own keep is in flight: the bookmark and the
  /// button in the card press the same handler, and the pair of them used to
  /// be the way to mint two rows for one root with two taps.
  final VoidCallback? onKeep;

  @override
  Widget build(BuildContext context) {
    final n = Nocturne.of(context);
    final l = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 8),
      child: Row(
        spacing: 10,
        children: [
          NocturneButton(
            variant: NocturneButtonVariant.icon,
            onPressed: () => Navigator.of(context).maybePop(),
            child: Semantics(
              label: l.root_back,
              child: const Icon(Icons.arrow_back_ios_new, size: 16),
            ),
          ),
          Expanded(
            child: Text(
              kicker.toUpperCase(),
              style: TextStyle(
                fontSize: 10,
                height: 1.2,
                letterSpacing: 0.11 * 10,
                color: n.accent,
              ),
            ),
          ),
          // Live once kept, not latched: a filled bookmark that refuses the
          // press is a control saying the thing cannot be undone, while the
          // only undo in the app is a swipe on a screen nobody is shown.
          NocturneButton(
            variant: NocturneButtonVariant.icon,
            onPressed: onKeep,
            child: Semantics(
              label: kept ? l.root_keptTapToUndoLabel : l.root_keep,
              child: Icon(
                kept ? Icons.bookmark : Icons.bookmark_border,
                size: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
