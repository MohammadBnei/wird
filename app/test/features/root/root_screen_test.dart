import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:wird/data/root_repo.dart';
import 'package:wird/features/root/root_dial.dart';
import 'package:wird/features/root/root_screen.dart';
import 'package:wird/features/root/root_spine_screen.dart';
import 'package:wird/nav.dart';
import 'package:wird/theme/nocturne.dart';

import '../../corpus.dart';
import '../../fonts.dart';

/// Five derivatives — the ring the design draws.
const onTheDial = 'عقل';

/// Nine derivatives: one more than the ring can hold.
const pastTheRing = 'هزأ';

/// The root the design wrote its own placeholder prose about.
const theDesignsRoot = 'صبر';

void main() {
  late Database db;

  setUpAll(loadBundledFonts);
  setUp(() async => db = await testCorpus());

  /// A tall phone, so the whole scroll is laid out and a section cannot pass
  /// a test by being below the fold.
  Future<void> open(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(402, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: nocturneTheme(),
        home: screen,
        onGenerateRoute: (settings) => screenRoute(settings, db),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the card and the kin spine keep showing the derivative the '
      'ring has already turned past', (tester) async {
    final reading = (await rootReading(db, onTheDial))!;
    await open(tester, RootScreen(db: db, letters: onTheDial));

    // The one being read is named three times — on the ring, in the card
    // under it, and on the spine. Every other derivative is named twice.
    expect(find.text(reading.derivatives.first.text), findsNWidgets(3));
    expect(find.text(reading.derivatives[1].text), findsNWidgets(2));

    await tester.tap(find.bySemanticsLabel('Next'));
    await tester.pumpAndSettle();

    expect(find.text(reading.derivatives[1].text), findsNWidgets(3));
    expect(find.text(reading.derivatives.first.text), findsNWidgets(2));
  });

  testWidgets('tapping a kin row leaves the ring pointing at a different '
      'derivative than the one the reader chose', (tester) async {
    final reading = (await rootReading(db, onTheDial))!;
    await open(tester, RootScreen(db: db, letters: onTheDial));

    await tester.tap(find.text(reading.derivatives[2].text).last);
    await tester.pumpAndSettle();

    expect(find.text(reading.derivatives[2].text), findsNWidgets(3));
  });

  testWidgets('a root with more derivatives than the ring can hold is put on '
      'the dial anyway, and the forms that will not fit are lost', (
    tester,
  ) async {
    final reading = (await rootReading(db, pastTheRing))!;
    expect(reading.derivatives, hasLength(greaterThan(dialCapacity)));

    await open(tester, RootScreen(db: db, letters: pastTheRing));

    expect(find.byType(RootDial), findsNothing);
    for (final derivative in reading.derivatives) {
      expect(find.text(derivative.text), findsOneWidget);
    }
  });

  testWidgets('screen 2b grows a dial when it is asked for a small root, so '
      'the reader gets two different screens for the same request', (
    tester,
  ) async {
    await open(tester, RootSpineScreen(db: db, letters: onTheDial));
    expect(find.byType(RootDial), findsNothing);
  });

  testWidgets('fetched lexicon and tafsir are shown as though they had been '
      'fetched, on a build that fetches nothing', (tester) async {
    await open(tester, RootScreen(db: db, letters: onTheDial));

    expect(find.textContaining('fetched rather than bundled'), findsOneWidget);
    expect(find.textContaining('Nothing is downloaded yet'), findsOneWidget);
    // Naming the works it will quote is not a claim about what they say.
    expect(find.text('Al-Ṭabarī'), findsOneWidget);
  });

  testWidgets('the mockup’s own prose is printed as sourced scholarship, '
      'with nothing to tell the reader it was written for a mockup', (
    tester,
  ) async {
    await open(tester, RootSpineScreen(db: db, letters: theDesignsRoot));
    expect(find.textContaining('Patience is the rope'), findsOneWidget);
    expect(find.textContaining('Placeholder summaries'), findsOneWidget);
  });

  testWidgets('another root borrows the prose the design wrote about '
      'patience, and teaches it as that root’s meaning', (tester) async {
    await open(tester, RootScreen(db: db, letters: onTheDial));
    expect(find.textContaining('Patience is the rope'), findsNothing);
  });

  testWidgets('keeping a root queues nothing, so it never reaches the kept '
      'list', (tester) async {
    await open(tester, RootScreen(db: db, letters: onTheDial));

    await tester.tap(find.text('Keep this root'));
    await tester.pumpAndSettle();

    expect(await rootKept(db, onTheDial), isTrue);
    expect(find.text('Kept'), findsOneWidget);
    expect(find.byIcon(Icons.bookmark), findsOneWidget);
  });

  testWidgets('a root the corpus does not carry leaves the screen blank '
      'instead of saying so', (tester) async {
    await open(tester, RootScreen(db: db, letters: 'زززز'));
    expect(find.textContaining('carries no root'), findsOneWidget);
  });

  testWidgets('the back arrow on a root strands the reader on it instead of '
      'returning to the set', (tester) async {
    await open(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () =>
                Navigator.of(context).pushNamed(Routes.root, arguments: onTheDial),
            child: const Text('the set'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('the set'));
    await tester.pumpAndSettle();
    expect(find.byType(RootScreen), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Back'));
    await tester.pumpAndSettle();
    expect(find.text('the set'), findsOneWidget);
  });

  testWidgets('"Read the aya" opens a different aya than the derivative the '
      'dial is pointing at', (tester) async {
    final reading = (await rootReading(db, onTheDial))!;
    await open(tester, RootScreen(db: db, letters: onTheDial));

    await tester.tap(find.bySemanticsLabel('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Read the aya'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        '${ayahRef(reading.derivatives[1].ayahId)} \u00b7 $onTheDial',
      ),
      findsOneWidget,
    );
  });
}
