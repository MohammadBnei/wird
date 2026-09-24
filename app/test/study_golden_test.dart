import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wird/data/audio.dart';
import 'package:wird/features/study/study_screen.dart';
import 'package:wird/nav.dart';
import 'package:wird/shell/wird_shell.dart';

import 'corpus.dart';
import 'fonts.dart';
import 'offline.dart';
import 'wird.dart';

void main() {
  late Database db;
  late AudioCache audio;

  setUpAll(loadBundledFonts);
  // Opening the corpus and making the cache directory are real file work,
  // which never completes inside the fake-async zone a widget test body runs
  // in.
  setUp(() async {
    db = await testCorpus();
    audio = await emptyCache();
  });

  testWidgets('screen 1a drifts away from the design in a way no behaviour '
      'test can see: type, spacing, or the layout of the set', (tester) async {
    // No recitation on disk and no network: the golden captures the screen a
    // phone shows before anything has been downloaded.
    await pumpPhone(
      tester,
      await wirdAround(
        db,
        StudyScreen(db: db),
        route: Routes.study,
        cache: audio,
      ),
    );

    await expectLater(
      find.byType(WirdShell),
      matchesGoldenFile('goldens/study.png'),
    );
  });

  testWidgets('the chrome the reader unfolds drifts away from the design: the '
      'masthead over the set, or the root under it', (tester) async {
    await pumpPhone(
      tester,
      await wirdAround(
        db,
        StudyScreen(db: db),
        route: Routes.study,
        cache: audio,
      ),
    );
    await tester.tap(find.byKey(const Key('toggle header')));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(WirdShell),
      matchesGoldenFile('goldens/study_unfolded.png'),
    );
  });

  testWidgets('the folded root panel drifts: the root it still names, or the '
      'act it still carries', (tester) async {
    await pumpPhone(
      tester,
      await wirdAround(
        db,
        StudyScreen(db: db),
        route: Routes.study,
        cache: audio,
      ),
    );
    await tester.tap(find.byKey(const Key('toggle root panel')));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(WirdShell),
      matchesGoldenFile('goldens/study_folded.png'),
    );
  });
}
