import 'package:flutter/material.dart';

import '../../data/root_repo.dart';
import '../../theme/nocturne.dart';
import '../../widgets/nocturne_button.dart';
import '../../widgets/nocturne_card.dart';
import '../../widgets/nocturne_rule.dart';

/// The line the design prints under its own mocked-up prose. It travels with
/// every word on this screen that was not read out of the corpus.
const mockupNotice =
    'Placeholder summaries written for this mockup — the real build pulls '
    'sourced translations.';

const _lexiconPending =
    'The lexicon is fetched rather than bundled, and the fetch is not built '
    'yet. These are the works it will quote.';
const _tafsirPending =
    'Tafsir is fetched per aya. Nothing is downloaded yet, so nothing is '
    'attributed here.';
const _irabPending =
    'The parsing of this phrase is fetched per aya, and no aya has been '
    'downloaded yet.';

/// Which works each section will quote once the fetch exists. Naming them is
/// not a claim about what they say.
const lexiconSources = ['Ibn Fāris · Maqāyīs al-Lugha', 'Lane · Arabic-English Lexicon'];
const tafsirSources = ['Al-Ṭabarī', 'Ibn Kathīr', 'Al-Rāzī'];

typedef MockupProse = ({
  String coreSense,
  String coreAside,
  List<(String, String)> lexicon,
});

/// Prose the design wrote into its own mockup, kept under the one root it was
/// written about. A different root shows the section as pending rather than
/// borrowing these words: mock scholarship attached to the wrong root is a
/// lie about scripture, and the reader has no way to check it.
const mockupProse = <String, MockupProse>{
  'صبر': (
    coreSense:
        'To bind fast; to hold a thing to its place. Patience is the rope, '
        'not the mood — the self tied to its post while the pull continues.',
    coreAside:
        'The same three letters name the bitter aloe (ṣabr), the hard stony '
        'ground (ṣubra), and the edge of a vessel (ṣubr). Bitterness, '
        'hardness and a held border sit inside the word you recite.',
    lexicon: [
      (
        'Ibn Fāris · Maqāyīs al-Lugha',
        'Gives the root one governing sense — restraint and confinement — '
            'and derives the rest from it.',
      ),
      (
        'Lane · Arabic-English Lexicon',
        'Records the concrete senses beside the moral one: the aloe plant, '
            'stony ground, the edge of a vessel.',
      ),
    ],
  ),
};

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

/// The derivatives read down the page instead of round the ring: a dotted
/// thread with one node per form.
class KinSpine extends StatelessWidget {
  const KinSpine({
    super.key,
    required this.derivatives,
    this.selected,
    this.onTap,
  });

  final List<Derivative> derivatives;

  /// The form the dial is pointing at. The spine lights the same one, so the
  /// two never disagree about what is being read.
  final int? selected;
  final ValueChanged<int>? onTap;

  @override
  Widget build(BuildContext context) {
    final n = Nocturne.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 26),
      child: Stack(
        // The thread and its nodes hang to the left of the rows they belong
        // to, which is off the edge of this stack.
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: -21,
            top: 6,
            bottom: 20,
            width: 1,
            child: CustomPaint(painter: _ThreadPainter(n.textAt(0.26))),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < derivatives.length; i++)
                _row(n, derivatives[i], i),
            ],
          ),
        ],
      ),
    );
  }

  Widget _row(Nocturne n, Derivative derivative, int i) {
    final lit = i == selected;
    return Padding(
      padding: EdgeInsets.only(bottom: i == derivatives.length - 1 ? 0 : 14),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap == null ? null : () => onTap!(i),
        child: Container(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(n.radius('md')),
            color: lit ? n.accent.withValues(alpha: 0.13) : null,
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: -34,
                top: lit ? 12 : 13,
                child: lit ? _litNode(n) : _node(n),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    spacing: 9,
                    children: [
                      Text(
                        derivative.text,
                        textDirection: TextDirection.rtl,
                        maxLines: 1,
                        style: TextStyle(
                          fontFamily: Nocturne.arabicFamily,
                          fontSize: lit ? 23 : 22,
                          height: 1.4,
                          color: lit ? n.color('accent-200') : n.text,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          derivative.gloss ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: n.textAt(0.78),
                          ),
                        ),
                      ),
                      Text(
                        ayahRef(derivative.ayahId),
                        style: TextStyle(
                          fontSize: 10.5,
                          color: lit ? n.accent : n.textAt(0.6),
                        ),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      derivativeNote(derivative),
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.5,
                        color: n.textAt(0.7),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _node(Nocturne n) => Container(
    width: 9,
    height: 9,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: n.color('accent-600'),
    ),
  );

  Widget _litNode(Nocturne n) => Container(
    width: 11,
    height: 11,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: n.bg,
      border: Border.all(color: n.accent, width: 1.5),
      boxShadow: [
        BoxShadow(
          color: n.accent.withValues(alpha: 0.55),
          blurRadius: 10,
        ),
      ],
    ),
  );
}

/// What the corpus knows about one form, said in a line. The design puts
/// authored prose here; until a root carries notes, its grammar and its weight
/// in the text are what there is to say.
String derivativeNote(Derivative derivative) {
  if (derivative.note != null) return derivative.note!;
  final occurrences = derivative.occurrences == 1
      ? 'once in the Qur’an'
      : '${derivative.occurrences} times in the Qur’an';
  return derivative.form == null
      ? 'Occurs $occurrences.'
      : 'Form ${derivative.form}. Occurs $occurrences.';
}

/// The dashed hairline the design draws inside the detail card.
class DashedRule extends StatelessWidget {
  const DashedRule({super.key});

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    height: 1,
    child: CustomPaint(
      painter: _ThreadPainter(Nocturne.of(context).textAt(0.22), across: true),
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
    required this.sources,
    required this.explanation,
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

/// The section a fetched source fills once it exists.
Widget lexiconSection(BuildContext context, RootReading reading) {
  final prose = mockupProse[reading.letters];
  if (prose == null) {
    return const PendingSection(
      heading: 'Lexicon',
      sources: lexiconSources,
      explanation: _lexiconPending,
    );
  }
  final n = Nocturne.of(context);
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SectionHeading('Lexicon'),
      SizedBox(height: n.space('3')),
      for (final (source, body) in prose.lexicon)
        Padding(
          padding: EdgeInsets.only(bottom: n.space('3')),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(source, style: TextStyle(fontSize: 11, color: n.accent)),
              SizedBox(height: n.space('1')),
              Text(
                body,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.55,
                  color: n.textAt(0.82),
                ),
              ),
            ],
          ),
        ),
      Text(
        mockupNotice,
        style: TextStyle(fontSize: 10.5, height: 1.5, color: n.textAt(0.5)),
      ),
    ],
  );
}

