import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:wird/main.dart' as app;
import 'package:wird/shell/wird_shell.dart';

/// What the resolved e2e target can do. A physical iPhone is the only place
/// the microphone and audio routing are real; the macOS desktop target is the
/// safety net and has no system browser to hand an OIDC redirect to.
const _capabilities = <String, Set<String>>{
  'iphone': {'system-browser', 'microphone'},
  'simulator': {'system-browser'},
  'macos': <String>{},
};

const _target = String.fromEnvironment('WIRD_TARGET', defaultValue: 'macos');

/// scripts/qa.sh reads these lines out of the run and copies them into
/// qa-report.json, so a journey that did not run is counted rather than
/// read as a pass. The gate fails once the same journey has been skipped for
/// two phases running.
void _report(String name, String status, String reason) {
  // ignore: avoid_print
  print(
    'WIRD-JOURNEY ${jsonEncode({'journey': name, 'status': status, 'reason': reason})}',
  );
}

/// Thrown by a journey that cannot run against the app as it stands — a
/// control that is drawn but not yet wired. The reason names what it waits on.
class NotWiredYet implements Exception {
  NotWiredYet(this.reason);

  final String reason;
}

/// One e2e journey: a way the product fails, not "the app launches".
///
/// [needs] is what the journey cannot run without; the runner skips loudly
/// when the resolved target does not have it.
void journey(
  String name, {
  List<String> needs = const [],
  required Future<void> Function(WidgetTester tester) body,
}) {
  testWidgets(name, (tester) async {
    final has = _capabilities[_target] ?? const <String>{};
    final missing = needs.where((n) => !has.contains(n)).toList();
    if (missing.isNotEmpty) {
      _report(name, 'skip', 'the $_target target has no ${missing.join(', ')}');
      return;
    }
    try {
      await body(tester);
    } on NotWiredYet catch (e) {
      _report(name, 'skip', e.reason);
      return;
    }
    _report(name, 'pass', '');
  });
}

Future<String> get _dbPath async => '${await getDatabasesPath()}/wird.db';

/// Starts the app the way a fresh install does: no database file, so this
/// launch is the one that copies the bundled corpus out and the walk starts
/// at the first aya of the revelation order.
Future<void> launchFresh(WidgetTester tester) async {
  await deleteDatabase(await _dbPath);
  app.main();
  // runApp locks pointer events until its warm-up frame lands, so settling
  // first is what makes the taps below reach the screen at all.
  await tester.pumpAndSettle();
  await openTheSet(tester, 'the first set');
}

/// Starts the app again over the database the previous launch left behind.
Future<void> relaunch(WidgetTester tester) async {
  app.main();
  await tester.pumpAndSettle();
  await openTheSet(tester, 'the set');
}

/// The app opens on its dashboard, so every journey about the reading starts
/// by walking through the drawer the way a reader does.
Future<void> openTheSet(WidgetTester tester, String what) async {
  await waitFor(
    tester,
    () => find.byIcon(Icons.menu).evaluate().isNotEmpty,
    'the way into the app',
  );
  await goThroughTheDrawer(tester, 'The set');
  await waitFor(tester, () => wordsOnScreen(tester).isNotEmpty, what);
}

/// Opens the drawer and goes to a destination by name.
Future<void> goThroughTheDrawer(WidgetTester tester, String label) async {
  await tester.tap(find.byIcon(Icons.menu));
  await tester.pumpAndSettle();
  await tester.tap(
    find.descendant(of: find.byType(WirdDrawer), matching: find.text(label)),
  );
  await tester.pumpAndSettle();
}

