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

/// Core sense: the root's own meaning, which is authored prose rather than
/// anything the morphology can derive. No root carries it yet, and a root
/// without one shows no section at all — a heading over an apology is still a
/// heading the reader has to read.
Widget coreSenseSection(BuildContext context, RootReading reading) {
  final sense = reading.coreSense;
  if (sense == null) return const SizedBox.shrink();
  final n = Nocturne.of(context);
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SectionHeading('Core sense'),
      SizedBox(height: n.space('2')),
      Text(
        sense,
        style: TextStyle(fontSize: 13.5, height: 1.5, color: n.text),
      ),
    ],
  );
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
    final core = reading.coreSense;
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
              if (core != null) ...[
                SizedBox(height: n.space('4')),
                Text(
                  core,
                  style: TextStyle(fontSize: 13.5, height: 1.5, color: n.text),
                ),
              ],
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
