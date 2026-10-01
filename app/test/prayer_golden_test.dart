// Rendered on macOS: other platforms draw a few pixels differently, so CI
// excludes these (`--exclude-tags golden`) and the Mac gate runs them.
@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wird/l10n/app_localizations.dart';
import 'package:wird/features/prayer/prayer_cursor.dart';
import 'package:wird/features/prayer/prayer_plan.dart';
import 'package:wird/features/prayer/prayer_screen.dart';
import 'package:wird/theme/nocturne.dart';

import 'corpus.dart';
import 'features/prayer/sets.dart';
import 'fonts.dart';

Future<void> _heldOpen({required bool enable}) async {}

void main() {
  late Database db;

  setUpAll(loadBundledFonts);
  setUp(() async {
    db = await testCorpus();
  });

  testWidgets('screen 1b drifts away from the design in a way no behaviour '
      'test can see: type, spacing, or the layout of the prayer', (
    tester,
  ) async {
    final fatiha = (await setOf(db, [
      for (var a = 1; a <= 7; a++) 1000 + a,
    ])).ayas;
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: nocturneTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: PrayerScreen(
          db: db,
          plan: PrayerPlan(
            preset: PrayerPreset.maghrib,
            rakahs: 3,
            first: await alAsr(db),
          ),
          fatiha: fatiha,
          // The design's own frame: Maghrib's first rakʿah, a few words into
          // Al-Fātiḥa's fourth aya. The cursor is pinned and nothing moves it
          // — no voice, no pace — so the frame is the same every run.
          cursor: PrayerCursor(42, at: 11),
          prefs: (
            preset: 'maghrib',
            rakahs: 3,
            voice: false,
            pace: false,
            wpm: 40,
            gloss: true,
            around: true,
            arabicSize: 52,
          ),
          wakelock: _heldOpen,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(PrayerScreen),
      matchesGoldenFile('goldens/prayer.png'),
    );
  });
}
