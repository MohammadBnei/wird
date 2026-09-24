import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wird/data/auth.dart';
import 'package:wird/data/db.dart';
import 'package:wird/data/kept_repo.dart';
import 'package:wird/data/outbox.dart';
import 'package:wird/data/sync.dart';

import '../corpus.dart';
import 'fake_issuer.dart';
import 'fake_wird.dart';

Future<int> queued(Database db) async =>
    (await db.rawQuery('SELECT COUNT(*) AS n FROM outbox')).single['n']! as int;

Future<int> understood(Database db) async =>
    (await db.rawQuery(
      'SELECT COUNT(*) AS n FROM ayah_understood',
    )).single['n']!
        as int;

void main() {
  late Database db;
  late FakeIssuer issuer;
  late FakeWird server;

  setUp(() async {
    db = await testCorpus();
    await ensureKeptTable(db);
    await db.delete('kept_items');
    await db.delete('ayah_understood');
    await db.execute('DROP TABLE IF EXISTS sync_state');
    await db.execute('DROP TABLE IF EXISTS auth_tokens');
    issuer = await FakeIssuer.start();
    server = await FakeWird.start();
  });

  tearDown(() async {
    await issuer.stop();
    await server.stop();
  });

  Account theAccount() => Account(
    db,
    issuer: issuer.issuer,
    clientId: 'wird-test',
    redirect: 'dev.bnei.wird://',
  );

  /// The browser's half of a sign-in, done by the test: open the address the
  /// app hands over, and bring back where it was sent.
  Future<void> signIn(Account account) async {
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

  SyncApi syncAs(Account account) => SyncApi(
    Dio(BaseOptions(baseUrl: 'http://127.0.0.1:${server.port}'))
      ..interceptors.add(AuthHeader(account)),
  );

  Future<void> aMonthOfReading() async {
    await markSetUnderstood(db, newOpId(), [96001, 96002]);
    await keep(db, kind: KeptKind.note, body: 'the pen and what it writes');
  }

  // The expensive mistake this round could make. A 401 is a token that has
  // gone stale, and the writes behind it are perfectly good; classify it as a
  // refusal and every aya the reader marked on a plane is parked for ever, on
  // a fault that fixes itself the moment they sign in again.
  test('an expired token dead-letters every write the reader made offline', () async {
    await aMonthOfReading();
    server.accepts = (_) => false;

    final report = await syncNow(db, syncAs(theAccount()));

    expect(report.reachedServer, isFalse);
    expect(report.deadLettered, 0);
    expect(await deadLettered(db), isEmpty);
    expect(await queued(db), 2);
    expect(
      (await pending(db)).map((op) => op.attempts),
      everyElement(0),
      reason: 'nothing the server never took counts against a retry budget',
    );
  });

  // Trap 1 of docs/authentik-wiring.md. The issuer hands back an ID token and
  // an access token; the obvious client code sends the access token, and the
  // Go server — which verifies an ID token, and so checks that `aud` carries
  // the client id — answers 401 to every write for ever.
  test('the phone sends the access token and the server refuses every write',
      () async {
    final account = theAccount();
    await signIn(account);
    // A server that takes the ID token and nothing else, which is what
    // `provider.Verifier(&oidc.Config{ClientID: audience})` is.
    server.accepts = (bearer) => bearer == 'Bearer ${issuer.idToken}';
    await aMonthOfReading();

    final report = await syncNow(db, syncAs(account));

    expect(report.reachedServer, isTrue);
    expect(await queued(db), 0);
    expect(server.bearers, isNot(contains('Bearer ${issuer.accessToken}')));
  });

  // The reader whose phone has been asleep since yesterday. The stored token
  // expired while they were not using it, and a client that sends it anyway
  // spends a round trip to be told so.
  test("a token that expired in the reader's pocket sends their writes nowhere",
      () async {
    final account = theAccount();
    issuer.life = const Duration(hours: -1);
    await signIn(account);
    issuer.life = const Duration(hours: 1);
    server.accepts = (bearer) => bearer == 'Bearer ${issuer.idToken}';
    await aMonthOfReading();

    final report = await syncNow(db, syncAs(account));

    expect(report.reachedServer, isTrue);
    expect(await queued(db), 0);
    expect(issuer.grants, contains('refresh_token'));
    expect(
      server.bearers,
      everyElement(isNot('Bearer ')),
      reason: 'the stale token was never sent',
    );
  });

  // The other shape of the same fault: the token still looks fresh here and
  // the session behind it has ended at the issuer. One refresh and one retry
  // is the difference between the flush landing and the reader's queue sitting
  // still until they notice.
  test('a session ended at the server leaves the queue where it is', () async {
    final account = theAccount();
    await signIn(account);
    final stale = issuer.idToken;
    server.accepts = (bearer) => bearer != 'Bearer $stale';
    await aMonthOfReading();

    final report = await syncNow(db, syncAs(account));

    expect(report.reachedServer, isTrue);
    expect(await queued(db), 0);
    expect(await deadLettered(db), isEmpty);
    expect(
      server.bearers.first,
      'Bearer $stale',
      reason: 'the first push carried the token the device held',
    );
  });

  // A refusal of the refresh token is the one answer that really means signed
  // out. Anything else is weather, and a client that signs the reader out over
  // weather makes them type a password because a train went into a tunnel.
  test('a tunnel signs the reader out of an account that is still theirs',
      () async {
    final account = theAccount();
    issuer.life = const Duration(hours: -1);
    await signIn(account);
    await issuer.stop();

    expect(await account.token(), isNull);
    expect(
      await account.current(),
      isNotNull,
      reason: 'the refresh never got an answer, so nothing was learned',
    );
  });

  test('a revoked session leaves the reader signed in to nothing, for ever',
      () async {
    final account = theAccount();
    issuer.life = const Duration(hours: -1);
    await signIn(account);
    issuer.refusesRefresh = true;

    expect(await account.token(), isNull);
    expect(
      await account.current(),
      isNull,
      reason: 'the panel has to offer a sign-in again, not a dead account',
    );
  });

  // Signing out and forgetting what the reader has understood are two
  // different acts, and only one of them was asked for.
  test('signing out throws away what the reader understood', () async {
    final account = theAccount();
    await signIn(account);
    await aMonthOfReading();

    await account.signOut();

    expect(await account.current(), isNull);
    expect(await understood(db), 2);
    expect(await queued(db), 2);
    expect((await db.query('kept_items')), hasLength(1));
  });

  test('a sign-in link from anywhere signs this phone into that account',
      () async {
    final account = theAccount();
    final begun = await account.begin();

    await expectLater(
      account.complete(
        begun,
        Uri.parse('dev.bnei.wird://?code=somebody-elses&state=not-ours'),
      ),
      throwsA(isA<AuthFailed>()),
    );
    expect(await account.current(), isNull);
  });

  test('the code is sent with no proof that this phone asked for it', () async {
    await signIn(theAccount());

    expect(issuer.verifiers, hasLength(1));
    expect(
      base64Url
          .encode(sha256.convert(ascii.encode(issuer.verifiers.single)).bytes)
          .replaceAll('=', ''),
      issuer.challenges.single,
    );
  });
}
