import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:wird/data/kept_repo.dart';
import 'package:wird/data/root_repo.dart';
import 'package:wird/features/deepdive/constellation.dart';
import 'package:wird/features/deepdive/deep_dive_screen.dart';
import 'package:wird/features/root/root_sections.dart';
import 'package:wird/theme/nocturne.dart';

import '../../corpus.dart';
import '../../fonts.dart';

/// 103:3, and the root the design itself drew this screen around. The aya
/// spells it بِٱلصَّبْرِ, and the corpus holds thirty-eight forms of it.
const ayaOfPatience = 103003;
const patience = 'صبر';

/// 96:2, the first aya of the revelation order, and the root inside it.
const ayaOfTheClot = 96002;
const clot = 'علق';

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

/// 2:282, the longest aya in the Qur'an, and a root it carries.
const longestAya = 2282;
const writing = 'كتب';

void main() {
  late Database db;

  setUpAll(loadBundledFonts);
  setUp(() async {
    db = await testCorpus();
    await ensureKeptTable(db);
    await db.delete('kept_items');
  });

  Future<void> open(
    WidgetTester tester, {
    required Size size,
    int ayahId = ayaOfPatience,
    String letters = patience,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: nocturneTheme(),
        home: DeepDiveScreen(db: db, ayahId: ayahId, letters: letters),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The iPad Pro 11-inch (M4) in landscape, which is the real device nearest
  /// the design's 1180×794 frame.
  const tablet = Size(1194, 834);
  const phone = Size(402, 874);

  /// Where the root's family sits relative to the aya it belongs to: beside
  /// it in the design's three panes, under it when they stack. Read off the
  /// pane's own heading, which is there whichever way the family is drawn.
  bool besideTheAya(WidgetTester tester) =>
      tester.getTopLeft(find.text('ROOT CONSTELLATION')).dx >
      tester.getBottomRight(find.text('AL-\'ASR · AYA 3')).dx;

  testWidgets('the deep dive prints a sense as a bare assertion, so the one '
      'screen that reads a root deepest is the one that says least about '
      'whose reading it is', (tester) async {
    final reading = (await rootReading(db, patience))!;
    for (final size in [tablet, phone]) {
      await open(tester, size: size);
      expect(find.text(reading.coreSense!), findsOneWidget);
      expect(find.textContaining("This app's own reading"), findsOneWidget);

      await tester.tap(find.textContaining("This app's own reading"));
      await tester.pumpAndSettle();
      expect(find.text(reading.senseBasis!), findsOneWidget);
      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();
    }
  });

  testWidgets('the deep dive says nothing when a root was refused a sense, '
      'so the reader takes the machine’s restraint for a hole', (tester) async {
    await open(tester, size: phone, ayahId: ayaOfTheClot, letters: clot);
    expect(find.text('CORE SENSE'), findsOneWidget);
    expect(find.textContaining('bear it out'), findsOneWidget);
  });

  testWidgets('a phone opening a constellation is handed the design’s three '
      'rails side by side, leaving the aya 292 points of a 402 point screen', (
    tester,
  ) async {
    await open(tester, size: phone);

    expect(find.text('ROOT CONSTELLATION'), findsOneWidget);
    expect(besideTheAya(tester), isFalse);
  });

  testWidgets('the phone is offered a choice between the drawing and the list '
      'when the drawing is not one of the two things it can have', (
    tester,
  ) async {
    await open(tester, size: phone);
    expect(find.text('List'), findsNothing);

    await open(tester, size: tablet);
    expect(find.text('List'), findsOneWidget);
  });

  testWidgets('a reader who opens the deep dive is stranded on it — no drawn '
      'way out at tablet width, or at the stacked width under it', (
    tester,
  ) async {
    for (final size in [tablet, phone]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: nocturneTheme(),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => DeepDiveScreen(
                      db: db,
                      ayahId: ayaOfPatience,
                      letters: patience,
                    ),
                  ),
                ),
                child: const Text('the root'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('the root'));
      await tester.pumpAndSettle();
      expect(find.byType(DeepDiveScreen), findsOneWidget, reason: '$size');

      expect(find.bySemanticsLabel('Back'), findsOneWidget, reason: '$size');
      await tester.tap(find.bySemanticsLabel('Back'));
      await tester.pumpAndSettle();
      expect(find.text('the root'), findsOneWidget, reason: '$size');
    }
  });

  testWidgets('the deep dive opens its three panes in a window too narrow to '
      'hold the design’s own 292 and 336 point rails', (tester) async {
    await open(tester, size: const Size(threePaneWidth - 1, 834));
    expect(besideTheAya(tester), isFalse);

    tester.view.physicalSize = const Size(threePaneWidth, 834);
    await tester.pumpAndSettle();
    expect(besideTheAya(tester), isTrue);
  });

  testWidgets('the aya pane lights a word of a different root than the one '
      'the reader opened', (tester) async {
    await open(tester, size: tablet);

    final aya = (await ayaReading(db, ayaOfPatience, patience))!;
    final lit = [
      for (final w in aya.words)
        if (w.lit) w.text,
    ];
    final words = await db.query(
      'words',
      columns: ['text_ar'],
      where: 'ayah_id = ? AND root_letters = ?',
      whereArgs: [ayaOfPatience, patience],
    );
    expect(lit, [for (final w in words) w['text_ar']]);
    expect(
      lit,
      isNotEmpty,
      reason: 'the aya carries the root it was opened on',
    );
  });

  testWidgets('prose attributed to a scholar who never wrote it reaches a '
      'reader', (tester) async {
    await open(tester, size: tablet);

    for (final invented in inventedProse) {
      expect(find.textContaining(invented), findsNothing, reason: invented);
    }
    for (final scholar in namedScholars) {
      expect(find.textContaining(scholar), findsNothing, reason: scholar);
    }
  });

  testWidgets('a root nobody has written about is introduced by a sentence '
      'apologising for the silence', (tester) async {
    await open(tester, size: tablet, ayahId: ayaOfTheClot, letters: clot);

    expect(find.textContaining('No one has written'), findsNothing);
    expect(find.byType(Constellation), findsOneWidget);
  });

  testWidgets('the tafsir pane names three commentaries beside prose the '
      'build never downloaded from any of them', (tester) async {
    await open(tester, size: tablet);

    expect(find.text('TAFSIR · 103:3'), findsOneWidget);
    for (final source in tafsirSources) {
      expect(find.text(source), findsOneWidget);
    }
    expect(find.textContaining('Nothing is downloaded yet'), findsOneWidget);
  });

  testWidgets('the constellation’s five nodes are all the reader is ever '
      'shown of a root the corpus holds thirty-eight forms of', (tester) async {
    await open(tester, size: tablet);
    final reading = (await rootReading(db, patience))!;
    expect(reading.derivatives.length, greaterThan(5));

    await tester.tap(find.text('List'));
    await tester.pumpAndSettle();

    expect(find.byType(KinSpine), findsOneWidget);
    final spine = tester.widget<KinSpine>(find.byType(KinSpine));
    expect(spine.derivatives.length, reading.derivatives.length);
  });

  testWidgets('the button promises the reader a note and files a bookmark on '
      'the aya, so the Notes list it sends them to is empty', (tester) async {
    await open(tester, size: tablet);

    await tester.tap(find.text('Keep this aya'));
    await tester.pumpAndSettle();

    // What the button says and what it writes are one fact: a bookmark on
    // this aya, which is what the Ayas list holds.
    final kept = await db.query('kept_items', where: 'deleted_at IS NULL');
    expect(kept.single['kind'], 'aya');
    expect(kept.single['ayah_id'], ayaOfPatience);
    expect(find.text('Kept'), findsOneWidget);
  });

  testWidgets('the aya pane overflows on 2:282, the longest aya in the '
      'Qur’an', (tester) async {
    await open(tester, size: tablet, ayahId: longestAya, letters: writing);

    expect(tester.takeException(), isNull);
  });

  testWidgets('the deep dive opened on an aya the corpus does not hold shows '
      'a blank three panes rather than saying so', (tester) async {
    await open(tester, size: tablet, ayahId: 115001, letters: patience);

    expect(find.textContaining('carries no aya 115:1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('the constellation captions a form the aya does not contain as the one '
      'being recited', () async {
    db = await testCorpus();
    final reading = (await rootReading(db, patience))!;
    final aya = (await ayaReading(db, ayaOfPatience, patience))!;
    final lit = [
      for (final w in aya.words)
        if (w.lit) w.text,
    ].last;

    final stars = constellation(reading, lit);
    final marked = stars.where((s) => s.thisAya).toList();

    expect(marked, hasLength(1));
    expect(
      lit.startsWith(marked.single.derivative.text),
      isTrue,
      reason: 'the node marked THIS AYA carries a form 103:3 does not spell',
    );
    expect(stars, hasLength(5));
  });

  test('a root opened on an aya that does not contain it is still drawn with '
      'a node saying the reader is reciting it', () async {
    db = await testCorpus();
    final reading = (await rootReading(db, clot))!;

    final stars = constellation(reading, null);

    expect(stars.where((s) => s.thisAya), isEmpty);
    expect(stars, hasLength(4));
  });
}
