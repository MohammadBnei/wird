import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:wird/data/root_repo.dart';
import 'package:wird/features/root/root_dial.dart';
import 'package:wird/features/root/root_sections.dart';
import 'package:wird/features/root/root_screen.dart';
import 'package:wird/nav.dart';
import 'package:wird/features/root/root_spine_screen.dart';

import '../../corpus.dart';
import '../../fonts.dart';
import '../../wird.dart';

/// Five derivatives — the ring the design draws.
const onTheDial = 'عقل';

/// Nine derivatives: one more than the ring can hold.
const pastTheRing = 'هزأ';

/// ṣ-b-r, the root the mockup's deleted prose was written about, and one of
/// the 523 that ship a sense.
const theDesignsRoot = 'صبر';

/// j-m-ʿ, one of the 1,119 roots the bar refused a sense to.
const refused = 'جمع';

/// The summaries the mockup wrote and signed with two real lexicographers'
/// names. Nothing in the build may print them again.
const inventedProse = [
  'Patience is the rope',
  'bitter aloe',
  'one governing sense',
  'Records the concrete senses',
  'Placeholder summaries',
];

/// The two works those summaries were signed with.
const namedScholars = [
  'Ibn Fāris',
  'Lane · Arabic-English Lexicon',
];

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
    await tester.pumpWidget(await wirdAround(db, screen));
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

  testWidgets('prose attributed to a scholar who never wrote it reaches a '
      'reader', (tester) async {
    for (final screen in [
      RootScreen(db: db, letters: theDesignsRoot),
      RootSpineScreen(db: db, letters: theDesignsRoot),
      RootScreen(db: db, letters: onTheDial),
      // A small root, so 2b's sources sit inside the laid-out height rather
      // than under a spine of thirty-eight forms that never mounts.
      RootSpineScreen(db: db, letters: onTheDial),
    ]) {
      await open(tester, screen);
      for (final invented in inventedProse) {
        expect(find.textContaining(invented), findsNothing, reason: invented);
      }
      for (final scholar in namedScholars) {
        expect(find.textContaining(scholar), findsNothing, reason: scholar);
      }
    }
  });

  testWidgets('a root the bar refused shows no core sense and no reason, so '
      'a deliberate refusal reads to a reader as a missing section', (
    tester,
  ) async {
    for (final screen in [
      RootScreen(db: db, letters: refused),
      RootSpineScreen(db: db, letters: refused),
    ]) {
      await open(tester, screen);
      expect(find.text('CORE SENSE'), findsOneWidget);
      expect(find.textContaining('bear it out'), findsOneWidget);
      // It says nothing is claimed, so it must not also claim something.
      expect(find.textContaining("This app's own reading"), findsNothing);
    }
  });

  testWidgets('a root that does carry a sense is made to look like an '
      'exception, because the refusal shouts louder than the sense', (
    tester,
  ) async {
    await open(tester, RootScreen(db: db, letters: theDesignsRoot));
    expect(find.textContaining('bear it out'), findsNothing);
  });

  testWidgets('a sense is printed as a bare assertion, with nothing telling '
      'a reader it is this app\'s own reading rather than a quotation', (
    tester,
  ) async {
    final reading = (await rootReading(db, theDesignsRoot))!;
    for (final screen in [
      RootScreen(db: db, letters: theDesignsRoot),
      RootSpineScreen(db: db, letters: theDesignsRoot),
    ]) {
      await open(tester, screen);
      expect(find.text(reading.coreSense!), findsOneWidget);
      expect(find.textContaining("This app's own reading"), findsOneWidget);
      // The line says how much stands behind it, so it reads as a claim
      // rather than as a disclaimer.
      expect(
        find.textContaining('${reading.senseEvidence.length}'),
        findsWidgets,
      );
    }
  });

  testWidgets('the words a sense was read from cannot be reached from the '
      'screen that claims it', (tester) async {
    final reading = (await rootReading(db, theDesignsRoot))!;
    await open(tester, RootScreen(db: db, letters: theDesignsRoot));

    // Not printed in place: the sheet is shut until the reader asks.
    expect(find.byType(SenseEvidence), findsNothing);

    await tester.tap(find.textContaining("This app's own reading"));
    await tester.pumpAndSettle();

    expect(find.byType(SenseEvidence), findsOneWidget);
    expect(find.text(reading.senseBasis!), findsOneWidget);
    for (final word in reading.senseEvidence) {
      expect(
        find.descendant(
          of: find.byType(SenseEvidence),
          matching: find.text(word),
        ),
        findsOneWidget,
        reason: word,
      );
    }
    // A word on its own is not evidence. The gloss the corpus carries for it
    // is what a reader checks the sense against.
    final glossed = reading.spelled(reading.senseEvidence.first)!;
    expect(
      find.descendant(
        of: find.byType(SenseEvidence),
        matching: find.text(glossed.gloss!),
      ),
      findsOneWidget,
    );
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
                Navigator.of(context)
                    .pushNamed(Routes.root, arguments: onTheDial),
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
    int? answered;
    await open(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              answered =
                  await Navigator.of(
                        context,
                      ).pushNamed(Routes.root, arguments: onTheDial)
                      as int?;
            },
            child: const Text('the set'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('the set'));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Read the aya'));
    await tester.pumpAndSettle();

    // The aya is answered DOWN to the set the reader came from, which is the
    // one screen that reads one: see ADR-0003.
    expect(find.byType(RootScreen), findsNothing);
    expect(answered, reading.derivatives[1].ayahId);
  });
}
