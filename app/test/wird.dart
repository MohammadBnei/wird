import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:wird/app.dart';
import 'package:wird/data/audio.dart';
import 'package:wird/nav.dart';
import 'package:wird/theme/nocturne.dart';

/// A screen inside the application it runs in: one recitation, one set of
/// preferences, and by default a cache that holds nothing and can fetch
/// nothing — a phone that has never been online.
///
/// A screen cannot be pumped on its own any more, and that is the point: the
/// audio and the preferences belong to the app above it rather than to the
/// screen, so a test that mounts a screen without them is testing something
/// the reader never runs.
Future<Widget> wirdAround(
  Database db,
  Widget screen, {
  AudioCache? cache,
  Recitation? recitation,
  RouteFactory? onGenerateRoute,
}) async => Wird(
  db: db,
  prefs: await Prefs.read(db),
  // No cache unless the test hands one over: making a temp directory is real
  // file work, and a widget test body never gets an answer from it. A screen
  // that plays nothing asks for nothing.
  recitation: recitation ?? Recitation(cache: cache),
  child: MaterialApp(
    theme: nocturneTheme(),
    onGenerateRoute:
        onGenerateRoute ?? (settings) => screenRoute(settings, db),
    home: screen,
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
  await tester.pumpWidget(app);
  await tester.pumpAndSettle();
}
