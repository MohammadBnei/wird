import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import '../../data/root_repo.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/nocturne.dart';
import '../../widgets/nocturne_button.dart';
import '../../widgets/nocturne_rule.dart';
import '../../widgets/nocturne_segmented.dart';
import '../root/root_sections.dart';

/// The width the design's own grid needs: the 292 and 336 point rails it
/// fixes, and a centre at least as wide as the wider of them. Narrower than
/// this and the constellation — the reason the screen exists — would be the
/// thinnest of the three panes, so the same three panes stack into one
/// column instead.
const threePaneWidth = 964.0;

/// One aya as this screen reads it: its place, its words, and which of them
/// carry the root that was opened.
typedef AyaReading = ({
  String surahName,
  int number,
  List<AyaWord> words,
});

/// One word of the aya: its id, so the parsing of this occurrence can be read,
/// and whether it carries the root that was opened.
typedef AyaWord = ({int id, String text, bool lit});

/// Screen 1c — one aya, its sources side by side, on a tablet.
///
/// The three panes are what the design draws and what a tablet gets. A window
/// too narrow for them reads the same three panes down one column rather than
/// crushing them side by side. The choice is made here, from the width, so no
/// caller has to know the rule — the same way the root screen chooses between
/// its dial and its spine.
class DeepDiveScreen extends StatefulWidget {
  const DeepDiveScreen({
    super.key,
    required this.db,
    required this.ayahId,
    required this.letters,
  });

  final Database db;

  /// surah * 1000 + aya, the corpus's own key.
  final int ayahId;

  /// The root lit inside that aya.
  final String letters;

  @override
  State<DeepDiveScreen> createState() => _DeepDiveScreenState();
}

class _DeepDiveScreenState extends State<DeepDiveScreen> {
  RootReading? _reading;
  AyaReading? _aya;

  /// The parsing of the root's own word in *this* aya — not of the spelling.
  /// The root screen's copy reads the first occurrence in the muṣḥaf; here the
  /// aya is given, so the occurrence is too.
  List<IrabSegment> _irab = const [];
  bool _loaded = false;

  /// The id this aya is kept under, or null. Read once in [_load]; nothing
  /// listens to `kept_items`, so a delete made on screen 1e while this screen
  /// is open does not reach the button until it is reopened.
  String? _keptId;

  /// Whether a keep or an undo is in flight. Two taps inside the `await` would
  /// both read `_keptId` as null and both write: the latch this replaced was
  /// also the only thing stopping that.
  bool _busy = false;
  int _view = 0;

