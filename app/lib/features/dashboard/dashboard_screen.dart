import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import '../../app.dart';
import '../../data/db.dart';
import '../../data/sets.dart';
import '../../nav.dart';
import '../../theme/nocturne.dart';
import '../../widgets/nocturne_button.dart';
import '../../widgets/nocturne_rule.dart';

/// What the walk has ready, and nothing the reader has to work out.
typedef Waiting = ({StudySet? set, int number, int prayers});

Future<Waiting> whatIsWaiting(Database db, ReadingOrder order) async {
  final set = await nextSet(db, order);
  return (
    set: set,
    // The sets already finished, plus the one being read. It comes from the
    // walk rather than from counting rows, because the rows record sets
    // *prayed* and a set can be prayed without ever being understood.
    number: await setsUnderstood(db, order) + 1,
    prayers: set == null ? 0 : await prayersOnSet(db, set.id),
  );
}

/// Home.
///
/// Screen 1d already reports on the walk, and this is deliberately not a
/// second one: it is the way IN. It answers one question — what is waiting and
/// what can I do about it — and hands the reader on to the screens that study
/// the thing. 1d keeps the ring, the juz, the sūra rows and the roots.
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

  /// The index answers with an aya rather than by staying open, so home
  /// carries it on to the one screen that reads one.
  Future<void> _open(String route) async {
    final nav = Navigator.of(context);
    final chosen = await nav.pushNamed(route);
    if (chosen is int) await nav.pushNamed(Routes.study, arguments: chosen);
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
                  SizedBox(height: n.space('8')),
                  _doors(n),
                ],
              ),
            ),
    );
  }

  Widget _next(Nocturne n, StudySet set, Waiting waiting) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'SET ${waiting.number} · WAITING',
        style: TextStyle(
          fontSize: 10,
          height: 1.2,
          letterSpacing: 0.11 * 10,
          color: n.accent,
        ),
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
        '${_ayas(set.ayas.length)} · ${_prayers(waiting.prayers)}',
        style: TextStyle(fontSize: 11.5, height: 1.45, color: n.textAt(0.55)),
      ),
      SizedBox(height: n.space('4')),
      // Praying the portion is what the app is for, so it is the one action
      // drawn at the top of the app's first screen. It used to be a button in
      // the reading screen's settings panel.
      NocturneButton(
        key: const Key('pray the set'),
        block: true,
        variant: NocturneButtonVariant.primary,
        onPressed: () => _pray(set),
        child: const Text('Pray this set'),
      ),
      NocturneButton(
        key: const Key('read the set'),
        block: true,
        onPressed: () => _open(Routes.study),
        child: const Text('Read it first'),
      ),
    ],
  );

  Widget _finished(Nocturne n) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Every aya is understood.',
        style: Theme.of(context).textTheme.displaySmall,
      ),
      SizedBox(height: n.space('2')),
      Text(
        'There is nothing left to serve. The index opens any sūra again.',
        style: TextStyle(fontSize: 12, height: 1.45, color: n.textAt(0.55)),
      ),
    ],
  );

  /// The same destinations the drawer lists, on the screen a reader lands on.
  /// The drawer is how you leave a screen; this is how you start.
  Widget _doors(Nocturne n) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'WHERE TO GO',
        style: TextStyle(
          fontSize: 10,
          height: 1.2,
          letterSpacing: 0.11 * 10,
          color: n.accent,
        ),
      ),
      const NocturneRule(fade: 30),
      for (final door in const [
        (route: Routes.index, label: 'Sūra index', why: 'Open any aya you want'),
        (
          route: Routes.progress,
          label: 'Your passage',
          why: 'How much you have understood',
        ),
        (route: Routes.kept, label: 'Kept', why: 'The ayas and roots you saved'),
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

String _ayas(int count) => count == 1 ? '1 aya' : '$count ayas';

String _prayers(int count) => switch (count) {
  0 => 'no prayer on it yet',
  1 => 'prayed once',
  2 => 'prayed twice',
  _ => 'prayed $count times',
};
