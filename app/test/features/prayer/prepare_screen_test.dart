import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wird/data/db.dart';
import 'package:wird/data/sets.dart';
import 'package:wird/features/prayer/prepare_screen.dart';
import 'package:wird/l10n/app_localizations.dart';
import 'package:wird/theme/nocturne.dart';

import '../../corpus.dart';
import 'sets.dart';

Future<void> pumpPrepare(
  WidgetTester tester, {
  required Database db,
  StudySet? from,
}) async {
  tester.view.physicalSize = const Size(402, 874);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: nocturneTheme(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => PrepareScreen(db: db, from: from),
              ),
            ),
            child: const Text('the set'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('the set'));
  await tester.pumpAndSettle();
}

/// Begins the prayer and leaves it at once by its Exit button.
Future<void> prayAndLeave(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('begin')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Exit'));
  await tester.pumpAndSettle();
}

void main() {
  late Database db;
  late StudySet asr;

  setUp(() async {
    db = await testCorpus();
    asr = await alAsr(db);
  });

  testWidgets('the set the reader came to pray is not the one prepared', (
    tester,
  ) async {
    await pumpPrepare(tester, db: db, from: asr);
    // In the first rakʿah, and again in the second, which repeats it.
    expect(find.text("Al-'Asr"), findsNWidgets(2));
    expect(find.textContaining('same as rakʿah 1'), findsOneWidget);
    expect(find.text('Begin Maghrib'), findsOneWidget);
  });

  testWidgets('a prayer left by its Exit button goes unrecorded', (
    tester,
  ) async {
    await pumpPrepare(tester, db: db, from: asr);
    await prayAndLeave(tester);
    // Back where the reader asked to pray from, and the prayer written down.
    expect(find.text('the set'), findsOneWidget);
    expect((await db.query('set_prayers')).single['set_id'], asr.id);
    expect(await db.query('prayer_history'), hasLength(1));
  });

  testWidgets('backing out of the preparation records a prayer nobody prayed', (
    tester,
  ) async {
    await pumpPrepare(tester, db: db, from: asr);
    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pumpAndSettle();
    expect(find.text('the set'), findsOneWidget);
    expect(await db.query('set_prayers'), isEmpty);
  });

  testWidgets('a prayer that recited another passage credits the set it was '
      'opened from', (tester) async {
    await pumpPrepare(tester, db: db, from: asr);
    await tester.tap(find.byKey(const Key('passage 1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'ikhlas');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Al-Ikhlas'));
    await tester.pumpAndSettle();
    // Four ayas, so it is offered whole and named as a sūra.
    await tester.tap(find.text('Recite Al-Ikhlas'));
    await tester.pumpAndSettle();
    expect(find.text('Al-Ikhlas'), findsNWidgets(2));
    await prayAndLeave(tester);
    expect(await db.query('set_prayers'), isEmpty);
    expect(
      (await db.query('prayer_history')).single['start_ayah_id'],
      112001,
    );
  });

  testWidgets('a reference typed in the search opens somewhere other than '
      'the aya it names', (tester) async {
    await pumpPrepare(tester, db: db, from: asr);
    await tester.tap(find.byKey(const Key('passage 1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '2:255');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Go to Al-Baqarah 2:255'));
    await tester.pumpAndSettle();
    expect(find.text('AL-BAQARAH 2:255'), findsOneWidget);
    expect(find.text('Recite Al-Baqarah 255–257'), findsOneWidget);
  });

  testWidgets('choosing a prayer leaves the rakʿah count where it was, and a '
      'changed count still claims to be the preset', (tester) async {
    await pumpPrepare(tester, db: db, from: asr);
    await tester.tap(find.text('Fajr'));
    await tester.pumpAndSettle();
    expect(find.text('Set by Fajr'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('More rakʿahs'));
    await tester.pumpAndSettle();
    expect(find.text('Fajr is usually 2'), findsOneWidget);
    // Tapped again, the preset lets go: a sunna, a nafl.
    await tester.tap(find.text('Fajr'));
    await tester.pumpAndSettle();
    expect(find.text('Any prayer, sunna or nafl'), findsOneWidget);
    expect(find.text('Begin Prayer'), findsOneWidget);
  });

  testWidgets('a phone with no recogniser is offered voice-follow it cannot '
      'run', (tester) async {
    await pumpPrepare(tester, db: db, from: asr);
    expect(
      find.text('Allow the microphone and download the recogniser in Settings'),
      findsOneWidget,
    );
    // The pace alone, then: the note says so.
    expect(
      find.text(
        'The text moves at 40 words a minute. Each rakʿah begins on a tap.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('the preview makes the reader sit through Al-Fātiḥa, or counts '
      'as a prayer', (tester) async {
    await pumpPrepare(tester, db: db, from: asr);
    await tester.tap(find.text('Preview'));
    await tester.pumpAndSettle();
    expect(find.text("Al-'Asr · 103:1"), findsOneWidget);
    await tester.tap(find.text('R2'));
    await tester.pumpAndSettle();
    expect(find.text('MAGHRIB · RAKʿAH 2 OF 3'), findsOneWidget);
    await tester.tap(find.text('Exit'));
    await tester.pumpAndSettle();
    expect(find.text('Begin Maghrib'), findsOneWidget);
    expect(await db.query('set_prayers'), isEmpty);
  });

  testWidgets('a reader who has not downloaded the recogniser yet loses '
      'their choice to be followed by voice', (tester) async {
    await pumpPrepare(tester, db: db, from: asr);
    await prayAndLeave(tester);
    expect((await prayerPrefs(db)).voice, isTrue);
  });

  testWidgets('a double tap on Begin starts two prayers and writes both', (
    tester,
  ) async {
    await pumpPrepare(tester, db: db, from: asr);
    await tester.tap(find.byKey(const Key('begin')));
    await tester.tap(find.byKey(const Key('begin')), warnIfMissed: false);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Exit'));
    await tester.pumpAndSettle();
    expect(find.text('the set'), findsOneWidget);
    expect(await db.query('set_prayers'), hasLength(1));
  });

  testWidgets('a reference into Al-Fātiḥa offers it as a passage, recited '
      'twice in one rakʿah', (tester) async {
    await pumpPrepare(tester, db: db, from: asr);
    await tester.tap(find.byKey(const Key('passage 1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '1:1');
    await tester.pumpAndSettle();
    expect(find.textContaining('Go to'), findsNothing);
  });
}
