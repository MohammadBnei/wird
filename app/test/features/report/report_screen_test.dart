import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wird/data/audio.dart';
import 'package:wird/features/report/report.dart';

import '../../corpus.dart';
import '../../fonts.dart';
import '../../offline.dart';
import '../../wird.dart';

/// Opens the report screen the way a reader does: from the drawer, having
/// been somewhere. Where they were is what the report carries.
Future<void> reportFrom(WidgetTester tester, String destination) async {
  await goTo(tester, destination);
  await goTo(tester, 'Report something');
}

Future<Map<String, dynamic>?> queued(Database db) async {
  final rows = await db.query('outbox');
  if (rows.isEmpty) return null;
  final row = rows.single;
  expect(row['kind'], 'report_written');
  return jsonDecode(row['body']! as String) as Map<String, dynamic>;
}

void main() {
  late Database db;
  late AudioCache silent;

  setUpAll(loadBundledFonts);
  setUp(() async {
    db = await testCorpus();
    silent = await emptyCache();
  });

  // The failure: the report arrives saying "the audio stops" and nothing else
  // — no build, no platform, no screen — because the reader was expected to
  // find those themselves and did not.
  testWidgets('a report arrives with nothing behind it to tie it to a build '
      'or a screen', (tester) async {
    await pumpPhone(tester, await wholeApp(db, cache: silent));
    await reportFrom(tester, 'Sūra index');

    await tester.enterText(
      find.byType(TextField),
      'the audio stops at the end of the set',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('send report')));
    await tester.pumpAndSettle();

    expect(await queued(db), {
      'kind': 'bug',
      'body': 'the audio stops at the end of the set',
      'app_version': appVersion,
      'platform': platformName,
      'screen': 'index',
      'corpus_version': 1,
      'created_at': anything,
    });
  });

  // The failure: the send goes to the server rather than to the queue, so the
  // reader on a plane — who is exactly the reader with something to report —
  // watches a spinner and loses what they wrote. There is no server anywhere
  // in this test: a send that reached for one could not finish.
  testWidgets('a report is carried to the server instead of the queue, so a '
      'reader with no signal loses what they wrote', (tester) async {
    await pumpPhone(tester, await wholeApp(db, cache: silent));
    await reportFrom(tester, 'Settings');

    await tester.enterText(find.byType(TextField), 'on a plane');
    await tester.pump();
    await tester.tap(find.byKey(const Key('send report')));
    await tester.pumpAndSettle();

    expect((await queued(db))!['body'], 'on a plane');
    expect(find.textContaining('goes out with the next sync'), findsOneWidget);
  });

  // The failure: the app asks to transmit something and shows the reader the
  // text but not the four values it has gathered around it. A devotional app
  // owes the person a plain look at what is leaving their phone.
  testWidgets('the context is sent without the reader being shown it',
      (tester) async {
    await pumpPhone(tester, await wholeApp(db, cache: silent));
    await reportFrom(tester, 'Sūra index');

    for (final shown in [appVersion, platformName, 'index', '1']) {
      expect(
        find.text(shown),
        findsOneWidget,
        reason: '"$shown" is sent and is not on the screen that sends it',
      );
    }
  });

  // The failure: a reader writes a report and waits for an answer that was
  // never going to come, because nothing on the screen said so.
  testWidgets('the screen takes a report without saying that nothing comes '
      'back', (tester) async {
    await pumpPhone(tester, await wholeApp(db, cache: silent));
    await reportFrom(tester, 'Sūra index');

    expect(find.textContaining('nothing comes back'), findsOneWidget);
  });

  // The failure: an empty press queues a blank row, and somebody reads it
  // looking for a bug that was never written.
  testWidgets('an empty report is queued and read as one', (tester) async {
    await pumpPhone(tester, await wholeApp(db, cache: silent));
    await reportFrom(tester, 'Sūra index');

    await tester.tap(find.byKey(const Key('send report')));
    await tester.pumpAndSettle();

    expect(await queued(db), isNull);
  });

  // The failure: the server's column takes 4000 characters and refuses
  // anything longer, and a refusal is permanent. So the reader who writes the
  // long report — the one with the detail in it — has it parked and never
  // read, and nothing on the screen ever said there was a limit.
  testWidgets('a report longer than the server accepts is queued and refused '
      'forever', (tester) async {
    await pumpPhone(tester, await wholeApp(db, cache: silent));
    await reportFrom(tester, 'Sūra index');

    await tester.enterText(
      find.byType(TextField),
      'the audio stops. ' * (reportMaxChars ~/ 4),
    );
    await tester.pump();

    expect(
      find.textContaining(RegExp('4,?000')),
      findsOneWidget,
      reason: 'the limit is met while the reader writes, where they see it',
    );

    // Four thousand characters is a field taller than the phone.
    await tester.ensureVisible(find.byKey(const Key('send report')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('send report')));
    await tester.pumpAndSettle();

    expect(((await queued(db))!['body']! as String).length, reportMaxChars);
  });

  // The failure: the app builds for a target the server's column constraint
  // has never heard of. That report is refused, and a refusal is permanent —
  // it is parked and never arrives.
  test('the platform a report names is one the server refuses forever', () {
    expect(const {'android', 'ios', 'macos'}, contains(platformName));
  });

  // The failure: pubspec is bumped, every report keeps naming the version
  // before it, and a fixed bug goes on being reported against the build that
  // fixed it.
  test('a report names a version this app is not', () {
    final pubspec = File('pubspec.yaml').readAsLinesSync();
    final declared = pubspec
        .firstWhere((line) => line.startsWith('version:'))
        .split(':')
        .last
        .trim()
        .split('+')
        .first;
    expect(appVersion, declared);
  });
}
