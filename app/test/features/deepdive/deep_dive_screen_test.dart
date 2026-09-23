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

  /// Where the constellation sits relative to the aya it belongs to: beside
  /// it in the design's three panes, under it when they stack.
  bool besideTheAya(WidgetTester tester) =>
      tester.getTopLeft(find.byType(Constellation)).dx >
      tester.getBottomRight(find.text('AL-\'ASR · AYA 3')).dx;

  testWidgets('a phone opening a constellation is handed the design’s three '
      'rails side by side, leaving the aya 292 points of a 402 point screen', (
    tester,
  ) async {
    await open(tester, size: phone);

    expect(find.text('ROOT CONSTELLATION'), findsOneWidget);
    expect(besideTheAya(tester), isFalse);
  });

  testWidgets('a phone reader pushed into a constellation has no way back to '
      'the screen that opened it', (tester) async {
    await open(tester, size: phone);

    expect(find.bySemanticsLabel('Back'), findsOneWidget);
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
    final lit = [for (final w in aya.words) if (w.lit) w.text];
    final words = await db.query(
      'words',
      columns: ['text_ar'],
      where: 'ayah_id = ? AND root_letters = ?',
      whereArgs: [ayaOfPatience, patience],
    );
    expect(lit, [for (final w in words) w['text_ar']]);
    expect(lit, isNotEmpty, reason: 'the aya carries the root it was opened on');
  });

  testWidgets('the tablet screen hands one root’s mockup prose to a root '
      'nobody has written a word about', (tester) async {
    await open(tester, size: tablet, ayahId: ayaOfTheClot, letters: clot);

    expect(find.textContaining('Patience is the rope'), findsNothing);
    expect(find.textContaining('bitter aloe'), findsNothing);
    expect(find.textContaining('No one has written'), findsOneWidget);
  });

  testWidgets('mockup prose is printed on the tablet with nothing to tell the '
      'reader nobody wrote it about this root', (tester) async {
    await open(tester, size: tablet);

    expect(find.textContaining('Patience is the rope'), findsOneWidget);
    expect(find.text(mockupNotice), findsWidgets);
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

  testWidgets('an aya the reader added to their notes is not on the kept list '
      'afterwards', (tester) async {
    await open(tester, size: tablet);

    await tester.tap(find.text('Add to notes'));
    await tester.pumpAndSettle();

    final kept = await db.query(
      'kept_items',
      where: 'kind = ? AND ayah_id = ? AND deleted_at IS NULL',
      whereArgs: ['aya', ayaOfPatience],
    );
    expect(kept, hasLength(1));
    expect(find.text('In your notes'), findsOneWidget);
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
    final lit = [for (final w in aya.words) if (w.lit) w.text].last;

    final stars = constellation(reading.derivatives, lit);
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

    final stars = constellation(reading.derivatives, null);

    expect(stars.where((s) => s.thisAya), isEmpty);
    expect(stars, hasLength(4));
  });
}
