import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wird/data/audio.dart';
import 'package:wird/data/auth.dart';
import 'package:wird/data/db.dart';
import 'package:wird/features/dashboard/dashboard_screen.dart';
import 'package:wird/features/settings/settings_screen.dart';

import '../../corpus.dart';
import '../../data/fake_issuer.dart';
import '../../fonts.dart';
import '../../offline.dart';
import '../../wird.dart';

void main() {
  late Database db;
  late AudioCache audio;
  late FakeIssuer issuer;

  setUpAll(() {
    loadBundledFonts();
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  setUp(() async {
    // A widget test is handed a client that answers 400 to everything, so that
    // no screen can quietly reach the network. The sign-in below is this test
    // standing in for the reader and their browser, not a screen.
    HttpOverrides.global = null;
    db = await testCorpus();
    await db.delete('ayah_understood');
    await db.execute('DROP TABLE IF EXISTS auth_tokens');
    await db.execute('DROP TABLE IF EXISTS local_reader');
    audio = await emptyCache();
    issuer = await FakeIssuer.start();
  });

  tearDown(() async => issuer.stop());

  Future<void> theReaderSignsIn() async {
    final account = Account(
      db,
      issuer: issuer.issuer,
      clientId: 'wird-test',
      redirect: 'dev.bnei.wird://',
    );
    final begun = await account.begin();
    final client = HttpClient();
    final request = await client.getUrl(begun.url);
    request.followRedirects = false;
    final answer = await request.close();
    final back = Uri.parse(answer.headers.value(HttpHeaders.locationHeader)!);
    await answer.drain<void>();
    client.close();
    await account.complete(begun, back);
  }

  Future<void> openSettings(WidgetTester tester) async {
    await pumpPhone(
      tester,
      await wirdAround(db, const SettingsScreen(), cache: audio),
    );
    await tester.scrollUntilVisible(find.text('ACCOUNT'), 200);
    await tester.pumpAndSettle();
  }

  // The rule the whole design rests on: the reading loop is local and works
  // with the radio off, so an account can never stand between the reader and
  // the Qur'an. A sign-in that greets them at launch, or a screen that waits
  // on one, is the failure.
  testWidgets('the app asks who the reader is before it will open the Qur\'an',
      (tester) async {
    await pumpPhone(tester, await wholeApp(db, cache: audio));

    expect(find.byType(DashboardScreen), findsOneWidget);
    expect(find.text('Sign in'), findsNothing);
    expect(find.textContaining('Signed in'), findsNothing);
  });

  testWidgets('a reader who has not signed in is offered no way to', (
    tester,
  ) async {
    await openSettings(tester);

    expect(find.text('Sign in'), findsOneWidget);
    expect(
      find.textContaining('Wird works signed out'),
      findsOneWidget,
      reason: 'the panel has to say that not signing in is a whole answer',
    );
  });

  // Signing out and forgetting a month of reading are two different acts, and
  // the reader asked for one of them. This is the button that could be wired
  // to both.
  testWidgets("signing out takes the reader's progress with it", (
    tester,
  ) async {
    // Real sockets, so outside the frames: a widget test runs on a fake clock
    // and an HTTP round trip does not.
    await tester.runAsync(theReaderSignsIn);
    await markSetUnderstood(db, newOpId(), [96001, 96002]);

    await openSettings(tester);
    expect(find.text('Signed in as reader@bnei.dev'), findsOneWidget);
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();

    expect(find.text('Sign in'), findsOneWidget);
    expect(await db.query('ayah_understood'), hasLength(2));
    expect(
      await db.query('outbox'),
      hasLength(1),
      reason: 'the queued write waits for the next sign-in, it is not dropped',
    );
  });
}
