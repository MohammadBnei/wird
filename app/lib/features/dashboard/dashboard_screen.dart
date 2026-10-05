import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import '../../app.dart';
import '../../data/db.dart';
import '../../data/root_repo.dart' show ayahOfWord;
import '../../data/sets.dart';
import '../../l10n/app_localizations.dart';
import '../../nav.dart';
import '../../theme/nocturne.dart';
import '../progress/passage.dart';
import '../study/word_row.dart' show arabicDigits;
import '../../widgets/nocturne_button.dart';
import '../../widgets/nocturne_kicker.dart';
import '../../widgets/nocturne_rule.dart';

/// What the walk has ready, where it stands in the Qur'an, the sūras the
/// reader is part-way through, and nothing the reader has to work out.
typedef Waiting = ({
  StudySet? set,
  int number,
  int prayers,
  ReadingOrder order,

  /// Whether the reader has understood an aya or recorded a prayer. Opening
  /// a sūra is not starting: a word tapped out of curiosity marks nothing.
  bool started,
  List<SuraPassage> suras,
  List<ReadingPlace> reading,
});

Future<Waiting> whatIsWaiting(Database db, ReadingOrder order) async {
  final set = await nextSet(db, order);
  final here = set?.ayas.first.surahId;
  final suras = await suraPassages(db, here);
  final prayed = Sqflite.firstIntValue(
    await db.rawQuery('SELECT COUNT(*) FROM set_prayers'),
  )!;
  return (
    set: set,
    // The sets already finished, plus the one being read. It comes from the
    // walk rather than from counting rows, because the rows record sets
    // *prayed* and a set can be prayed without ever being understood.
    number: await setsUnderstood(db, order) + 1,
    prayers: set == null ? 0 : await prayersOnSet(db, set.id),
    order: order,
    started: prayed > 0 || suras.any((s) => s.understood > 0),
    // In the order the reader walks, which is the order the strip is drawn.
    suras: order == ReadingOrder.nuzul
        ? (suras.toList()
            ..sort((a, b) => a.revelationOrder.compareTo(b.revelationOrder)))
        : suras,
    // The walk's own sūra is already named by the set; listing it again as a
    // place to continue would be the same place twice.
    reading: await readingPlaces(db, limit: 3, except: here),
  );
}

