import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wird/data/audio.dart';
import 'package:wird/features/dashboard/dashboard_screen.dart';
import 'package:wird/features/settings/settings_screen.dart';
import 'package:wird/nav.dart';
import 'package:wird/shell/wird_shell.dart';

import 'corpus.dart';
import 'fonts.dart';
import 'offline.dart';
import 'wird.dart';

void main() {
  late Database db;
  late AudioCache silent;

  setUpAll(loadBundledFonts);
  setUp(() async {
    db = await testCorpus();
    silent = await emptyCache();
  });

  testWidgets('the shell the design never drew drifts out of Nocturne: the '
      'bar, the rule, or the weight of the account at the head of the drawer',
      (tester) async {
    await pumpPhone(tester, await wholeApp(db, cache: silent));
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(WirdDrawer),
      matchesGoldenFile('goldens/drawer.png'),
    );
  });

  testWidgets('home drifts away from Nocturne in a way no behaviour test can '
      'see: the waiting set, the two actions, or the doors below them',
      (tester) async {
    await pumpPhone(tester, await wholeApp(db, cache: silent));

    await expectLater(
      find.byType(DashboardScreen),
      matchesGoldenFile('goldens/dashboard.png'),
    );
  });

  testWidgets('the settings screen drifts out of Nocturne: the section rules, '
      'the segmented controls, or the width control under them',
      (tester) async {
    await pumpPhone(
      tester,
      await wirdAround(
        db,
        const WirdShell(route: Routes.settings, child: SettingsScreen()),
        cache: silent,
      ),
    );

    await expectLater(
      find.byType(SettingsScreen),
      matchesGoldenFile('goldens/settings.png'),
    );
  });
}
