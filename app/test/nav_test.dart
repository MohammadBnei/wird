import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:wird/features/study/word_row.dart';
import 'package:wird/data/audio.dart';
import 'package:wird/data/db.dart';
import 'package:wird/data/root_repo.dart';
import 'package:wird/features/root/family.dart';
import 'package:wird/data/sets.dart';
import 'package:wird/features/about/about_screen.dart';
import 'package:wird/features/dashboard/dashboard_screen.dart';
import 'package:wird/features/deepdive/deep_dive_screen.dart';
import 'package:wird/features/index/index_screen.dart';
import 'package:wird/features/kept/kept_screen.dart';
import 'package:wird/features/prayer/prepare_screen.dart';
import 'package:wird/features/progress/progress_screen.dart';
import 'package:wird/features/report/report_screen.dart';
import 'package:wird/features/root/root_screen.dart';
import 'package:wird/features/root/root_spine_screen.dart';
import 'package:wird/features/settings/settings_screen.dart';
import 'package:wird/features/study/study_screen.dart';
import 'package:wird/main.dart';
import 'package:wird/nav.dart';
import 'package:wird/shell/wird_shell.dart';

import 'corpus.dart';
import 'fonts.dart';
import 'offline.dart';
import 'wird.dart';

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
  /// and the reading screen would sit on its loading frame for the whole test.
  Future<void> openApp(WidgetTester tester) async {
    await pumpPhone(tester, await wholeApp(db, cache: audio));
  }

  /// The drawer, then a destination — the way a reader moves now. Scoped to
  /// the drawer because home names the same places on its own face.
  Future<void> goTo(WidgetTester tester, String label) async {
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: find.byType(WirdDrawer), matching: find.text(label)),
    );
    await tester.pumpAndSettle();
  }

  /// Where the reader stands, as the reader's bar prints it: "96:1 · word 1/72".
  String? position(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const Key('position'))).data;

  /// A root as the reader's sheet names it, over the word open. The ring
  /// further down the sheet prints the same letters at its centre.
  Finder rootNamed(String display) => find.descendant(
    of: find.byKey(const ValueKey('open-root')),
    matching: find.text(display),
  );

  /// The set, which is no longer the screen the app opens on.
  Future<void> openTheSet(WidgetTester tester) async {
    await openApp(tester);
    await goTo(tester, 'The set');
  }

  testWidgets('every destination the app names opens its screen, never a '
      'blank page', (tester) async {
    // What each screen is opened on. Declared here so a route added with no
    // caller able to open it fails this test instead of crashing in a hand.
    final destinations = <String, ({Object? arguments, Type screen})>{
      Routes.dashboard: (arguments: null, screen: DashboardScreen),
      // The argument is the aya screen 1a opens on, rather than the set the
      // walk would have handed the reader.
      Routes.study: (arguments: 2153, screen: StudyScreen),
      Routes.prepare: (arguments: set, screen: PrepareScreen),
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
      // The argument is the screen the reader was on when they asked to
      // report something.
      Routes.report: (arguments: Routes.index, screen: ReportScreen),
    };
    expect(destinations.keys.toSet(), screens.keys.toSet());

    await pumpPhone(tester, await wholeApp(db, cache: audio));

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

  testWidgets('the sūra index, the passage and the kept list can only be '
      'found by opening a panel that is collapsed by default', (tester) async {
    await openApp(tester);

    const doors = {
      'The set': StudyScreen,
      'Sūra index': IndexScreen,
      'Your passage': ProgressScreen,
      'Kept': KeptScreen,
      'Settings': SettingsScreen,
      'Sources': AboutScreen,
    };
    for (final door in doors.entries) {
      await goTo(tester, door.key);
      expect(find.byType(door.value), findsOneWidget, reason: door.key);
      // Settings is a sheet over the screen, and the drawer is under it.
      if (door.value == SettingsScreen) {
        await closeSettings(tester);
      }
    }
    // Home is a pop rather than a push, so the reader who walked all six is
    // one press from the start rather than six.
    await goTo(tester, 'Home');
    expect(find.byType(DashboardScreen), findsOneWidget);
    expect(navigatorIn(tester).canPop(), isFalse);
  });

  testWidgets('coming back from the index leaves the reader on the word they '
      'pressed, not on the one it opened with', (tester) async {
    final rooted = [
      for (final aya in set.ayas)
        for (final word in aya.words)
          if (word.root != null) word,
    ];
    final opened = rooted.first;
    final tapped = rooted.firstWhere((w) => w.root != opened.root);
    final detail = (await rootReading(
      db,
      tapped.root!,
      readIn: const Locale('en'),
    ))!;

    await openTheSet(tester);
    // The tap is what opens a root; the press is what sounds the word.
    await tester.tap(find.byKey(WordKey(tapped.id)));
    await tester.pumpAndSettle();
    expect(rootNamed(detail.display), findsOneWidget);

    // The index is a step from the reader; back without choosing an aya.
    await tester.tap(find.byKey(const Key('surah name')));
    await tester.pumpAndSettle();
    expect(find.byType(IndexScreen), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(StudyScreen), findsOneWidget);
    expect(rootNamed(detail.display), findsOneWidget);
  });

  testWidgets('a reader who wants Al-Fātiḥa is stuck with whatever set the '
      'walk hands them', (tester) async {
    await openTheSet(tester);
    expect(position(tester), startsWith('96:1 '));

    await goTo(tester, 'Sūra index');
    await tester.tap(find.byKey(const ValueKey('ayas-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('aya-1005')));
    await tester.pumpAndSettle();

    expect(find.byType(IndexScreen), findsNothing);
    expect(find.textContaining('Al-Fatihah'), findsOneWidget);
    expect(position(tester), startsWith('1:5 '));
  });

  testWidgets('the index opened from the passage hands its aya to a second '
      'reader stacked on the first, each holding a live player', (
    tester,
  ) async {
    await openApp(tester);
    await goTo(tester, 'Your passage');
    await tester.tap(find.text('All 114'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ayas-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('aya-1005')));
    await tester.pumpAndSettle();

    // Down to the one screen that reads an aya, not up onto a second one.
    expect(find.byType(StudyScreen), findsOneWidget);
    expect(find.byType(ProgressScreen), findsNothing);
    expect(position(tester), startsWith('1:5 '));
  });

  // The failure: home and the drawer carried only an aya on from a screen
  // they pushed, so a word answered by the passage was dropped on the floor.
  testWidgets('a sūra picked from the passage’s reading rows is dropped on '
      'the way back, from home and from the drawer', (tester) async {
    await movePosition(db, 2255003);
    await openApp(tester);
    final row = find.byKey(const ValueKey('reading 2255003'));

    Future<void> pick() async {
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(find.byType(StudyScreen), findsOneWidget);
      expect(find.byType(ProgressScreen), findsNothing);
      expect(position(tester), startsWith('2:255 '));
      navigatorIn(tester).popUntil((r) => r.isFirst);
      await tester.pumpAndSettle();
    }

    await tester.tap(find.byKey(const Key('where you are')));
    await tester.pumpAndSettle();
    await pick();

    await goTo(tester, 'Your passage');
    await pick();
  });

  testWidgets('the app goes down on the frame the corpus finishes opening, so '
      'the reader never reaches the app at all', (tester) async {
    final opening = Completer<Database>();
    await tester.pumpWidget(WirdApp(corpus: opening.future));
    await tester.pump();
    opening.complete(db);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(DashboardScreen), findsOneWidget);
  });

  testWidgets('a reader on a tablet opening a deep dive lands on a page '
      'that admits the screen behind it was never built', (tester) async {
    await openTheSet(tester);
    // The iPad Pro 11-inch in landscape, which is where the three-pane
    // reading opens rather than the phone one.
    tester.view.physicalSize = const Size(1194, 834);
    navigatorIn(tester)
        .pushNamed(Routes.deepDive, arguments: (ayahId: 96002, letters: 'علق'));
    await tester.pumpAndSettle();

    expect(find.text('ROOT'), findsOneWidget);
  });

  testWidgets('a reader on a phone opening a deep dive is handed the '
      'tablet’s three rails, which do not fit a phone', (tester) async {
    await openTheSet(tester);
    navigatorIn(tester)
        .pushNamed(Routes.deepDive, arguments: (ayahId: 96002, letters: 'علق'));
    await tester.pumpAndSettle();

    expect(find.text('DEEP DIVE · 96:2'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back_ios_new));
    await tester.pumpAndSettle();
    expect(find.byType(StudyScreen), findsOneWidget);
  });

  testWidgets('following a root’s aya reference stacks a second reading screen '
      'on the first, so the play button recites the aya the reader left', (
    tester,
  ) async {
    await openTheSet(tester);
    await tester.tap(find.byKey(const ValueKey('open-root')));
    await tester.pumpAndSettle();

    final reference = tester.widget<AyaRef>(find.byType(AyaRef).first);
    await tester.tap(find.byWidget(reference));
    await tester.pumpAndSettle();

    // One reader, changed in place. A second one stacked here would dispose
    // the first's player while the first's words stayed on screen, so the
    // count is taken over the whole stack rather than over what is on top.
    expect(find.byType(StudyScreen, skipOffstage: false), findsOneWidget);
    expect(find.byType(RootScreen, skipOffstage: false), findsNothing);
    expect(
      tester.widget<Text>(find.byKey(const Key('position'))).data,
      startsWith('${ayahRef(reference.ayahId)} '),
    );
    // And back from the visited aya is home, not a second reader.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(DashboardScreen), findsOneWidget);
  });
}
