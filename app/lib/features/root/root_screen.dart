import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import '../../data/root_repo.dart';
import '../../nav.dart';
import '../../theme/nocturne.dart';
import '../../widgets/nocturne_button.dart';
import '../../widgets/nocturne_rule.dart';
import 'root_dial.dart';
import 'root_sections.dart';

/// Screen 3a — one root on its dial, and as deep a reading as the sources go.
///
/// A root with more derivatives than the ring can hold is read as screen 2b
/// instead, which is this screen with the dial taken away. Which one a reader
/// gets is decided here, from the root, so no caller has to know the rule.
class RootScreen extends StatefulWidget {
  const RootScreen({
    super.key,
    required this.db,
    required this.letters,
    this.alwaysSpine = false,
  });

  final Database db;

  /// The root's letters joined, the way the corpus keys them.
  final String letters;

  /// Set by screen 2b, which is the spine whatever the root's size.
  final bool alwaysSpine;

  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> {
  RootReading? _reading;
  bool _loaded = false;
  bool _kept = false;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final reading = await rootReading(widget.db, widget.letters);
    final kept = await rootKept(widget.db, widget.letters);
    if (!mounted) return;
    setState(() {
      _reading = reading;
      _kept = kept;
      _loaded = true;
    });
  }

  Future<void> _keep() async {
    await keepRoot(widget.db, widget.letters);
    if (!mounted) return;
    setState(() => _kept = true);
  }

  @override
  Widget build(BuildContext context) {
    final n = Nocturne.of(context);
    final reading = _reading;
    final spine = widget.alwaysSpine || (reading?.readsAsSpine ?? false);
    return Scaffold(
      backgroundColor: n.bg,
      body: SafeArea(
        child: !_loaded
            ? const SizedBox.shrink()
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  RootChrome(
                    kicker: spine ? 'Root spine' : 'Root',
                    kept: _kept,
                    onKeep: _keep,
                  ),
                  if (reading == null)
                    Expanded(child: _unknown(n))
                  else if (spine)
                    Expanded(child: RootSpineView(reading: reading))
                  else
                    Expanded(child: _dialReading(n, reading)),
                ],
              ),
      ),
    );
  }

  Widget _unknown(Nocturne n) => Center(
    child: Padding(
      padding: EdgeInsets.all(n.space('8')),
      child: Text(
        'The corpus carries no root spelled ${widget.letters}.',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.headlineSmall,
      ),
    ),
  );

  Widget _dialReading(Nocturne n, RootReading reading) {
    final selected = reading.derivatives[_index];
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        RootDial(
          reading: reading,
          index: _index,
          onIndex: (i) => setState(() => _index = i),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: _detailCard(n, reading, selected),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
          child: coreSenseSection(context, reading),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 18),
          child: NocturneRule(),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeading(
                "Its kin in the Qur'an",
                trailing:
                    '${reading.derivatives.length} forms · '
                    '${reading.occurrences} occurrences',
              ),
              SizedBox(height: n.space('4')),
              KinSpine(
                derivatives: reading.derivatives,
                selected: _index,
                onTap: (i) => setState(() => _index = i),
              ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 18),
          child: NocturneRule(),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: lexiconSection(context, reading),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 18),
          child: NocturneRule(),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: tafsirSection(ayahRef(selected.ayahId)),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 18),
          child: NocturneRule(),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 44),
          child: irabSection(selected.text),
        ),
      ],
    );
  }

  Widget _detailCard(Nocturne n, RootReading reading, Derivative selected) =>
      Container(
        padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
        decoration: BoxDecoration(
          color: n.surface,
          borderRadius: BorderRadius.circular(n.radius('lg')),
          boxShadow: n.shadow('md'),
          border: Border.all(color: n.accent.withValues(alpha: 0.22)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              spacing: 10,
              children: [
                Text(
                  selected.text,
                  textDirection: TextDirection.rtl,
                  maxLines: 1,
                  style: TextStyle(
                    fontFamily: Nocturne.arabicFamily,
                    fontSize: 29,
                    height: 1.4,
                    color: n.color('accent-200'),
                  ),
                ),
                Expanded(
                  child: Text(
                    selected.gloss ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: n.textAt(0.82)),
                  ),
                ),
                Text(
                  ayahRef(selected.ayahId),
                  style: TextStyle(fontSize: 11, color: n.accent),
                ),
              ],
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(0, 9, 0, 10),
              child: DashedRule(),
            ),
            Text(
              selected.form == null
                  ? '${selected.occurrences}× IN THE QUR’AN'
                  : 'FORM ${selected.form} · ${selected.occurrences}×',
              style: TextStyle(
                fontSize: 10,
                height: 1.2,
                letterSpacing: 0.1 * 10,
                color: n.accent,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 6, 0, 11),
              child: Text(
                derivativeNote(selected),
                style: TextStyle(fontSize: 13.5, height: 1.55, color: n.text),
              ),
            ),
            Row(
              spacing: 8,
              children: [
                Expanded(
                  child: NocturneButton(
                    onPressed: () => Navigator.of(context).pushNamed(
                      Routes.deepDive,
                      arguments: (
                        ayahId: selected.ayahId,
                        letters: reading.letters,
                      ),
                    ),
                    child: const Text('Read the aya'),
                  ),
                ),
                Expanded(
                  child: NocturneButton(
                    variant: NocturneButtonVariant.primary,
                    onPressed: _kept ? null : _keep,
                    child: Text(_kept ? 'Kept' : 'Keep this root'),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
}