/// Pumps until [ready], or fails naming what never arrived.
///
/// pumpAndSettle is not enough here: a cold start copies 24 MB out of the
/// bundle and then queries it, and neither of those schedules a frame, so
/// settling returns to a screen that is still empty.
Future<void> waitFor(
  WidgetTester tester,
  bool Function() ready,
  String what, {
  Duration timeout = const Duration(seconds: 60),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!ready()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('$what never arrived, after ${timeout.inSeconds} seconds of waiting');
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// The corpus the app is reading, opened beside it so a journey can assert
/// the screen shows what the corpus actually records rather than a string
/// typed into the test.
Future<Database> openCorpusBeside() async => openReadOnlyDatabase(await _dbPath);

/// The corpus ids of the words drawn on screen. Each word tile is keyed by
/// its id, so this identifies the set the reader is looking at without
/// depending on any of the screen's wording.
Set<int> wordsOnScreen(WidgetTester tester) => {
  for (final e in find.byWidgetPredicate((w) => w.key is ValueKey<int>).evaluate())
    (e.widget.key! as ValueKey<int>).value,
};

Set<int> ayasOnScreen(WidgetTester tester) => {
  for (final id in wordsOnScreen(tester)) id ~/ 1000,
};

/// The root the corpus gives a word, spelled the way the root panel prints
/// it. Null for the particles and proper nouns that carry none.
Future<String?> rootDisplayOf(Database corpus, int wordId) async {
  final word = await corpus.query(
    'words',
    columns: ['root_letters'],
    where: 'id = ?',
    whereArgs: [wordId],
  );
  final letters = word.single['root_letters'] as String?;
  if (letters == null || letters.isEmpty) return null;
  final root = await corpus.query(
    'roots',
    columns: ['display'],
    where: 'letters = ?',
    whereArgs: [letters],
  );
  return root.isEmpty ? null : root.single['display'] as String;
}

/// A word to tap: one that carries a root the panel is not already showing —
/// so the tap is a visible change rather than a no-op — and that sits where a
/// reader could actually put a finger on it.
Future<({int id, String display})> aWordToTap(
  WidgetTester tester,
  Database corpus,
) async {
  final ids = wordsOnScreen(tester).toList()..sort();
  final showing = await _firstRootDisplay(tester, corpus);
  for (final id in ids) {
    final display = await rootDisplayOf(corpus, id);
    if (display == null || display == showing) continue;
    final tile = find.byKey(ValueKey(id));
    final box = tester.renderObject<RenderBox>(tile);
    if (tester.hitTestOnBinding(tester.getCenter(tile)).path.any((e) => e.target == box)) {
      return (id: id, display: display);
    }
  }
  throw StateError(
    'this set offers the reader no second root to open: of the ${ids.length} '
    'words on screen, none carries a root other than the one already in the '
    'panel and sits where it can be tapped',
  );
}

/// The root the screen opens on: the first word of the set that carries one.
Future<String?> _firstRootDisplay(WidgetTester tester, Database corpus) async {
  for (final id in wordsOnScreen(tester).toList()..sort()) {
    final display = await rootDisplayOf(corpus, id);
    if (display != null) return display;
  }
  return null;
}

/// The "Mark set understood" control, refused when it is drawn but dead.
Finder markSetUnderstood(WidgetTester tester) {
  final finder = find.widgetWithText(GestureDetector, 'Mark set understood');
  final live = finder
      .evaluate()
      .map((e) => e.widget as GestureDetector)
      .where((g) => g.onTap != null);
  if (live.isEmpty) {
    throw NotWiredYet(
      'the "Mark set understood" button is drawn but has no action behind it, '
      'so a set cannot be completed and the next one cannot arrive; waiting on '
      'the phase 4 change to app/lib/features/study/ that gives it one',
    );
  }
  return find.byWidget(live.first);
}

/// Marks the set, then asks for the next one.
///
/// Marking leaves the reader on the set they marked, so that the bars they
/// just filled are on screen in front of them. Walking on is a second press,
/// the way it is for a reader.
Future<void> finishSet(WidgetTester tester) async {
  await tester.tap(markSetUnderstood(tester));
  await waitFor(
    tester,
    () => find.text('Next set').evaluate().isNotEmpty,
    'the way on to the next set, after the one before it was marked',
  );
  await tester.tap(find.text('Next set'));
}

/// A prayer happens in a room with no signal. Nothing the app draws may spin
/// or apologise, at any point in the journey.
void expectNoSpinnerAndNoApology(WidgetTester tester, String moment) {
  expect(
    find.bySubtype<ProgressIndicator>(skipOffstage: false),
    findsNothing,
    reason: 'a spinner is on screen $moment',
  );
  expect(
    find.byType(AlertDialog, skipOffstage: false),
    findsNothing,
    reason: 'a dialog is on screen $moment',
  );
  expect(
    find.byType(SnackBar, skipOffstage: false),
    findsNothing,
    reason: 'a snack bar is on screen $moment',
  );
  const apologies = [
    'would not open',
    'try again',
    'something went wrong',
    'no connection',
    'check your connection',
    'unable to',
  ];
  for (final text in tester.widgetList<Text>(find.byType(Text, skipOffstage: false))) {
    final shown = (text.data ?? '').toLowerCase();
    for (final apology in apologies) {
      expect(
        shown.contains(apology),
        isFalse,
        reason: 'the screen says "${text.data}" $moment',
      );
    }
  }
}

/// Denies every socket the app can reach through dart:io for the duration of
/// [body], which is as close to switching the radio off as a simulator gets.
Future<void> withNetworkDenied(Future<void> Function() body) async {
  final previous = HttpOverrides.current;
  HttpOverrides.global = _NoNetwork();
  try {
    await body();
  } finally {
    HttpOverrides.global = previous;
  }
}

class _NoNetwork extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _DeniedClient();
}

class _DeniedClient implements HttpClient {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw const SocketException('the radio is off for this journey');
}
