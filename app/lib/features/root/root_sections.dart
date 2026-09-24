import 'package:flutter/material.dart';

import '../../data/root_repo.dart';
import '../../theme/nocturne.dart';
import '../../widgets/nocturne_button.dart';
import '../../widgets/nocturne_rule.dart';
import 'family.dart';

// A family's own widgets live in family.dart. They are exported here so a
// screen reading a root asks one file for the sections and the spine both.
export 'family.dart';

const _lexiconPending =
    'The lexicon is fetched rather than bundled. Neither the fetch nor the '
    'choice of lexicon is settled, so no work is named here and none is '
    'quoted.';
const _tafsirPending =
    'Tafsir is fetched per aya. Nothing is downloaded yet, so nothing is '
    'attributed here.';
const _irabPending =
    'The parsing of this phrase is fetched per aya, and no aya has been '
    'downloaded yet.';

/// Said where a root ships no sense, which is two roots in three. The absence
/// is the machine declining to claim something its own evidence does not
/// carry, and a reader who is not told that reads it as a missing section.
const _senseRefused =
    "Wird writes a root's sense only where that root's own words in the "
    'Qur\'an bear it out. These do not, so nothing is claimed here.';

/// Which commentaries the tafsir section will quote once the fetch exists.
/// Naming them is not a claim about what they say.
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

/// The section a fetched lexicon fills once it exists.
Widget lexiconSection(BuildContext context, RootReading reading) =>
    const PendingSection(heading: 'Lexicon', explanation: _lexiconPending);

/// Core sense: what the root means, and whose reading that is.
///
/// The sense is Wird's own — written from the root's own words in this corpus
/// and kept only where their glosses bore it out. A reader cannot be left to
/// guess whether it is that or a quotation from a lexicon, because a version
/// of this feature was already reverted for shipping invented prose under two
/// lexicographers' names. So the line saying whose reading it is sits under
/// the sentence, and the words it rests on are one tap further.
class CoreSense extends StatelessWidget {
  const CoreSense({super.key, required this.reading, this.senseSize = 13.5});

  final RootReading reading;

  /// The deep dive reads the same sentence a point larger than the two root
  /// screens do.
  final double senseSize;

  @override
  Widget build(BuildContext context) {
    final sense = reading.coreSense;
    if (sense == null) {
      return const PendingSection(
        heading: 'Core sense',
        explanation: _senseRefused,
      );
    }
    final n = Nocturne.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeading('Core sense'),
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
  String _whoseWords(String? source, int words) {
    final borne = words == 0
        ? ''
        : ", borne out by $words of the root's own words";
    return source == null || source == 'Wird'
        ? "This app's own reading$borne"
        : "$source's reading$borne";
  }

  Widget _whose(BuildContext context, Nocturne n) {
    final source = reading.senseSource;
    final words = reading.senseEvidence.length;
    if (words == 0) {
      return Text(
        '${_whoseWords(source, 0)}.',
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
          _whoseWords(source, words),
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
        const SectionHeading('Whose reading this is'),
        SizedBox(height: n.space('2')),
        Text(
          reading.senseBasis ?? '',
          style: TextStyle(fontSize: 12.5, height: 1.55, color: n.textAt(0.7)),
        ),
        const NocturneRule(),
        SectionHeading(
          'The words it was read from',
          trailing: '${reading.senseEvidence.length} words',
        ),
        SizedBox(height: n.space('3')),
        // The stored order is the bar's own, grouped by morphological shape,
        // so it is kept rather than sorted: the grouping is the argument.
        for (final word in reading.senseEvidence) _word(n, word),
      ],
    );
  }

  Widget _word(Nocturne n, String word) {
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
                    'FORM $form',
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

Widget tafsirSection(String? ref) => PendingSection(
  heading: ref == null ? 'Tafsir' : 'Tafsir · $ref',
  sources: tafsirSources,
  explanation: _tafsirPending,
);

Widget irabSection(String? phrase) => PendingSection(
  heading: phrase == null ? 'Iʿrāb' : 'Iʿrāb · $phrase',
  sources: const ['The word-by-word parsing of this aya'],
  explanation: _irabPending,
);

/// Screen 2b's body: the same root with the dial taken away. A root with more
/// derivatives than the ring can hold is read here instead.
class RootSpineView extends StatelessWidget {
  const RootSpineView({super.key, required this.reading});

  final RootReading reading;

  @override
  Widget build(BuildContext context) {
    final n = Nocturne.of(context);
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
                      '${reading.translit} · ${reading.occurrences} in '
                      '${reading.surahCount} sūras',
                      style: TextStyle(fontSize: 11, color: n.textAt(0.6)),
                    ),
                  ),
                ],
              ),
              SizedBox(height: n.space('4')),
              CoreSense(reading: reading),
            ],
          ),
        ),
        Container(height: 1, color: n.divider),
        SizedBox(height: n.space('4')),
        SectionHeading(
          "Its kin in the Qur'an",
          trailing: '${reading.derivatives.length} forms',
        ),
        SizedBox(height: n.space('4')),
        KinSpine(derivatives: reading.derivatives),
        const NocturneRule(),
        SectionHeading('Sources'),
        SizedBox(height: n.space('3')),
        lexiconSection(context, reading),
        SizedBox(height: n.space('3')),
        Text(
          'Provenance: ${reading.sources.join(', ')}',
          style: TextStyle(fontSize: 10.5, color: n.textAt(0.45)),
        ),
      ],
    );
  }
}

/// The back-and-keep row both root screens carry.
class RootChrome extends StatelessWidget {
  const RootChrome({
    super.key,
    required this.kicker,
    required this.kept,
    required this.onKeep,
  });

  final String kicker;
  final bool kept;
  final VoidCallback onKeep;

  @override
  Widget build(BuildContext context) {
    final n = Nocturne.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 8),
      child: Row(
        spacing: 10,
        children: [
          NocturneButton(
            variant: NocturneButtonVariant.icon,
            onPressed: () => Navigator.of(context).maybePop(),
            child: Semantics(
              label: 'Back',
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
          NocturneButton(
            variant: NocturneButtonVariant.icon,
            onPressed: kept ? null : onKeep,
            child: Semantics(
              label: kept ? 'Kept' : 'Keep',
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
