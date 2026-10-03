import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wird/data/audio.dart';
import 'package:wird/data/auth.dart';
import 'package:wird/features/report/report.dart';

import '../../corpus.dart';
import '../../fonts.dart';
import '../../offline.dart';
import '../../wird.dart';
import '../settings/account_panel_test.dart' show IssuerInProcess;

/// Opens the report screen the way a reader does: from the drawer, having
/// been somewhere. Where they were is what the report carries.
Future<void> reportFrom(WidgetTester tester, String destination) async {
  await goTo(tester, destination);
  await goTo(tester, 'Report something');
}

/// The version the shipped corpus carries, asked of the corpus rather than
/// written down here. Written down, every rebuild of the asset reddens these
/// tests over a number the ETL is supposed to bump.
Future<int> shippedCorpusVersion(Database db) async =>
    (await db.query('corpus_meta', columns: ['corpus_version'], limit: 1))
            .single['corpus_version']!
        as int;

Future<Map<String, dynamic>?> queued(Database db) async {
  final rows = await db.query('outbox');
  if (rows.isEmpty) return null;
  final row = rows.single;
  expect(row['kind'], 'report_written');
  return jsonDecode(row['body']! as String) as Map<String, dynamic>;
}

/// The version the asset in `app/assets/` is expected to carry, and the only
/// place in the app's tests it is written down. `server/cmd/etl`'s
/// `-corpus-version` default has to agree with it: the API groups reports by
/// this number, so a rebuild that regresses it misattributes every report, and
/// the report golden only bakes the digit as pixels.
const expectedCorpusVersion = 8;

void main() {
  late Database db;
  late AudioCache silent;

  setUpAll(loadBundledFonts);
  setUp(() async {
    db = await testCorpus();
    silent = await emptyCache();
  });

  test('the shipped corpus carries the version the ETL writes', () async {
    expect(await shippedCorpusVersion(db), expectedCorpusVersion);
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
      'corpus_version': await shippedCorpusVersion(db),
      'sense_version': '',
      'locale': 'en',
      'sense_hash': '',
      'created_at': anything,
    });
  });

  // The failure: the local write fails — a full disk — and the screen flips to
  // "written down" anyway, clearing the box. The reader believes it went, and
  // the words are gone.
  testWidgets('a report the phone could not write is called sent and its '
      'words thrown away', (tester) async {
    await db.execute(
      'CREATE TEMP TRIGGER outbox_full BEFORE INSERT ON main.outbox '
      "BEGIN SELECT RAISE(ABORT, 'database or disk is full'); END",
    );
    addTearDown(() => db.execute('DROP TRIGGER IF EXISTS temp.outbox_full'));
    await pumpPhone(tester, await wholeApp(db, cache: silent));
    await reportFrom(tester, 'Sūra index');

    await tester.enterText(find.byType(TextField), 'the audio stops');
    await tester.pump();
    await tester.tap(find.byKey(const Key('send report')));
    await tester.pumpAndSettle();

    expect(find.textContaining('goes out with the next sync'), findsNothing);
    expect(find.text('the audio stops'), findsOneWidget);
    expect(find.textContaining('Not saved on this phone'), findsOneWidget);
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
    expect(find.textContaining('Kept on this phone'), findsOneWidget);
  });

  /// Sends one report from the index and settles on the sent view.
  Future<void> sendOne(WidgetTester tester) async {
    await pumpPhone(tester, await wholeApp(db, cache: silent));
    await reportFrom(tester, 'Sūra index');
    await tester.enterText(find.byType(TextField), 'the audio stops');
    await tester.pump();
    await tester.tap(find.byKey(const Key('send report')));
    await tester.pumpAndSettle();
  }

  // The failure: a signed-out reader is told the report goes out with the
  // next sync, and it never does — every flush is refused until they sign in,
  // and nothing on the screen said so.
  testWidgets('a signed-out report is promised to the next sync it will '
      'never reach', (tester) async {
    await sendOne(tester);

    expect(
      find.text('Kept on this phone. It is sent once you sign in.'),
      findsOneWidget,
    );
    expect(find.textContaining('goes out with the next sync'), findsNothing);
  });

  // The failure: the sign-in line is shown to a reader who is signed in, and
  // they go looking for a sign-in that is already done.
  testWidgets('a signed-in reader is told to sign in before the report goes',
      (tester) async {
    final issuer = IssuerInProcess();
    final account = Account(
      db,
      http: issuer.client,
      issuer: IssuerInProcess.issuer,
      clientId: 'wird-test',
      redirect: authRedirect,
    );
    // The test corpus is shared by the whole file and the sign-in tables are
    // not among those it empties.
    addTearDown(() async {
      await db.execute('DROP TABLE IF EXISTS auth_tokens');
      await db.execute('DROP TABLE IF EXISTS local_reader');
    });
    // The sign-in does not settle under the test's fake clock.
    await tester.runAsync(() async {
      final begun = await account.begin();
      final asked = begun.url.queryParameters;
      await account.complete(
        begun,
        Uri.parse(
          '${asked['redirect_uri']}?code=a-code&state=${asked['state']}',
        ),
      );
    });

    await sendOne(tester);

    expect(find.textContaining('goes out with the next sync'), findsOneWidget);
    expect(find.textContaining('sign in'), findsNothing);
  });

  // The failure: the app asks to transmit something and shows the reader the
  // text but not the values it has gathered around it. A devotional app owes
  // the person a plain look at what is leaving their phone.
  testWidgets('the context is sent without the reader being shown it',
      (tester) async {
    // A pack is installed first because an empty sense version is drawn as
    // nothing, and nothing on a screen is not evidence that it is shown.
    const senseVersion = '2-d41d8cd98f00b204e9800998ecf8427e';
    await db.insert('sense_pack', {
      'id': 1,
      'version': senseVersion,
      'fetched_at': DateTime.now().toIso8601String(),
    });
    await pumpPhone(tester, await wholeApp(db, cache: silent));
    await reportFrom(tester, 'Sūra index');

    final version = '${await shippedCorpusVersion(db)}';
    for (final shown in [
      appVersion,
      platformName,
      'index',
      version,
      senseVersion,
      'en',
    ]) {
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

    expect(find.textContaining('Nothing comes back'), findsOneWidget);
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

  // The failure: a build run from a laptop reports itself as the last
  // release, and a bug seen on a walk build is filed against a version that
  // never had it. Only the release build names a version (apk.yml passes the
  // pubspec's); everything else is `dev`.
  test('a build nobody released reports a released version', () {
    expect(appVersion, 'dev');
  });
}
