import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:wird/data/kept_repo.dart';
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
    final reading = (await rootReading(db, onTheDial, readIn: const Locale('en')))!;
    await open(tester, RootScreen(db: db, letters: onTheDial));

    // The one being read is named four times — on the ring, in the card under
    // it, on the spine, and over its parsing at the foot of the screen. Every
    // other derivative is named twice.
    expect(find.text(reading.derivatives.first.text), findsNWidgets(4));
    expect(find.text(reading.derivatives[1].text), findsNWidgets(2));

    await tester.tap(find.bySemanticsLabel('Next'));
    await tester.pumpAndSettle();

    expect(find.text(reading.derivatives[1].text), findsNWidgets(4));
    expect(find.text(reading.derivatives.first.text), findsNWidgets(2));
  });

  testWidgets('tapping a kin row leaves the ring pointing at a different '
      'derivative than the one the reader chose', (tester) async {
    final reading = (await rootReading(db, onTheDial, readIn: const Locale('en')))!;
    await open(tester, RootScreen(db: db, letters: onTheDial));

    // Unselected it is named twice, on the ring and on the spine, and .last is
    // the spine row the reader taps. Selected, it is named four times: the
    // card and its parsing name it too.
    await tester.tap(find.text(reading.derivatives[2].text).last);
    await tester.pumpAndSettle();

    expect(find.text(reading.derivatives[2].text), findsNWidgets(4));
  });

  testWidgets('a root with more derivatives than the ring can hold is put on '
      'the dial anyway, and the forms that will not fit are lost', (
    tester,
  ) async {
    final reading = (await rootReading(db, pastTheRing, readIn: const Locale('en')))!;
    expect(reading.derivatives, hasLength(greaterThan(dialCapacity)));

    await open(tester, RootScreen(db: db, letters: pastTheRing));

    expect(find.byType(RootDial), findsNothing);
    for (var i = 0; i < reading.derivatives.length; i++) {
      // Once down the spine, and the form the parsing under it is showing —
      // the first, until the reader taps another — a second time above its
      // segments.
      expect(
        find.text(reading.derivatives[i].text),
        i == 0 ? findsNWidgets(2) : findsOneWidget,
      );
    }
  });

  testWidgets('screen 2b grows a dial when it is asked for a small root, so '
      'the reader gets two different screens for the same request', (
    tester,
  ) async {
    await open(tester, RootSpineScreen(db: db, letters: onTheDial));
    expect(find.byType(RootDial), findsNothing);
  });

  testWidgets('tafsir is shown as though it had been fetched, on a build that '
      'fetches nothing', (tester) async {
    await open(tester, RootScreen(db: db, letters: onTheDial));

    expect(find.textContaining('Nothing is downloaded yet'), findsOneWidget);
    // Naming the works it will quote is not a claim about what they say.
    expect(find.text('Al-Ṭabarī'), findsOneWidget);
    // The lexicon section is gone rather than pending: Lane has no route into
    // AGPL-3.0 and the core sense answers what the placeholder stood in for.
    expect(find.text('LEXICON'), findsNothing);
    expect(find.textContaining('fetched rather than bundled'), findsNothing);
  });

  testWidgets("the parsing says it was fetched while it is sitting in the "
      'bundle, and says nothing about which occurrence it is of', (
    tester,
  ) async {
    final reading = (await rootReading(db, onTheDial, readIn: const Locale('en')))!;
    final selected = reading.derivatives.first;
    await open(tester, RootScreen(db: db, letters: onTheDial));

    // What the section used to say. Tafsir still says its own half of it.
    expect(find.textContaining('no aya has been downloaded'), findsNothing);

    // تَعْقِلُونَ at 2:44, ʿ-q-l's commonest form: a verb carrying an attached
    // pronoun, which is two segments and not one word's worth of label.
    expect(selected.wordId, 2044010);
    expect(find.text('Verb'), findsOneWidget);
    expect(find.text('Personal pronoun'), findsOneWidget);
    expect(
      find.text('Stem · Imperfect · 2nd person masculine plural'),
      findsOneWidget,
    );

    // The occurrence, named: the case and the mood are the verse's own, so a
    // parsing drawn under a root with no aya beside it would read as a claim
    // about the spelling.
    expect(find.textContaining(ayahRef(selected.ayahId)), findsWidgets);
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
      // Nothing has been fetched here, and that is a different fact from
      // "nobody wrote a sense for this root". The bundle carries no senses
      // since ADR 0010, so a device with no pack must be told the second.
      expect(find.textContaining('has not fetched'), findsOneWidget);
      // It says nothing is claimed, so it must not also claim something.
      expect(find.textContaining("This app's own reading"), findsNothing);
    }
  });

  testWidgets('a root that does carry a sense is made to look like an '
      'exception, because the refusal shouts louder than the sense', (
    tester,
  ) async {
    await seedSenses(db, {theDesignsRoot: 'to bind oneself fast; to endure'});
    await open(tester, RootScreen(db: db, letters: theDesignsRoot));
    expect(find.textContaining('has not fetched'), findsNothing);
    expect(find.textContaining('bear it out'), findsNothing);
  });

  testWidgets('a sense is printed as a bare assertion, with nothing telling '
      'a reader it is this app\'s own reading rather than a quotation', (
    tester,
  ) async {
    await seedSenses(db, {theDesignsRoot: 'to bind oneself fast; to endure'});
    final reading = (await rootReading(db, theDesignsRoot, readIn: const Locale('en')))!;
    for (final screen in [
      RootScreen(db: db, letters: theDesignsRoot),
      RootSpineScreen(db: db, letters: theDesignsRoot),
    ]) {
      await open(tester, screen);
      expect(find.text(reading.coreSense!), findsOneWidget);
      expect(find.textContaining("This app's own reading"), findsOneWidget);
    }
  });

  testWidgets('the words a sense was read from cannot be reached from the '
      'screen that claims it', (tester) async {
    await seedSenses(db, {theDesignsRoot: 'to bind oneself fast; to endure'});
    final reading = (await rootReading(db, theDesignsRoot, readIn: const Locale('en')))!;
    await open(tester, RootScreen(db: db, letters: theDesignsRoot));

    // Not printed in place: the sheet is shut until the reader asks.
    expect(find.byType(SenseEvidence), findsNothing);

    await tester.tap(find.textContaining("This app's own reading"));
    await tester.pumpAndSettle();

    // Reachable even though the sense carries no evidence words, which every
    // served sense does. That tap used to exist only when there were words,
    // so the sentence saying a machine wrote this and nobody checked it was
    // reachable on no root at all — ADR 0010's one named risk.
    expect(find.byType(SenseEvidence), findsOneWidget);
    expect(find.text(reading.senseBasis!), findsOneWidget);
    // No word list, and no empty heading over one either. A served sense
    // carries no evidence words — it was not read off a word list — so the
    // sheet drops that section rather than drawing a heading above nothing.
    expect(reading.senseEvidence, isEmpty);
    expect(
      find.descendant(
        of: find.byType(SenseEvidence),
        matching: find.textContaining('THE WORDS'),
      ),
      findsNothing,
    );
  });

  testWidgets('keeping a root queues nothing, so it never reaches the kept '
      'list', (tester) async {
    await open(tester, RootScreen(db: db, letters: onTheDial));

    await tester.tap(find.text('Keep this root'));
    await tester.pumpAndSettle();

    expect(await rootKept(db, onTheDial), isNotNull);
    expect(find.text('Kept · tap to undo'), findsOneWidget);
    expect(find.byIcon(Icons.bookmark), findsOneWidget);
  });

  testWidgets('the two Keep controls disagree: one is a toggle and the other '
      'latches, on the same screen and the same root', (tester) async {
    // kept_items is made on first use, after corpus.dart has worked out which
    // tables to empty between tests, so it is never emptied: the test above
    // has already kept this root.
    await forgetRoot(db, onTheDial);
    await open(tester, RootScreen(db: db, letters: onTheDial));

    // The bookmark at the top of the screen keeps it…
    await tester.tap(find.bySemanticsLabel('Keep'));
    await tester.pumpAndSettle();
    expect(await rootKept(db, onTheDial), isNotNull);
    expect(find.text('Kept · tap to undo'), findsOneWidget);
    expect(find.bySemanticsLabel('Kept, tap to undo'), findsOneWidget);

    // …and the button in the card below takes it back off.
    await tester.tap(find.text('Kept · tap to undo'));
    await tester.pumpAndSettle();
    expect(await rootKept(db, onTheDial), isNull);
    expect(find.byIcon(Icons.bookmark_border), findsOneWidget);
    expect(find.text('Keep this root'), findsOneWidget);
  });

  testWidgets('a double tap on Keep mints two kept rows for one root, because '
      'nothing guards the write in flight', (tester) async {
    await forgetRoot(db, onTheDial);
    await open(tester, RootScreen(db: db, letters: onTheDial));
    Future<int> live() async => (await keptItems(db, kind: KeptKind.root))
        .where((item) => item.rootLetters == onTheDial)
        .length;

    // Both presses land while the write is in flight. sqflite serialises on
    // the database, so an open transaction is what a phone's platform channel
    // is for free: the first press is still waiting on its read when the
    // second arrives, and nothing has rebuilt in between.
    await db.transaction((txn) async {
      await tester.tap(find.text('Keep this root'));
      await tester.tap(find.text('Keep this root'));
    });
    await tester.pumpAndSettle();

    expect(await live(), 1);
    expect(find.text('Kept · tap to undo'), findsOneWidget);
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
    final reading = (await rootReading(db, onTheDial, readIn: const Locale('en')))!;
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