/// Core sense: the root's own meaning, which is authored prose rather than
/// anything the morphology can derive.
Widget coreSenseSection(BuildContext context, RootReading reading) {
  final n = Nocturne.of(context);
  final prose = mockupProse[reading.letters];
  final corpus = reading.coreSense;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SectionHeading('Core sense'),
      SizedBox(height: n.space('2')),
      if (corpus != null)
        Text(
          corpus,
          style: TextStyle(fontSize: 13.5, height: 1.5, color: n.text),
        )
      else if (prose != null) ...[
        Text(
          prose.coreSense,
          style: TextStyle(fontSize: 13.5, height: 1.5, color: n.text),
        ),
        SizedBox(height: n.space('2')),
        Text(
          prose.coreAside,
          style: TextStyle(fontSize: 12, height: 1.5, color: n.textAt(0.64)),
        ),
        SizedBox(height: n.space('2')),
        Text(
          mockupNotice,
          style: TextStyle(fontSize: 10.5, height: 1.5, color: n.textAt(0.5)),
        ),
      ] else
        Text(
          'No one has written this root’s core sense yet. What the '
          'corpus knows about it is the ${reading.occurrences} places it is '
          'read, below.',
          style: TextStyle(fontSize: 13.5, height: 1.5, color: n.textAt(0.72)),
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
    final prose = mockupProse[reading.letters];
    final core = reading.coreSense ?? prose?.coreSense;
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
              if (prose != null) ...[
                SizedBox(height: n.space('2')),
                Text(
                  prose.coreAside,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: n.textAt(0.62),
                  ),
                ),
                SizedBox(height: n.space('2')),
                // The design prints this once, at the foot of the screen. A
                // root with forty derivatives puts the foot thousands of
                // pixels below the prose, so the mark travels with the words
                // it is marking.
                Text(
                  mockupNotice,
                  style: TextStyle(
                    fontSize: 10.5,
                    height: 1.5,
                    color: n.textAt(0.5),
                  ),
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
        if (prose == null)
          const PendingSection(
            heading: 'Lexicon',
            sources: lexiconSources,
            explanation: _lexiconPending,
          )
        else ...[
          for (final (source, body) in prose.lexicon)
            Padding(
              padding: EdgeInsets.only(bottom: n.space('2')),
              child: NocturneCard(
                body: body,
                meta: [Text(source)],
                elevation: NocturneElevation.sm,
              ),
            ),
          Text(
            mockupNotice,
            style: TextStyle(fontSize: 10.5, height: 1.5, color: n.textAt(0.5)),
          ),
        ],
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

/// Two pixels of line every seven, the way the design's repeating gradient
/// draws it.
class _ThreadPainter extends CustomPainter {
  const _ThreadPainter(this.colour, {this.across = false});

  final Color colour;
  final bool across;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = colour
      ..strokeWidth = 1;
    final length = across ? size.width : size.height;
    for (var at = 0.0; at < length; at += 7) {
      final end = (at + 2).clamp(0.0, length);
      canvas.drawLine(
        across ? Offset(at, 0) : Offset(0, at),
        across ? Offset(end, 0) : Offset(0, end),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_ThreadPainter old) =>
      old.colour != colour || old.across != across;
}
