import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import '../../app.dart';
import '../../data/db.dart';
import '../../data/root_repo.dart' show ayahOfWord, surahOfWord;
import '../../data/sets.dart';
import '../../l10n/app_localizations.dart';
import '../../nav.dart';
import '../../theme/nocturne.dart';
import '../progress/passage.dart';
import '../study/word_row.dart' show arabicDigits;
import '../../widgets/nocturne_button.dart';
import '../../widgets/nocturne_kicker.dart';
import '../../widgets/nocturne_rule.dart';

/// What the walk has ready, and the one sūra the reader is reading outside it.
typedef Waiting = ({
  StudySet? set,
  int number,
  int prayers,
  ReadingPlace? reading,
});

Future<Waiting> whatIsWaiting(Database db, ReadingOrder order) async {
  final set = await nextSet(db, order);
  final here = set?.ayas.first.surahId;
  // A sūra the walk has already been through is finished, not open: the walk
  // leaves a sūra only once all of it is understood. Without this the one
  // line below would point at the set the reader just closed.
  final finished = {
    for (final s in await suraPassages(db, here))
      if (s.understood >= s.ayahCount) s.id,
  };
  final places = await readingPlaces(db, limit: 3, except: here);
  return (
    set: set,
    // The sets already finished, plus the one being read. It comes from the
    // walk rather than from counting rows, because the rows record sets
    // *prayed* and a set can be prayed without ever being understood.
    number: await setsUnderstood(db, order) + 1,
    prayers: set == null ? 0 : await prayersOnSet(db, set.id),
    // The walk's own sūra is already named by the set; listing it again as a
    // place to continue would be the same place twice.
    reading: places
        .where((p) => !finished.contains(surahOfWord(p.wordId)))
        .firstOrNull,
  );
}

/// Home.
///
/// It is the way IN, with few doors (ADR 0034): the set the walk has ready —
/// read first, or prayed — one sūra the reader is reading outside the walk,
/// and the ways to any sūra and to a prayer of one's own. Where the reader
/// stands lives on 1d, reached from the drawer; what a set is was said once,
/// on the setup screen.
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
                  if (waiting.set case final set?)
                    _next(n, set, waiting)
                  else
                    _finished(n),
                  if (waiting.reading case final place?) ...[
                    SizedBox(height: n.space('6')),
                    _reading(n, place),
                  ],
                  SizedBox(height: n.space('8')),
                  _doors(n),
                ],
              ),
            ),
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
          // Reading leads and praying follows it (ADR 0034): the set is
          // understood before it is prayed, so Read is the primary and Pray
          // the quieter way straight to the prayer.
          NocturneButton(
            key: const Key('read the set'),
            block: true,
            variant: NocturneButtonVariant.primary,
            // The set itself, named by its first aya: opened with no aya, the
            // reader goes where it last stood, which need not be this set.
            onPressed: () =>
                Navigator.of(context)
                    .pushNamed(Routes.study, arguments: set.ayas.first.id),
            child: Text(l10n.dashboard_readSet),
          ),
          NocturneButton(
            key: const Key('pray the set'),
            block: true,
            variant: NocturneButtonVariant.ghost,
            onPressed: () => _pray(set),
            child: Text(l10n.dashboard_praySet),
          ),
        ],
      ),
    );
  }

  /// The one sūra the reader is part-way through outside the walk, opening on
  /// the word they last stood on.
  Widget _reading(Nocturne n, ReadingPlace place) {
    final l10n = AppLocalizations.of(context)!;
    final aya = ayahOfWord(place.wordId);
    return GestureDetector(
      key: ValueKey('continue ${place.wordId}'),
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(
        context,
      ).pushNamed(Routes.study, arguments: AtWord(place.wordId)),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: n.space('3')),
        child: Row(
          children: [
            Expanded(
              child: Text(
                l10n.dashboard_continue(
                  place.nameEn,
                  '${aya ~/ 1000}:${aya % 1000}',
                ),
                style: TextStyle(fontSize: 14, color: n.text),
              ),
            ),
            Icon(Icons.arrow_forward, size: 16, color: n.accent),
          ],
        ),
      ),
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

  /// The two ways in besides the walk: any sūra, and a prayer of one's own.
  /// Everything else is a place a reader returns to, so it is in the drawer.
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
