import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:wird/features/root/root_screen.dart';
import 'package:wird/features/root/root_sections.dart';
import 'package:wird/features/root/root_spine_screen.dart';
import 'package:wird/l10n/app_localizations.dart';
import 'package:wird/theme/nocturne.dart';

import 'corpus.dart';
import 'fonts.dart';

/// ʿ-q-l, five derivatives — the ring exactly as the design draws it.
const onTheDial = 'عقل';

/// ṣ-b-r, thirty-eight derivatives, and the root the design itself wrote its
/// placeholder prose about.
const onTheSpine = 'صبر';

void main() {
  late Database db;

  setUpAll(loadBundledFonts);
  setUp(() async => db = await testCorpus());

  Future<void> phone(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: nocturneTheme(),
        // Both root screens read their strings now, and without the delegates
        // `AppLocalizations.of` is null and every one of them throws. The
        // raster is the English one either way: no locale is set, so these
        // goldens are unmoved by the sweep.
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: screen,
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Brings the sections below the fold into the raster.
  ///
  /// A golden of the first screenful is a golden of the first screenful: a
  /// `ListView` never builds what is under it, so the sections these tests name
  /// could be deleted outright without moving a pixel — and were. The parsing
  /// and the provenance under it are both down here.
  Future<void> toTheSections(WidgetTester tester) async {
    await tester.scrollUntilVisible(
      find.byType(IrabSection),
      300,
      scrollable: find.descendant(
        of: find.byType(ListView),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('screen 3a drifts away from the design in a way no behaviour '
      'test can see: the ring, the card under it, or the sections below', (
    tester,
  ) async {
    await phone(tester, RootScreen(db: db, letters: onTheDial));
    await expectLater(
      find.byType(RootScreen),
      matchesGoldenFile('goldens/root.png'),
    );

    await toTheSections(tester);
    await expectLater(
      find.byType(RootScreen),
      matchesGoldenFile('goldens/root_sections.png'),
    );
  });

  testWidgets('screen 2b drifts away from the design in a way no behaviour '
      'test can see: the header, the spine, or the sources under it', (
    tester,
  ) async {
    await phone(tester, RootSpineScreen(db: db, letters: onTheSpine));
    await expectLater(
      find.byType(RootSpineScreen),
      matchesGoldenFile('goldens/root_spine.png'),
    );

    await toTheSections(tester);
    await expectLater(
      find.byType(RootSpineScreen),
      matchesGoldenFile('goldens/root_spine_sections.png'),
    );
  });
}
