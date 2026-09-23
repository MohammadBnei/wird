import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:wird/data/audio.dart';
import 'package:wird/data/db.dart';
import 'package:wird/data/sets.dart';
import 'package:wird/features/about/about_screen.dart';
import 'package:wird/features/deepdive/deep_dive_screen.dart';
import 'package:wird/features/index/index_screen.dart';
import 'package:wird/features/kept/kept_screen.dart';
import 'package:wird/features/prayer/prayer_screen.dart';
import 'package:wird/features/progress/progress_screen.dart';
import 'package:wird/features/root/root_screen.dart';
import 'package:wird/features/root/root_spine_screen.dart';
import 'package:wird/features/study/study_screen.dart';
import 'package:wird/main.dart';
import 'package:wird/nav.dart';
import 'package:wird/theme/nocturne.dart';

import 'corpus.dart';
import 'fonts.dart';
import 'offline.dart';

NavigatorState navigatorIn(WidgetTester tester) =>
    tester.state<NavigatorState>(find.byType(Navigator).first);

void main() {
  late Database db;
  late StudySet set;
  late AudioCache audio;

  setUpAll(loadBundledFonts);
  setUp(() async {
    db = await testCorpus();
    set = (await nextSet(db, ReadingOrder.nuzul))!;
    audio = await emptyCache();
  });

  /// The app on a phone at the design's size, whose recitation cannot be
  /// downloaded: a real download never completes inside a widget test's zone,
  /// and screen 1a would sit on its loading frame for the whole test.
  Future<void> openApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: nocturneTheme(),
        onGenerateRoute: (settings) => screenRoute(settings, db),
        home: StudyScreen(db: db, audioCache: audio),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('every destination the app names opens its screen, never a '
      'blank page', (tester) async {
    // What each screen is opened on. Declared here so a route added with no
    // caller able to open it fails this test instead of crashing in a hand.
    final destinations = <String, ({Object? arguments, Type screen})>{
      // The argument is the aya screen 1a opens on, rather than the set the
      // walk would have handed the reader.
      Routes.study: (arguments: 2153, screen: StudyScreen),
      Routes.prayer: (arguments: set, screen: PrayerScreen),
      Routes.root: (arguments: 'علق', screen: RootScreen),
      Routes.rootSpine: (arguments: 'علق', screen: RootSpineScreen),
      Routes.deepDive: (
        arguments: (ayahId: 96001, letters: 'علق'),
        screen: DeepDiveScreen,
      ),
      Routes.progress: (arguments: null, screen: ProgressScreen),
      Routes.kept: (arguments: null, screen: KeptScreen),
      Routes.about: (arguments: null, screen: AboutScreen),
      Routes.index: (arguments: null, screen: IndexScreen),
    };
    expect(destinations.keys.toSet(), screens.keys.toSet());

    await tester.pumpWidget(wirdApp(db));
    await tester.pumpAndSettle();

    for (final destination in destinations.entries) {
      navigatorIn(tester)
          .pushNamed(destination.key, arguments: destination.value.arguments);
      await tester.pumpAndSettle();
      expect(
        find.byType(destination.value.screen),
        findsOneWidget,
        reason: destination.key,
      );
      navigatorIn(tester).pop();
      await tester.pumpAndSettle();
    }
  });

  testWidgets('the prayer, the passage and the kept list are reachable from '
      'the set the reader is on', (tester) async {
    await openApp(tester);
    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();

    const doors = {
      'Pray this set': PrayerScreen,
      'Your passage': ProgressScreen,
      'Kept': KeptScreen,
      'Sūra index': IndexScreen,
    };
    for (final door in doors.entries) {
      await tester.tap(find.text(door.key));
      await tester.pumpAndSettle();
      expect(find.byType(door.value), findsOneWidget, reason: door.key);
      navigatorIn(tester).pop();
      await tester.pumpAndSettle();
    }
  });

  testWidgets('coming back from a root leaves the set on the word the reader '
      'pressed, not on the one it opened with', (tester) async {
    final rooted = [
      for (final aya in set.ayas)
        for (final word in aya.words)
          if (word.root != null) word,
    ];
    final opened = rooted.first;
    final tapped = rooted.firstWhere((w) => w.root != opened.root);
    final detail = (await rootDetail(db, tapped.root!))!;

    await openApp(tester);
    // The long press is what opens a root now; the tap speaks the word.
    await tester.longPress(find.byKey(ValueKey(tapped.id)));
    await tester.pumpAndSettle();
    expect(find.text(detail.display), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('open-root')));
    await tester.pumpAndSettle();
    expect(find.byType(RootScreen), findsOneWidget);
    // The root screen prints the radicals spaced apart, the way a lexicon
    // does, rather than the joined form the corpus keys them by.
    expect(find.text(detail.display), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(StudyScreen), findsOneWidget);
    expect(find.text(detail.display), findsOneWidget);
  });

  testWidgets('a reader who wants Al-Fātiḥa is stuck with whatever set the '
      'walk hands them', (tester) async {
    await openApp(tester);
    expect(find.textContaining("Al-'Alaq 1"), findsOneWidget);

    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sūra index'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sura-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('aya-1005')));
    await tester.pumpAndSettle();

    expect(find.byType(IndexScreen), findsNothing);
    expect(find.textContaining('Al-Fatihah 5'), findsOneWidget);
  });

  testWidgets('the index opened from the passage hands its aya to a second '
      'reader stacked on the first, each holding a live player', (tester) async {
    await openApp(tester);
    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Your passage'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All 114'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sura-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('aya-1005')));
    await tester.pumpAndSettle();

    // Down to the one screen that reads an aya, not up onto a second one.
    expect(find.byType(StudyScreen), findsOneWidget);
    expect(find.byType(ProgressScreen), findsNothing);
    expect(find.textContaining('Al-Fatihah 5'), findsOneWidget);
  });

  testWidgets('the app goes down on the frame the corpus finishes opening, so '
      'the reader never reaches the set', (tester) async {
    final opening = Completer<Database>();
    await tester.pumpWidget(WirdApp(corpus: opening.future));
    await tester.pump();
    opening.complete(db);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(StudyScreen), findsOneWidget);
  });

  testWidgets('a reader on a tablet opening a constellation lands on a page '
      'that admits the screen behind it was never built', (tester) async {
    await openApp(tester);
    // The iPad Pro 11-inch in landscape, which is where the three-pane
    // reading opens rather than the phone one.
    tester.view.physicalSize = const Size(1194, 834);
    navigatorIn(tester).pushNamed(Routes.deepDive,
        arguments: (ayahId: 96002, letters: 'علق'));
    await tester.pumpAndSettle();

    expect(find.text('ROOT CONSTELLATION'), findsOneWidget);
  });

  testWidgets('a reader on a phone opening a constellation is handed the '
      'tablet’s three rails, which do not fit a phone', (tester) async {
    await openApp(tester);
    navigatorIn(tester).pushNamed(Routes.deepDive,
        arguments: (ayahId: 96002, letters: 'علق'));
    await tester.pumpAndSettle();

    expect(find.text('DEEP DIVE · 96:2'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back_ios_new));
    await tester.pumpAndSettle();
    expect(find.byType(StudyScreen), findsOneWidget);
  });
}
