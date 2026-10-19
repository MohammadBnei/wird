import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wird/app.dart';
import 'package:wird/data/audio.dart';
import 'package:wird/data/db.dart';
import 'package:wird/data/sets.dart';
import 'package:wird/features/dashboard/dashboard_screen.dart';
import 'package:wird/features/setup/setup_screen.dart';

import '../../corpus.dart';
import '../../fonts.dart';
import '../../offline.dart';
import '../../player.dart';
import '../../wird.dart';

void main() {
  late Database db;

  setUpAll(loadBundledFonts);
  setUp(() async => db = await testCorpus());

  // The failure: a new reader lands on home with nothing chosen and nothing
  // said about what a set is — or Start leaves them on setup with no way on.
  testWidgets('a new install opens on setup, and Start lands on home for '
      'good', (tester) async {
    await pumpPhone(tester, await wholeApp(db, setupDone: false));
    expect(find.byType(SetupScreen), findsOneWidget);

    await tester.tap(find.byKey(const Key('start')));
    await tester.pumpAndSettle();
    expect(find.byType(SetupScreen), findsNothing);
    expect(find.byType(DashboardScreen), findsOneWidget);
    expect(await setupDone(db), isTrue);
  });

  // The failure: the order or the voice picked on setup is dropped, and the
  // reader's first set is not where they asked to start.
  testWidgets('what setup is told is what the app reads with', (tester) async {
    await pumpPhone(tester, await wholeApp(db, setupDone: false));
    await tester.tap(find.text('Muṣḥaf'));
    await tester.pumpAndSettle();
    expect(find.textContaining('al-Fātiḥa'), findsOneWidget);

    final alafasy = find.text('Mishary Rashid Alafasy');
    await tester.scrollUntilVisible(alafasy, 200);
    await tester.tap(alafasy);
    await tester.tap(find.byKey(const Key('start')));
    await tester.pumpAndSettle();

    final prefs = Wird.of(tester.element(find.byType(DashboardScreen))).prefs;
    expect(prefs.order, ReadingOrder.mushaf);
    expect(prefs.reciter, 'alafasy');
    expect(
      await languagePref(db),
      isNull,
      reason: 'the language left alone keeps following the phone',
    );
  });

  // The failure: a reciter sampled on setup keeps reciting over home.
  testWidgets('a sample stops when setup closes', (tester) async {
    JustAudioPlatform.instance = FakePlayers();
    final dir = await tester.runAsync(tempAudioDir);
    await tester.runAsync(
      () => AudioCache(
        dir!,
        fetch: FakeCdn().call,
      ).fetchOne('Alafasy_128kbps/$sampleFile'),
    );
    final recitation = Recitation(
      cache: AudioCache(dir!, fetch: RadioOff().call),
    );
    await pumpPhone(
      tester,
      await wholeApp(db, setupDone: false, recitation: recitation),
    );
    final hear = find.byKey(const Key('sample alafasy'));
    await tester.scrollUntilVisible(hear, 200);
    await tester.tap(hear);
    await tester.pump();
    expect(recitation.sampling.value, 'alafasy');

    await tester.tap(find.byKey(const Key('start')));
    await tester.pumpAndSettle();
    expect(recitation.sampling.value, isNull);
  });

  // The failure: the system's back on setup leaves the flag unwritten, and
  // the reader meets setup again on every launch.
  testWidgets('back from setup lands on home and setup stays done', (
    tester,
  ) async {
    await pumpPhone(tester, await wholeApp(db, setupDone: false));
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byType(SetupScreen), findsNothing);
    expect(find.byType(DashboardScreen), findsOneWidget);
    expect(await setupDone(db), isTrue);
  });

  // The failure: a reader picks French on setup and the app stays in English,
  // or forgets the choice by the next launch.
  testWidgets('a language picked on setup is the one the app speaks', (
    tester,
  ) async {
    await pumpPhone(tester, await wholeApp(db, setupDone: false));
    await tester.tap(find.text('Français'));
    await tester.pumpAndSettle();
    expect(find.text('Commencer'), findsOneWidget);

    await tester.tap(find.byKey(const Key('start')));
    await tester.pumpAndSettle();
    expect(await languagePref(db), 'fr');
  });
}
