import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import 'app.dart';
import 'l10n/app_localizations.dart';
import 'data/flush.dart';
import 'data/sets.dart';
import 'features/about/about_screen.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/deepdive/deep_dive_screen.dart';
import 'features/index/index_screen.dart';
import 'features/kept/kept_screen.dart';
import 'features/prayer/prepare_screen.dart';
import 'features/progress/progress_screen.dart';
import 'features/report/report_screen.dart';
import 'features/root/root_screen.dart';
import 'features/root/root_spine_screen.dart';
import 'features/study/study_screen.dart';
import 'shell/wird_shell.dart';
import 'theme/nocturne.dart';

/// The name each screen is pushed by. A screen is built by replacing the file
/// its builder already points at, so no two screens are written into one file.
abstract final class Routes {
  static const dashboard = '/';
  static const study = '/study';
  static const prepare = '/prepare';
  static const root = '/root';
  static const rootSpine = '/root-spine';
  static const deepDive = '/deep-dive';
  static const progress = '/progress';
  static const kept = '/kept';
  static const index = '/index';
  static const settings = '/settings';
  static const report = '/report';
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
//   "Pray this set"                   -> prepare, which opens the prayer (1b) and
//                                        records it on the way back
// root (3a): back arrow -> back to whoever pushed it; keep icon -> keeps the root.
//            A root with more than 8 derivatives is read as rootSpine (2b) instead;
//            which one opens is the root screen's decision, not the caller's.
// progress (1d): "All 114" -> index, which is what the label has always meant.
// index: a sūra opens its ayas; an aya is POPPED back up the stack rather than
//        pushed onto it, so the reader who asked for it lands on the one
//        reading screen instead of on a second one stacked above the first.
// settings: what the reader sets and forgets. No navigation, and no prayer. A
//   sheet over the current screen (showSettings), not a route: the drawer keeps
//   its row, and the reader keeps their screen.
// report: a bug, a request or an improvement, carrying the screen the reader
//   opened it from. One way: it queues and nothing comes back.
// kept (1e), deepDive (1c), prepare: back -> back to whoever pushed them. The
//   prayer (1b) is pushed by prepare alone, and pops back to it.
final screens = <String, ScreenBuilder>{
  Routes.dashboard: (db, _) => const DashboardScreen(),
  // The target is how the screen is built on an aya the reader asked for,
  // rather than on where they last stood; an AtWord opens it on one word.
  Routes.study: (db, args) => args is AtWord
      ? StudyScreen(db: db, word: args.wordId)
      : StudyScreen(db: db, target: args as int?),
  // The set the reader was holding, or nothing from the dashboard's door,
  // where the next unread set takes its place.
  Routes.prepare: (db, args) => PrepareScreen(db: db, from: args as StudySet?),
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
  // The argument is the screen the reader was on, so the report carries it
  // without anybody having to type "I was on the index".
  Routes.report: (db, args) =>
      ReportScreen(db: db, from: args as String? ?? Routes.dashboard),
  Routes.about: (db, _) => const AboutScreen(),
  Routes.index: (db, _) => IndexScreen(db: db),
};

/// One place the drawer can send the reader, and its row's words in the
/// reader's language.
typedef Destination = ({String route, String Function(AppLocalizations) label});

/// The drawer, in the order it lists them: home, the reading, the two ways of
/// finding a place in the text, what has been kept, and then the two screens a
/// reader visits rarely. A row shares its key with the screen's own heading
/// wherever the two say the same thing.
final destinations = <Destination>[
  (route: Routes.dashboard, label: (l) => l.nav_home),
  (route: Routes.study, label: (l) => l.nav_theSet),
  (route: Routes.index, label: (l) => l.dashboard_doorIndex),
  (route: Routes.progress, label: (l) => l.progress_title),
  (route: Routes.kept, label: (l) => l.kept_title),
  (route: Routes.settings, label: (l) => l.settingsTitle),
  (route: Routes.report, label: (l) => l.report_title),
  (route: Routes.about, label: (l) => l.nav_sources),
];

bool isDestination(String? route) => destinations.any((d) => d.route == route);

/// Whether the shell draws the bar's row over this destination, or the screen
/// draws it itself.
///
/// The reading screen draws it. What that row has to say — the sūra, which of
/// its ayas, whether the chrome is folded, and the act the reading is for — is
/// more than a shell can know, and a shell row above the screen's own was a
/// second line of chrome between the reader and the first aya.
bool shellDrawsTheBar(String route) => route != Routes.study;

/// A destination opened as a step inside another screen rather than chosen in
/// the drawer.
///
/// The same screen is both: the sūra index chosen in the drawer is where the
/// reader is, and the one opened from "All 114" is a step they took and have
/// to come back from. The difference rides on the route, so the screen never
/// has to know which way it was entered — it drew its own way back before,
/// and inside the shell that put a second navigation control under the first.
/// Opens the reading screen on one word rather than at the start of an aya:
/// where the reader stood in a sūra they are part-way through.
final class AtWord {
  const AtWord(this.wordId);

  final int wordId;
}

final class AStepFrom {
  const AStepFrom([this.arguments]);

  /// What the screen itself is opened on, untouched.
  final Object? arguments;
}

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
  final step = settings.arguments is AStepFrom;
  final arguments = step
      ? (settings.arguments! as AStepFrom).arguments
      : settings.arguments;
  return MaterialPageRoute<void>(
    settings: settings,
    builder: (_) {
      final screen = build(db, arguments);
      return isDestination(settings.name)
          ? WirdShell(
              route: settings.name!,
              step: step,
              bar: shellDrawsTheBar(settings.name!),
              child: screen,
            )
          : screen;
    },
  );
}

/// The app, with the application layer above the navigator: the recitation and
/// the preferences are held here, so they survive every screen that shows them.
///
/// The flusher is held the same way and for the same reason — it is the app
/// that comes back to the foreground, not a screen — and a build without one
/// is a test or the gallery, which have no server to reach.
Widget wirdApp(
  Database db, {
  required Prefs prefs,
  Recitation? recitation,
  Flusher? flusher,
}) => Wird(
  db: db,
  prefs: prefs,
  recitation: recitation ?? Recitation(tuning: prefs.playback),
  child: Flushing(
    flusher: flusher,
    // Rebuilt when the language moves and at no other time. It is the one
    // preference that rebuilds the whole tree — every screen has to come back
    // in the new language, not just the one that was open — and listening to
    // Prefs itself would redraw all of them once per frame of the Arabic-size
    // drag.
    child: ValueListenableBuilder<Locale?>(
      valueListenable: prefs.locale,
      builder: (context, locale, _) => MaterialApp(
        title: 'Wird',
        theme: nocturneTheme(),
        // The reader's own language: what they picked, and their phone's until
        // they pick. Null is MaterialApp's own word for the second, so no
        // choice stays one state rather than a stored word meaning "no word".
        //
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        initialRoute: Routes.dashboard,
        onGenerateRoute: (settings) => screenRoute(settings, db),
      ),
    ),
  ),
);
