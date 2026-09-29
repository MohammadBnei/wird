import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import '../../data/root_repo.dart';
import '../../l10n/app_localizations.dart';
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

  /// The id this root is kept under, or null. Read once in [_load]; nothing
  /// listens to `kept_items`, so a delete made on screen 1e while this screen
  /// is open does not reach the two buttons until it is reopened.
  String? _keptId;

  /// Whether a keep or an undo is in flight. Two taps inside the `await` would
  /// both read `_keptId` as null and both write: the latch this replaced was
  /// also the only thing stopping that.
  bool _busy = false;
  int _index = 0;

  /// The strings this screen draws. A getter rather than a local threaded
  /// through every builder: the card, the kicker and the headings are four
  /// methods deep and none of them takes a context of its own.
  AppLocalizations get _l => AppLocalizations.of(context)!;

  /// The language the sense on screen was read in, so a reader who switches
  /// language is handed the other sentence where they are rather than on the
  /// next visit. Null until the first load.
  Locale? _readIn;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final locale = Localizations.localeOf(context);
    if (locale == _readIn) return;
    _readIn = locale;
    _load();
  }

  Future<void> _load() async {
    final reading = await rootReading(
      widget.db,
      widget.letters,
      inFrench: _readIn?.languageCode == 'fr',
    );
    final keptId = await rootKept(widget.db, widget.letters);
    if (!mounted) return;
    setState(() {
      _reading = reading;
      _keptId = keptId;
      _loaded = true;
    });
  }

  /// Keeps the root, or takes it back off the list. Both controls on this
  /// screen — the bookmark at the top and the button in the card — press it,
  /// because a toggle beside a latched chip is the defect this replaced.
  Future<void> _toggleKeep() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      String? keptId;
      if (_keptId == null) {
        keptId = await keepRoot(widget.db, widget.letters);
      } else {
        await forgetRoot(widget.db, widget.letters);
      }
      if (!mounted) return;
      setState(() => _keptId = keptId);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
                    kicker: spine ? _l.root_kickerSpine : _l.root_kicker,
                    kept: _keptId != null,
                    onKeep: _busy ? null : _toggleKeep,
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
        _l.root_unknownRoot(widget.letters),
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
          child: CoreSense(reading: reading),
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
                _l.root_kinHeading,
                trailing: _l.root_kinFormsAndOccurrences(
                  reading.derivatives.length,
                  reading.occurrences,
                ),
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
          child: tafsirSection(ayahRef(selected.ayahId)),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 18),
          child: NocturneRule(),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 44),
          // The dial's selected form is a spelling met many times over. The
          // parsing is of its first occurrence, which is the aya the card above
          // already names, and the section says so rather than leaving the
          // reader to read one occurrence's case as the form's own.
          child: IrabSection(
            segments: reading.irab[selected.wordId] ?? const [],
            word: selected.text,
            where: ayahRef(selected.ayahId),
          ),
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
                AyaRef(ayahId: selected.ayahId, lit: true),
              ],
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(0, 9, 0, 10),
              child: DashedRule(),
            ),
            Text(
              selected.form == null
                  ? _l.root_cardWeight(selected.occurrences)
                  : _l.root_cardWeightWithForm(
                      selected.form!,
                      selected.occurrences,
                    ),
              style: TextStyle(
                fontSize: 10,
                height: 1.2,
                letterSpacing: 0.1 * 10,
                color: n.accent,
              ),
            ),
            // The kicker above already gives the form and the weight, so
            // what is left to say here is the authored note or nothing.
            if (selected.note != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  selected.note!,
                  style: TextStyle(fontSize: 13.5, height: 1.55, color: n.text),
                ),
              ),
            const SizedBox(height: 11),
            Row(
              spacing: 8,
              children: [
                Expanded(
                  // The button reads the aya. It used to open screen 1c —
                  // the analysis of the aya, which is a different request and
                  // is already reachable from the word that led here.
                  child: NocturneButton(
                    onPressed: () => openAya(context, selected.ayahId),
                    child: Text(_l.root_readTheAya),
                  ),
                ),
                Expanded(
                  child: NocturneButton(
                    variant: NocturneButtonVariant.primary,
                    onPressed: _busy ? null : _toggleKeep,
                    child: Text(
                      _keptId == null
                          ? _l.root_keepThisRoot
                          : _l.root_keptTapToUndo,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
}
