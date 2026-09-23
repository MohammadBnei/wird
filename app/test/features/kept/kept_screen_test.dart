import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wird/data/db.dart';
import 'package:wird/data/kept_repo.dart';
import 'package:wird/features/kept/kept_screen.dart';
import 'package:wird/theme/nocturne.dart';

import '../../corpus.dart';
import '../../fonts.dart';

/// 103:3, وَتَوَاصَوْا بِالصَّبْرِ — the aya the design's own kept card holds.
const _tawasaw = 103003;

void main() {
  late Database db;

  setUpAll(loadBundledFonts);
  setUp(() async {
    db = await testCorpus();
    await ensureKeptTable(db);
    await db.delete('kept_items');
  });

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: nocturneTheme(),
        home: KeptScreen(db: db),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> choose(WidgetTester tester, String segment) async {
    await tester.tap(find.text(segment));
    await tester.pumpAndSettle();
  }

  testWidgets('a reader who has kept nothing is shown a blank screen that '
      'never says why it is blank', (tester) async {
    await open(tester);

    expect(find.textContaining('No ayas kept yet'), findsOneWidget);
  });

  testWidgets('an aya is kept without the words the corpus writes it in, so '
      'the reader cannot tell which aya it is', (tester) async {
    await keep(
      db,
      kind: KeptKind.aya,
      ayahId: _tawasaw,
      body: 'The form VI verb makes it mutual.',
      tags: ['grammar'],
    );
    await open(tester);

    final aya = (await db.query(
      'ayahs',
      columns: ['text_uthmani'],
      where: 'id = ?',
      whereArgs: [_tawasaw],
    )).single['text_uthmani'];
    expect(find.text(aya! as String), findsOneWidget);
    expect(find.text('103 : 3'), findsOneWidget);
    expect(find.text('The form VI verb makes it mutual.'), findsOneWidget);
    expect(find.text('grammar'), findsOneWidget);
  });

  testWidgets('a kept root is drawn as a bare line of letters, with none of '
      'the words that share it', (tester) async {
    await keep(
      db,
      kind: KeptKind.root,
      rootLetters: 'عصر',
      ayahId: 103001,
      body: 'To press, to wring the juice from fruit.',
    );
    await open(tester);
    await choose(tester, 'Roots');

    expect(find.text('ROOT · عصر'), findsOneWidget);
    expect(find.text('kept from 103:1'), findsOneWidget);
    // The kin the root screen would show: a root card with no kin on it is
    // indistinguishable from a note.
    final kin = (await rootDetail(db, 'عصر'))!.kin;
    for (final word in kin) {
      expect(find.text(word.text), findsOneWidget, reason: word.text);
    }
  });

  testWidgets('an aya flagged to come back to is drawn exactly like one the '
      'reader chose to keep', (tester) async {
    await keep(
      db,
      kind: KeptKind.aya,
      ayahId: 2153,
      rootLetters: 'صبر',
      body: 'Same root, read 209 sets ago.',
      tags: ['revisit'],
    );
    await open(tester);

    expect(find.text('2 : 153 · REVISIT'), findsOneWidget);
    expect(find.text('flagged for صبر'), findsOneWidget);
  });

  testWidgets('choosing a segment shows every kind anyway, so the filter '
      'decides nothing', (tester) async {
    await keep(db, kind: KeptKind.aya, ayahId: _tawasaw);
    await keep(db, kind: KeptKind.note, body: 'is khusr the loss itself?');
    await open(tester);

    expect(find.textContaining('khusr'), findsNothing);
    await choose(tester, 'Notes');
    expect(find.textContaining('khusr'), findsOneWidget);
    expect(find.text('103 : 3'), findsNothing);
  });

  testWidgets('searching for the words the reader wrote does not find their '
      'note', (tester) async {
    await keep(db, kind: KeptKind.note, body: 'is khusr the loss itself?');
    await keep(db, kind: KeptKind.note, body: 'Ṭabarī reads it as ruin.');
    await open(tester);
    await choose(tester, 'Notes');

    await tester.enterText(find.byType(TextField), 'khusr');
    await tester.pumpAndSettle();

    // The field itself now reads "khusr", so the card is identified by the
    // words around it rather than by the word searched for.
    expect(find.textContaining('the loss itself'), findsOneWidget);
    expect(find.textContaining('Ṭabarī'), findsNothing);
  });

  testWidgets('an item swiped away is back on the next visit to the kept '
      'list', (tester) async {
    await keep(db, kind: KeptKind.note, body: 'is khusr the loss itself?');
    await open(tester);
    await choose(tester, 'Notes');

    await tester.drag(find.textContaining('khusr'), const Offset(500, 0));
    await tester.pumpAndSettle();
    expect(find.textContaining('khusr'), findsNothing);

    await open(tester);
    await choose(tester, 'Notes');
    expect(find.textContaining('khusr'), findsNothing);
  });
}
