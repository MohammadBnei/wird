import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import 'data/sets.dart';
import 'features/about/about_screen.dart';
import 'features/deepdive/deep_dive_screen.dart';
import 'features/kept/kept_screen.dart';
import 'features/prayer/prayer_screen.dart';
import 'features/progress/progress_screen.dart';
import 'features/root/root_screen.dart';
import 'features/root/root_spine_screen.dart';
import 'features/study/study_screen.dart';
import 'theme/nocturne.dart';

/// The name each screen is pushed by. A screen is built by replacing the file
/// its builder already points at, so no two screens are written into one file.
abstract final class Routes {
  static const study = '/';
  static const prayer = '/prayer';
  static const root = '/root';
  static const rootSpine = '/root-spine';
  static const deepDive = '/deep-dive';
  static const progress = '/progress';
  static const kept = '/kept';
  static const about = '/about';
}

/// What screen `1c` is opened on: one aya, with one root lit inside it.
typedef DeepDiveTarget = ({int ayahId, String letters});

typedef ScreenBuilder = Widget Function(Database db, Object? arguments);

// How a reader moves. Read off docs/design/prayer-app-screens.html, element by
// element, rather than invented — and the design draws no tab bar, so there is
// none.
//
// study (1a) is home, and it is the only screen the app launches into.
//   an underlined word                -> swaps 1a's own root panel, no push
//   the root panel's identity row     -> root (3a), the root of the word just tapped
//   "Open constellation"              -> deepDive (1c), on that aya and that root
//   "Mark set understood"             -> stays on 1a
//   the bookmark icon                 -> keeps the set. The design gives it no
//                                        destination, so it leads nowhere here either
//   the settings icon                 -> 1a's settings panel, which already holds the
//                                        controls the design does not draw: the reading
//                                        order, the microphone, the Arabic size and
//                                        "Sources and licences". prayer (1b), progress
//                                        (1d) and kept (1e) are reached from there too,
//                                        because no design element anywhere leads to
//                                        them and 1a's chrome is fixed by its
//                                        acceptance row
// root (3a): back arrow -> back to whoever pushed it; keep icon -> keeps the root.
//            A root with more than 8 derivatives is read as rootSpine (2b) instead;
//            which one opens is the root screen's decision, not the caller's.
// rootSpine (2b): back arrow -> back to whoever pushed it; keep icon -> keeps the root.
// progress (1d): "All 114" -> kept (1e). The design's own link points there.
// kept (1e), deepDive (1c): back -> back to whoever pushed them.
final screens = <String, ScreenBuilder>{
  Routes.study: (db, _) => StudyScreen(db: db),
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
  Routes.about: (db, _) => const AboutScreen(),
};

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
    builder: (_) => build(db, settings.arguments),
  );
}

MaterialApp wirdApp(Database db) => MaterialApp(
  title: 'Wird',
  theme: nocturneTheme(),
  initialRoute: Routes.study,
  onGenerateRoute: (settings) => screenRoute(settings, db),
);
