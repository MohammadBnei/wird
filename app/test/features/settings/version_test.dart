import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wird/data/audio.dart';
import 'package:wird/features/report/report.dart';
import 'package:wird/features/settings/settings_screen.dart';

import '../../corpus.dart';
import '../../fonts.dart';
import '../../offline.dart';
import '../../wird.dart';

void main() {
  late Database db;
  late AudioCache audio;

  setUpAll(loadBundledFonts);
  setUp(() async {
    db = await testCorpus();
    audio = await emptyCache();
  });

  testWidgets('a reader cannot tell which build they are running, or whether '
      'the update they installed arrived', (tester) async {
    await pumpPhone(
      tester,
      await wirdAround(db, const SettingsScreen(), cache: audio),
    );
    final version = find.byKey(const Key('app version'));
    await tester.scrollUntilVisible(version, 300);
    // A test build is not a release, so it says dev; the release build passes
    // the pubspec's version in as WIRD_VERSION.
    expect(tester.widget<Text>(version).data, 'Wird $appVersion');
    expect(appVersion, 'dev');
  });
}
