import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import 'app.dart';
import 'data/sets.dart';
import 'features/about/about_screen.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/deepdive/deep_dive_screen.dart';
import 'features/index/index_screen.dart';
import 'features/kept/kept_screen.dart';
import 'features/prayer/prayer_screen.dart';
import 'features/progress/progress_screen.dart';
import 'features/root/root_screen.dart';
import 'features/root/root_spine_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/study/study_screen.dart';
import 'shell/wird_shell.dart';
import 'theme/nocturne.dart';

/// The name each screen is pushed by. A screen is built by replacing the file
/// its builder already points at, so no two screens are written into one file.
abstract final class Routes {
  static const dashboard = '/';
  static const study = '/study';
  static const prayer = '/prayer';
  static const root = '/root';
  static const rootSpine = '/root-spine';
  static const deepDive = '/deep-dive';
  static const progress = '/progress';
  static const kept = '/kept';
  static const index = '/index';
  static const settings = '/settings';
  static const about = '/about';
}

/// What screen `1c` is opened on: one aya, with one root lit inside it.
typedef DeepDiveTarget = ({int ayahId, String letters});

typedef ScreenBuilder = Widget Function(Database db, Object? arguments);

// How a reader moves.
//
// The design draws seven tablet frames and no shell — no tab bar, no drawer,
// no home. Every path between them is implicit, which is why the sūra index
// ended up inside a collapsed panel on the reading screen and why starting a
// prayer ended up beside the microphone permission. So the app has a
// conventional shell around the seven: a drawer lists the destinations, and
// the dashboard is home.
//
// dashboard: the app opens here. The set the walk has ready, the act of
//   praying it, and the way into everything else.
// study (1a): the set, reached from the dashboard or the drawer.
//   an underlined word                -> swaps 1a's own root panel, no push
//   the root panel's identity row     -> root (3a), the root of the word just tapped
//   "Constellation"                   -> deepDive (1c), on that aya and that root
//   "Mark set understood"             -> stays on 1a
//   "Pray this set"                   -> prayer (1b), and records it on the way back
// root (3a): back arrow -> back to whoever pushed it; keep icon -> keeps the root.
//            A root with more than 8 derivatives is read as rootSpine (2b) instead;
//            which one opens is the root screen's decision, not the caller's.
// progress (1d): "All 114" -> index, which is what the label has always meant.
// index: a sūra opens its ayas; an aya is POPPED back up the stack rather than
//        pushed onto it, so the reader who asked for it lands on the one
//        reading screen instead of on a second one stacked above the first.
// settings: what the reader sets and forgets. No navigation, and no prayer.
// kept (1e), deepDive (1c), prayer (1b): back -> back to whoever pushed them.
final screens = <String, ScreenBuilder>{
  Routes.dashboard: (db, _) => const DashboardScreen(),
  // The target is how the screen is built on an aya the reader asked for,
  // rather than on the one the walk hands them.
  Routes.study: (db, args) => StudyScreen(db: db, target: args as int?),
  Routes.prayer: (db, args) => PrayerScreen(db: db, set: args! as StudySet),
  Routes.root: (db, args) => RootScreen(db: db, letters: args! as String),
  Routes.rootSpine: (db, args) =>
      RootSpineScreen(db: db, letters: args! as String),
  Routes.deepDive: (db, args) {
    final target = args! as DeepDiveTarget;
    return DeepDiveScreen(
      db: db,
      ayahId: target.ayahId,
      letters: target.letters,
    );
  },
  Routes.progress: (db, _) => ProgressScreen(db: db),
  Routes.kept: (db, _) => KeptScreen(db: db),
  Routes.settings: (db, _) => const SettingsScreen(),
  Routes.about: (db, _) => const AboutScreen(),
  Routes.index: (db, _) => IndexScreen(db: db),
};

/// One place the drawer can send the reader.
typedef Destination = ({String route, String label});

/// The drawer, in the order it lists them: home, the reading, the two ways of
/// finding a place in the text, what has been kept, and then the two screens a
/// reader visits rarely.
const destinations = <Destination>[
  (route: Routes.dashboard, label: 'Home'),
  (route: Routes.study, label: 'The set'),
  (route: Routes.index, label: 'Sūra index'),
  (route: Routes.progress, label: 'Your passage'),
  (route: Routes.kept, label: 'Kept'),
  (route: Routes.settings, label: 'Settings'),
  (route: Routes.about, label: 'Sources'),
];

bool isDestination(String? route) =>
    destinations.any((d) => d.route == route);

/// A destination is drawn inside the shell; a screen the reader pushed into is
/// not.
///
/// The prayer, a root and a constellation carry their own way back and must
/// not offer a drawer. Screen 1b especially: it runs inside the prayer, where
/// there is nothing to navigate to and nothing may be drawn over the aya —
/// which is also why the shell, and only the shell, carries the audio
/// transport. 1b cannot show one because it has no shell to show it in.
Route<void> screenRoute(RouteSettings settings, Database db) {
  final build = screens[settings.name];
  if (build == null) {
    throw ArgumentError.value(
      settings.name,
      'route',
      'no screen is registered under this name',
    );
  }
  return MaterialPageRoute<void>(
    settings: settings,
    builder: (_) {
      final screen = build(db, settings.arguments);
      return isDestination(settings.name)
          ? WirdShell(route: settings.name!, child: screen)
          : screen;
    },
  );
}

/// The app, with the application layer above the navigator: the recitation and
/// the preferences are held here, so they survive every screen that shows them.
Widget wirdApp(Database db, {required Prefs prefs, Recitation? recitation}) =>
    Wird(
      db: db,
      prefs: prefs,
      recitation: recitation ?? Recitation(),
      child: MaterialApp(
        title: 'Wird',
        theme: nocturneTheme(),
        initialRoute: Routes.dashboard,
        onGenerateRoute: (settings) => screenRoute(settings, db),
      ),
    );
