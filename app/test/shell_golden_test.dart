import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wird/app.dart';
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
      'bar, the rule, or the weight of the account at the head of the drawer', (
    tester,
  ) async {
    await pumpPhone(tester, await wholeApp(db, cache: silent));
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(WirdDrawer),
      matchesGoldenFile('goldens/drawer.png'),
    );
  });

  testWidgets('home drifts away from Nocturne in a way no behaviour test can '
      'see: the waiting set, the two actions, or the doors below them', (
    tester,
  ) async {
    await pumpPhone(tester, await wholeApp(db, cache: silent));

    await expectLater(
      find.byType(DashboardScreen),
      matchesGoldenFile('goldens/dashboard.png'),
    );
  });

  testWidgets('the settings screen drifts out of Nocturne: the section rules, '
      'the segmented controls, or the width control under them', (
    tester,
  ) async {
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

  testWidgets('the sūra index drifts out of Nocturne, or the corner it is '
      'opened into carries a second control under the first', (tester) async {
    await pumpPhone(tester, await wholeApp(db, cache: silent));
    await goTo(tester, 'Sūra index');

    await expectLater(
      find.byType(WirdShell),
      matchesGoldenFile('goldens/index.png'),
    );
  });

  testWidgets('the report screen drifts out of Nocturne: the kinds, the box '
      'the reader writes in, or the context printed under it', (tester) async {
    await pumpPhone(tester, await wholeApp(db, cache: silent));
    await goTo(tester, 'Report something');

    await expectLater(
      find.byType(WirdShell),
      matchesGoldenFile('goldens/report.png'),
    );
  });

  testWidgets('the transport tells a reader nothing about which recitation '
      'they started, and the only way to silence it is unreadable', (
    tester,
  ) async {
    // The notifier rather than a player: what the transport draws is the
    // sounding it is handed, and a fake platform would only be a longer way
    // of handing it one. The destination under the bar is empty so the image
    // is of the bar and nothing else.
    final recitation = Recitation(cache: silent);
    await pumpPhone(
      tester,
      await wirdAround(
        db,
        const WirdShell(route: Routes.settings, child: SizedBox.shrink()),
        recitation: recitation,
      ),
    );

    recitation.sounding.value = (what: Sounded.word, label: 'ٱقْرَأْ');
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(WirdShell),
      matchesGoldenFile('goldens/sounding_word.png'),
    );

    recitation.sounding.value = (what: Sounded.set, label: "Al-'Alaq 1-5");
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(WirdShell),
      matchesGoldenFile('goldens/sounding_set.png'),
    );
  });
}
