import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wird/data/audio.dart';
import 'package:wird/data/db.dart';
import 'package:wird/data/outbox.dart';
import 'package:wird/features/prayer/prayer_screen.dart';
import 'package:wird/features/report/report.dart';
import 'package:wird/features/settings/settings_screen.dart';
import 'package:wird/theme/nocturne.dart';

import '../../corpus.dart';
import '../../fonts.dart';
import '../../offline.dart';
import '../../wird.dart';
import '../prayer/sets.dart';

/// A write the server has refused, parked the way the sync path parks it —
/// through [settle], not by writing the column by hand, so a test cannot pass
/// against a state the app never reaches.
Future<String> parkAWrite(Database db, List<int> ayas) async {
  final id = newOpId();
  await markSetUnderstood(db, id, ayas);
  await settle(db, [
    OpVerdict(id, 'refused', reason: 'it does not fit what is already recorded'),
  ]);
  return id;
}

void main() {
  late Database db;
  late AudioCache audio;

  setUpAll(loadBundledFonts);
  setUp(() async {
    db = await testCorpus();
    audio = await emptyCache();
  });

  Future<void> openSettings(WidgetTester tester) async {
    await pumpPhone(
      tester,
      await wirdAround(db, const SettingsScreen(), cache: audio),
    );
  }

  // The defect: the ops the server would never take were queried by nothing
  // and shown nowhere, so a write that could not land looked exactly like a
  // write that never happened.
  testWidgets('a write dies quietly and the reader never learns it is gone',
      (tester) async {
    await parkAWrite(db, [96001, 96002]);

    await openSettings(tester);

    expect(find.textContaining('has not reached the server'), findsOneWidget);
    expect(find.text('2 ayas you marked understood'), findsOneWidget);
    expect(find.text('Send again'), findsOneWidget);
    expect(find.text('Discard'), findsOneWidget);
  });

  testWidgets('a reader with a healthy outbox is told about writes anyway',
      (tester) async {
    await markSetUnderstood(db, newOpId(), [96001]);

    await openSettings(tester);

    expect(find.textContaining('has not reached the server'), findsNothing);
    expect(find.textContaining('have not reached the server'), findsNothing);
    expect(find.text('Send again'), findsNothing);
  });

  testWidgets('the reader sends a parked write again and it is still parked',
      (tester) async {
    final id = await parkAWrite(db, [96001]);

    await openSettings(tester);
    await tester.tap(find.text('Send again'));
    await tester.pumpAndSettle();

    expect(find.text('Send again'), findsNothing);
    expect(await deadLettered(db), isEmpty);
    expect(
      (await pending(db)).map((op) => op.id),
      contains(id),
      reason: 'the reader asked for it to ride on the next flush',
    );
  });

  testWidgets('the reader discards a parked write and it comes back on the '
      'next flush', (tester) async {
    await parkAWrite(db, [96001]);

    await openSettings(tester);
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();

    expect(find.text('Discard'), findsNothing);
    expect(await deadLettered(db), isEmpty);
    expect(await pending(db), isEmpty);
  });

  // The failure: a report is the one op kind the panel could not name, so the
  // reader who took the trouble to write a bug is told "A change you made"
  // about it and has no way to tell which of their writes is stuck.
  testWidgets('a parked report is named as something the reader cannot place',
      (tester) async {
    await sendReport(
      db,
      kind: ReportKind.bug,
      body: 'the audio stops at the end of the set',
      context: await reportContext(db, screen: 'study'),
    );
    final report = (await pending(db)).single;
    await settle(db, [
      OpVerdict(report.id, 'refused', reason: 'it is longer than the column'),
    ]);

    await openSettings(tester);

    expect(find.text('Something you reported'), findsOneWidget);
    expect(find.text('A change you made'), findsNothing);
  });

  // 1b may not block, spin, or show anything. A parked write is settings'
  // business and waits there; mid-prayer the reader is praying.
  testWidgets('the prayer screen shows a parked write to a reader who is '
      'praying', (tester) async {
    await parkAWrite(db, [103001]);
    final set = await alAsr(db);

    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: nocturneTheme(),
        home: PrayerScreen(
          db: db,
          set: set,
          wakelock: ({required bool enable}) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('reached the server'), findsNothing);
    expect(find.textContaining('marked understood'), findsNothing);
    expect(find.text('Send again'), findsNothing);
    expect(find.text('Discard'), findsNothing);
    expect(find.byType(Dialog), findsNothing);
  });
}