/// Home.
///
/// It is the way IN. It answers what is waiting, where that sits in the
/// Qur'an, and what the reader can do about it, then hands them on to the
/// screens that study the thing. Where the reader stands is one line and one
/// strip of the 114 sūras (ADR 0033); 1d keeps the ring, the tiles, the sūra
/// rows and the roots.
///
/// A reader who has not started is told what a set is before being asked to
/// pray one. That is derived, never a flag: the welcome goes with the first
/// aya understood or the first prayer recorded.
///
/// Every figure on it is read from the corpus at the moment it is drawn. There
/// is no streak, no daily target and no plausible-looking number that nobody
/// computed.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Waiting? _waiting;

  /// Which read owns the screen. Two can be in flight at once — the one the
  /// prayer's return asks for, and the one this screen asks for after the
  /// prayer has been recorded — and only the last one asked for is current.
  int _read = 0;

  // The first read happens here rather than in initState because the corpus
  // and the reader's order are reached through the application above this
  // screen.
  /// Home lies under everything, and everything above it can move the walk: a
  /// set marked understood, a prayer, a change of reading order. Being
  /// uncovered is the one moment all three have in common, and this is where
  /// the screen hears about it.
  ///
  /// **`ModalRoute.of(context)` is the subscription.** It is not a lookup
  /// whose result is discarded — reading it registers a dependency on the
  /// route's `_ModalScopeStatus`, which Flutter rebuilds when the route stops
  /// being covered. That is what calls this method again, and calling `_load`
  /// from here is what keeps home from offering a set the reader has already
  /// finished. Delete the line and home silently goes stale; there is a test
  /// named for exactly that.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    ModalRoute.of(context);
    _load();
  }

  Future<void> _load() async {
    final read = ++_read;
    final wird = Wird.of(context);
    final waiting = await whatIsWaiting(wird.db, wird.prefs.order);
    if (mounted && read == _read) setState(() => _waiting = waiting);
  }

  Future<void> _pray(StudySet set) async {
    await prayTheSet(context, set);
    if (mounted) await _load();
  }

  /// The index answers with an aya, and the passage with an aya or a word,
  /// rather than by staying open, so home carries it on to the one screen
  /// that reads one.
  Future<void> _open(String route) async {
    final nav = Navigator.of(context);
    final chosen = await nav.pushNamed(route);
    if (chosen is int || chosen is AtWord) {
      await nav.pushNamed(Routes.study, arguments: chosen);
    }
    // A prayer prepared from a door may have answered for the waiting set.
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final n = Nocturne.of(context);
    final waiting = _waiting;
    return Scaffold(
      backgroundColor: n.bg,
      body: waiting == null
          ? const SizedBox.shrink()
          : SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                n.space('6'),
                n.space('2'),
                n.space('6'),
                n.space('8'),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!waiting.started) ...[
                    _welcome(n),
                    SizedBox(height: n.space('6')),
                  ],
                  if (waiting.set case final set?) ...[
                    _next(n, set, waiting),
                    SizedBox(height: n.space('8')),
                    _whereYouAre(n, set, waiting),
                  ] else
                    _finished(n),
                  if (waiting.reading.isNotEmpty) ...[
                    SizedBox(height: n.space('8')),
                    _reading(n, waiting),
                  ],
                  SizedBox(height: n.space('8')),
                  _doors(n),
                ],
              ),
            ),
    );
  }

  Widget _welcome(Nocturne n) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        NocturneKicker(l10n.dashboard_welcomeKicker, tone: KickerTone.accent),
        SizedBox(height: n.space('2')),
        Text(
          l10n.dashboard_welcome,
          style: TextStyle(fontSize: 13.5, height: 1.5, color: n.textAt(0.8)),
        ),
      ],
    );
  }

  /// The waiting set, on a card of its own, with its Arabic: a set is at most
  /// a few dozen words, so the whole of it fits and none is cut off.
  Widget _next(Nocturne n, StudySet set, Waiting waiting) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: EdgeInsets.all(n.space('4')),
      decoration: BoxDecoration(
        color: n.surface,
        borderRadius: BorderRadius.circular(n.radius('md')),
        boxShadow: n.shadow('sm'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NocturneKicker(
            l10n.dashboard_setWaiting(waiting.number),
            tone: KickerTone.accent,
          ),
          SizedBox(height: n.space('2')),
          Text(set.title, style: Theme.of(context).textTheme.displaySmall),
          SizedBox(height: n.space('1')),
          Text(
            set.ayas.first.surahNameAr,
            textDirection: TextDirection.rtl,
            style: TextStyle(
              fontFamily: Nocturne.arabicFamily,
              fontSize: 15,
              color: n.textAt(0.55),
            ),
          ),
          SizedBox(height: n.space('3')),
          Text(
            [
              // The bundled face does not draw the end-of-aya sign around a
              // number, and a ringed number drawn as a widget is reordered
              // where right-to-left lines wrap; the ornate brackets are text,
              // so they stay with the aya they close.
              for (final aya in set.ayas)
                '${aya.words.map((w) => w.text).join(' ')} '
                    '\uFD3F${arabicDigits(aya.number)}\uFD3E',
            ].join(' '),
            key: const Key('set text'),
            textDirection: TextDirection.rtl,
            style: TextStyle(
              fontFamily: Nocturne.arabicFamily,
              fontSize: 22,
              height: 1.9,
              color: n.text,
            ),
          ),
          SizedBox(height: n.space('3')),
          Text(
            '${l10n.dashboard_ayaCount(set.ayas.length)} · '
            '${l10n.dashboard_prayerCount(waiting.prayers)}',
            style: TextStyle(
              fontSize: 11.5,
              height: 1.45,
              color: n.textAt(0.55),
            ),
          ),
          SizedBox(height: n.space('4')),
          // Praying the portion is what the app is for, so it is the one
          // action drawn at the top of the app's first screen. It used to be a
          // button in the reading screen's settings panel.
          NocturneButton(
            key: const Key('pray the set'),
            block: true,
            variant: NocturneButtonVariant.primary,
            onPressed: () => _pray(set),
            child: Text(l10n.dashboard_praySet),
          ),
          NocturneButton(
            key: const Key('read the set'),
            block: true,
            // The set itself, named by its first aya: opened with no aya, the
            // reader goes where it last stood, which need not be this set.
            onPressed: () =>
                Navigator.of(context)
                    .pushNamed(Routes.study, arguments: set.ayas.first.id),
            child: Text(l10n.dashboard_readFirst),
          ),
        ],
      ),
    );
  }

  /// Where the waiting set sits: its sūra's place in the order the reader
  /// walks, and a strip of all 114 lit by how much of each is understood.
  /// The juz is named only in the muṣḥaf's order; in the order of revelation
  /// the walk opens in juz 30, which would read as nearly done.
  Widget _whereYouAre(Nocturne n, StudySet set, Waiting waiting) {
    final l10n = AppLocalizations.of(context)!;
    final first = set.ayas.first;
    final place = waiting.order == ReadingOrder.nuzul
        ? l10n.dashboard_suraNuzul(first.revelationOrder)
        : l10n.dashboard_suraMushaf(first.surahId, juzOf(first.id));
    final understood = waiting.suras.fold(0, (sum, s) => sum + s.understood);
    final caption = understood == 0
        ? null
        : l10n.dashboard_ayasUnderstood(understood, ayasInTheQuran);
    return Semantics(
      button: true,
      label: [place, ?caption].join('. '),
      excludeSemantics: true,
      child: GestureDetector(
        key: const Key('where you are'),
        behavior: HitTestBehavior.opaque,
        onTap: () => _open(Routes.progress),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: NocturneKicker(
                    l10n.dashboard_whereYouAre,
                    tone: KickerTone.accent,
                  ),
                ),
                Icon(Icons.arrow_forward, size: 16, color: n.accent),
              ],
            ),
            SizedBox(height: n.space('2')),
            Text(place, style: Theme.of(context).textTheme.headlineSmall),
            SizedBox(height: n.space('3')),
            SizedBox(
              height: 18,
              child: CustomPaint(
                painter: _Strip(
                  suras: waiting.suras,
                  accent: n.accent,
                  spent: n.color('neutral-800'),
                ),
              ),
            ),
            if (caption != null) ...[
              SizedBox(height: n.space('2')),
              Text(
                caption,
                style: TextStyle(fontSize: 11.5, color: n.textAt(0.55)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// The sūras the reader is part-way through, each opening on the word
  /// they last stood on.
  Widget _reading(Nocturne n, Waiting waiting) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NocturneKicker(l10n.dashboard_continueReading, tone: KickerTone.accent),
        const NocturneRule(fade: 30),
        for (final place in waiting.reading)
          GestureDetector(
            key: ValueKey('continue ${place.wordId}'),
            behavior: HitTestBehavior.opaque,
            onTap: () =>
                Navigator.of(context)
                    .pushNamed(Routes.study, arguments: AtWord(place.wordId)),
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: n.space('3')),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      place.nameEn,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  Text(
                    l10n.reading_ayaOf(
                      ayahOfWord(place.wordId) % 1000,
                      place.ayahCount,
                    ),
                    style: TextStyle(fontSize: 12, color: n.textAt(0.55)),
                  ),
                  SizedBox(width: n.space('2')),
                  Icon(Icons.arrow_forward, size: 16, color: n.accent),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _finished(Nocturne n) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        AppLocalizations.of(context)!.dashboard_allUnderstood,
        style: Theme.of(context).textTheme.displaySmall,
      ),
      SizedBox(height: n.space('2')),
      Text(
        AppLocalizations.of(context)!.dashboard_allUnderstoodWhy,
        style: TextStyle(fontSize: 12, height: 1.45, color: n.textAt(0.55)),
      ),
    ],
  );

  /// The same destinations the drawer lists, on the screen a reader lands on.
  /// The drawer is how you leave a screen; this is how you start.
  Widget _doors(Nocturne n) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NocturneKicker(l10n.dashboard_whereToGo, tone: KickerTone.accent),
        const NocturneRule(fade: 30),
        for (final door in [
          (
            route: Routes.index,
            label: l10n.dashboard_doorIndex,
            why: l10n.dashboard_doorIndexWhy,
          ),
          (
            route: Routes.progress,
            label: l10n.dashboard_doorProgress,
            why: l10n.dashboard_doorProgressWhy,
          ),
          (
            route: Routes.kept,
            label: l10n.dashboard_doorKept,
            why: l10n.dashboard_doorKeptWhy,
          ),
          (
            route: Routes.prepare,
            label: l10n.dashboard_doorPray,
            why: l10n.dashboard_doorPrayWhy,
          ),
        ])
          GestureDetector(
            key: ValueKey('door${door.route}'),
            behavior: HitTestBehavior.opaque,
            onTap: () => _open(door.route),
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: n.space('3')),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          door.label,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        SizedBox(height: n.space('1')),
                        Text(
                          door.why,
                          style: TextStyle(fontSize: 11, color: n.textAt(0.5)),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.arrow_forward, size: 16, color: n.accent),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// The 114 sūras as ticks, in the order the reader walks, each lit by how
/// much of it is understood. The sūra the walk is in stands taller, so it is
/// found by its shape and not by its colour alone.
class _Strip extends CustomPainter {
  const _Strip({
    required this.suras,
    required this.accent,
    required this.spent,
  });

  final List<SuraPassage> suras;
  final Color accent;
  final Color spent;

  @override
  void paint(Canvas canvas, Size size) {
    final pitch = size.width / suras.length;
    final width = math.max(1.0, pitch * 0.6);
    for (var i = 0; i < suras.length; i++) {
      final sura = suras[i];
      final done = sura.fraction;
      final height = sura.current ? size.height : size.height * 0.5;
      // The same light as the ring on 1d: a sūra never opened stays the
      // colour of the track, one only partly understood is the accent held
      // back to how far it got.
      final paint = Paint()
        ..color = sura.current
            ? accent
            : done == 0
            ? spent
            : accent.withValues(alpha: done >= 1 ? 1 : 0.35 + 0.5 * done);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(i * pitch, size.height - height, width, height),
          Radius.circular(width / 2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_Strip old) => old.suras != suras;
}