  AppLocalizations get _l10n => AppLocalizations.of(context)!;

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
    final readIn = _readIn ?? Localizations.localeOf(context);
    final reading = await rootReading(widget.db, widget.letters, readIn: readIn);
    final aya = await ayaReading(widget.db, widget.ayahId, widget.letters);
    final keptId = await ayaKept(widget.db, widget.ayahId);
    final lit = aya == null ? null : _litWord(aya);
    final irab = lit == null
        ? const <IrabSegment>[]
        : await wordIrab(widget.db, lit.id, readIn: readIn);
    if (!mounted) return;
    setState(() {
      _reading = reading;
      _aya = aya;
      _irab = irab;
      _keptId = keptId;
      _loaded = true;
    });
  }

  /// Keeps the aya, or takes it back off the list. One handler, because the
  /// control is one button: a reader who has just pressed Keep is the reader
  /// most likely to want it undone.
  Future<void> _toggleKeep() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      String? keptId;
      if (_keptId == null) {
        keptId = await keepAya(widget.db, widget.ayahId);
      } else {
        await forgetAya(widget.db, widget.ayahId);
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
    final aya = _aya;
    return Scaffold(
      backgroundColor: n.bg,
      body: SafeArea(
        child: !_loaded
            ? const SizedBox.shrink()
            : reading == null || aya == null
            ? _unknown(n)
            : LayoutBuilder(
                builder: (context, constraints) =>
                    constraints.maxWidth < threePaneWidth
                    ? _oneColumn(n, reading, aya, constraints.maxWidth)
                    : _threePanes(n, reading, aya),
              ),
      ),
    );
  }

  Widget _unknown(Nocturne n) => Center(
    child: Padding(
      padding: EdgeInsets.all(n.space('8')),
      child: Text(
        _l10n.deepdive_unknown(ayahRef(widget.ayahId), widget.letters),
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.headlineSmall,
      ),
    ),
  );

  Widget _threePanes(Nocturne n, RootReading reading, AyaReading aya) => Row(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Container(
        width: 292,
        padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 20),
        decoration: BoxDecoration(
          border: Border(right: BorderSide(color: n.divider)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: _ayaPane(n, aya, leading: _back()),
              ),
            ),
            SizedBox(height: n.space('4')),
            _keepButton(),
          ],
        ),
      ),
      Expanded(
        child: _centrePane(
          n,
          reading,
          aya,
          // The centre pane of the design's own grid is wide enough for the
          // drawing, so the reader gets the choice between it and the list.
          drawn: true,
          view: Expanded(child: _family(n, reading, aya)),
        ),
      ),
      Container(
        width: 336,
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: n.divider)),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 20),
          child: _sourcesPane(),
        ),
      ),
    ],
  );

  /// The same three panes read down one column, for a window the design's
  /// rails do not fit in. It carries the back arrow the tablet frame does
  /// not draw, because on a phone this screen is pushed over another.
  Widget _oneColumn(
    Nocturne n,
    RootReading reading,
    AyaReading aya,
    double width,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(18, 6, 18, 8),
        child: Row(
          spacing: 10,
          children: [
            _back(),
            Expanded(
              child: Text(
                _l10n.deepdive_kicker(ayahRef(widget.ayahId)),
                style: TextStyle(
                  fontSize: 10,
                  height: 1.2,
                  letterSpacing: 0.11 * 10,
                  color: n.accent,
                ),
              ),
            ),
          ],
        ),
      ),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 34),
          children: [
            _ayaPane(n, aya),
            SizedBox(height: n.space('4')),
            _keepButton(),
            SizedBox(height: n.space('6')),
            _centrePane(
              n,
              reading,
              aya,
              // 20 points of list gutter and 26 of pane padding on each side.
              drawn: width - 92 >= constellationFloor,
              view: _family(n, reading, aya),
            ),
            SizedBox(height: n.space('6')),
            _sourcesPane(),
          ],
        ),
      ),
    ],
  );

  /// The arrow every other Nocturne screen draws at the head of its first
  /// column. Three panes or one, the reader leaves the same way.
  Widget _back() => NocturneButton(
    variant: NocturneButtonVariant.icon,
    onPressed: () => Navigator.of(context).maybePop(),
    child: Semantics(
      label: _l10n.deepdive_back,
      child: const Icon(Icons.arrow_back_ios_new, size: 16),
    ),
  );

  /// [leading] rides the aya's kicker line, which in the three panes is the
  /// top line of the leftmost one and so the head of the screen.
  Widget _ayaPane(Nocturne n, AyaReading aya, {Widget? leading}) {
    final kicker = Text(
      _l10n.deepdive_aya_kicker(aya.surahName, aya.number).toUpperCase(),
      style: TextStyle(
        fontSize: 10,
        height: 1.2,
        letterSpacing: 0.11 * 10,
        color: n.accent,
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (leading == null)
          kicker
        else
          Row(
            spacing: 10,
            children: [
              leading,
              Expanded(child: kicker),
            ],
          ),
        const SizedBox(height: 14),
        Text.rich(
          TextSpan(
            children: [
              for (final (i, word) in aya.words.indexed)
                TextSpan(
                  text: i == 0 ? word.text : ' ${word.text}',
                  style: word.lit
                      ? TextStyle(
                          color: n.color('accent-200'),
                          shadows: [
                            Shadow(
                              color: n.accent.withValues(alpha: 0.55),
                              blurRadius: 22,
                            ),
                          ],
                        )
                      : null,
                ),
            ],
          ),
          textDirection: TextDirection.rtl,
          style: TextStyle(
            fontFamily: Nocturne.arabicFamily,
            fontSize: 25,
            height: 2.1,
            color: n.text,
          ),
        ),
        // Both the rule and the section go when the aya does not carry the root:
        // there is no word to parse, and a heading over nothing reads worse
        // than no heading.
        if (_litWord(aya) case final lit?) ...[
          const NocturneRule(fade: 40),
          IrabSection(
            segments: _irab,
            word: lit.text,
            where: '${aya.surahName} ${aya.number}',
          ),
        ],
      ],
    );
  }

  // The design draws "Compare translations" beside this. The corpus ships one
  // rendering of the aya and no second translation to compare it with, so
  // that button is left out rather than drawn dead.
  //
  // It used to say "Add to notes" and write a bookmark, which sent the reader
  // to a Notes list that stayed empty. Nothing in the app writes a note, and
  // this keeps the aya, so it says so — in the root screen's own words.
  //
  // It used to disable itself once pressed, and read "Kept". That is a control
  // saying the thing is done and permanent, while the only way back was a
  // swipe on another screen nobody is shown. So it stays live and the label
  // carries its own undo.
  Widget _keepButton() => NocturneButton(
    block: true,
    onPressed: _busy ? null : _toggleKeep,
    child: Text(_keptId == null ? _l10n.deepdive_keep : _l10n.deepdive_kept),
  );

  /// [drawn] is whether this pane is wide enough for the design's
  /// constellation. Where it is not, the family is read as a ring and a spine
  /// — which is the list already — so the choice between them is not offered.
  Widget _centrePane(
    Nocturne n,
    RootReading reading,
    AyaReading aya, {
    required Widget view,
    required bool drawn,
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0, -0.16),
          radius: 0.9,
          colors: [
            Color.alphaBlend(n.accent.withValues(alpha: 0.05), n.bg),
            n.bg,
          ],
          stops: const [0, 0.7],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 26),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _rootName(n, reading)),
                if (drawn)
                  NocturneSegmented(
                    options: [
                      _l10n.deepdive_view_constellation,
                      _l10n.deepdive_view_list,
                    ],
                    selected: _view,
                    onChanged: (i) => setState(() => _view = i),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            CoreSense(reading: reading, senseSize: 14.5),
            // The ring draws its pointer hard against its own top edge, so
            // the gap under the sense is the only thing keeping the arrow off
            // the last line of it.
            SizedBox(height: n.space('3')),
            view,
          ],
        ),
      ),
    );
  }

  /// The root's family, however this screen has room to draw it.
  Widget _family(Nocturne n, RootReading reading, AyaReading aya) {
    final here = _litWord(aya)?.text;
    if (_view == 1) {
      return SingleChildScrollView(
        padding: EdgeInsets.only(top: n.space('4')),
        child: KinSpine(
          derivatives: reading.derivatives,
          here: reading.spelled(here),
        ),
      );
    }
    return RootFamily(
      reading: reading,
      ayahId: widget.ayahId,
      wordInAya: here,
    );
  }

  /// How this aya spells the root, or null where it does not carry it.
  AyaWord? _litWord(AyaReading aya) {
    final lit = [
      for (final word in aya.words)
        if (word.lit) word,
    ];
    return lit.isEmpty ? null : lit.last;
  }

  Widget _rootName(Nocturne n, RootReading reading) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        _l10n.deepdive_root_heading,
        style: TextStyle(
          fontSize: 10,
          height: 1.2,
          letterSpacing: 0.11 * 10,
          color: n.accent,
        ),
      ),
      SizedBox(height: n.space('2')),
      Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        children: [
          Text(
            reading.display,
            textDirection: TextDirection.rtl,
            style: TextStyle(
              fontFamily: Nocturne.arabicFamily,
              fontSize: 34,
              letterSpacing: 0.16 * 34,
              color: n.text,
            ),
          ),
          Text(
            _l10n.deepdive_occurrences(reading.translit, reading.occurrences),
            style: TextStyle(fontSize: 12, color: n.textAt(0.6)),
          ),
        ],
      ),
    ],
  );

  /// What is left of the sources pane now the lexicon placeholder is gone. The
  /// rule above it went with it: it separated two sections and there is one.
  Widget _sourcesPane() => tafsirSection(ayahRef(widget.ayahId));
}

/// The aya as it is printed, with the words carrying [letters] marked. Null
/// when the corpus has no such aya.
Future<AyaReading?> ayaReading(Database db, int ayahId, String letters) async {
  final place = await db.rawQuery(
    '''SELECT a.number, s.name_en
         FROM ayahs a
         JOIN surahs s ON s.id = a.surah_id
        WHERE a.id = ?''',
    [ayahId],
  );
  if (place.isEmpty) return null;
  final words = await db.query(
    'words',
    columns: ['id', 'text_ar', 'root_letters'],
    where: 'ayah_id = ?',
    whereArgs: [ayahId],
    orderBy: 'position',
  );
  return (
    surahName: place.first['name_en']! as String,
    number: place.first['number']! as int,
    words: [
      for (final w in words)
        (
          id: w['id']! as int,
          text: w['text_ar']! as String,
          lit: w['root_letters'] == letters,
        ),
    ],
  );
}

// ayaKept moved into app/lib/data/root_repo.dart beside rootKept: the undo
// needs every live row for the aya, and reading them in the order that rule
// asks for is the same rule twice if it is written twice.
