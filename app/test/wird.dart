import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:wird/l10n/app_localizations.dart';
import 'package:wird/app.dart';
import 'package:wird/data/audio.dart';
import 'package:wird/nav.dart';
import 'package:wird/shell/wird_shell.dart';
import 'package:wird/theme/nocturne.dart';

/// A screen inside the application it runs in: one recitation, one set of
/// preferences, and by default a cache that holds nothing and can fetch
/// nothing — a phone that has never been online.
///
/// A screen cannot be pumped on its own any more, and that is the point: the
/// audio and the preferences belong to the app above it rather than to the
/// screen, so a test that mounts a screen without them is testing something
/// the reader never runs.
///
/// [route] puts it inside the shell as well, which a destination needs: the
/// drawer the burger opens is the shell's, and a screen mounted without one
/// has no way out to test.
Future<Widget> wirdAround(
  Database db,
  Widget screen, {
  String? route,
  AudioCache? cache,
  Recitation? recitation,
  RouteFactory? onGenerateRoute,
  /// The locale to draw in. Null follows the test binding's own, which is en.
  Locale? locale,
}) async => Wird(
  db: db,
  prefs: await Prefs.read(db),
  // No cache unless the test hands one over: making a temp directory is real
  // file work, and a widget test body never gets an answer from it. A screen
  // that plays nothing asks for nothing.
  recitation: recitation ?? Recitation(cache: cache),
  child: MaterialApp(
    theme: nocturneTheme(),
    // The delegates the app has, so a screen under test can read a string the
    // way it will in the app. Without them `AppLocalizations.of(context)` is
    // null and every localised screen throws under test but not in the app,
    // which is the worst way round for this to break.
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: locale,
    onGenerateRoute:
        onGenerateRoute ?? (settings) => screenRoute(settings, db),
    home: route == null
        ? screen
        : WirdShell(
            route: route,
            bar: shellDrawsTheBar(route),
            child: screen,
          ),
  ),
);

/// The whole app, from its first route, with a cache the test controls.
Future<Widget> wholeApp(
  Database db, {
  AudioCache? cache,
  Recitation? recitation,
}) async => wirdApp(
  db,
  prefs: await Prefs.read(db),
  recitation: recitation ?? Recitation(cache: cache),
);

/// Sizes the view to the phone the app is judged on before pumping.
Future<void> pumpPhone(WidgetTester tester, Widget app) async {
  tester.view.physicalSize = const Size(402, 874);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  unmountAtTearDown(tester);
  await tester.pumpWidget(app);
  await tester.pumpAndSettle();
}

/// Takes the app down before the test ends, so what a screen writes as it is
/// disposed lands in this test.
///
/// The reading screen saves where the reader stood when it is disposed. Left
/// to the framework, the screen is disposed after the test body and the write
/// lands in whichever test runs next — after that test's setUp emptied the
/// database — so the next reader opens where the last test left off.
void unmountAtTearDown(WidgetTester tester) => addTearDown(() async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
});

/// Opens a destination the way a reader does: the burger, then the drawer's
/// own row for it. Scoped to the drawer, because home names the same places
/// on its own face and a bare `find.text` would hit either.
Future<void> goTo(WidgetTester tester, String label) async {
  await tester.tap(find.byIcon(Icons.menu));
  await tester.pumpAndSettle();
  await tester.tap(
    find.descendant(of: find.byType(WirdDrawer), matching: find.text(label)),
  );
  await tester.pumpAndSettle();
}
