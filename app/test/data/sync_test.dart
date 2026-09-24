import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wird/data/db.dart';
import 'package:wird/data/kept_repo.dart';
import 'package:wird/data/outbox.dart';
import 'package:wird/data/sets.dart';
import 'package:wird/data/sync.dart';

import '../corpus.dart';
import 'fake_wird.dart';

Map<String, dynamic> keptRow(
  String id, {
  required String updatedAt,
  String body = '',
  String? deletedAt,
}) => {
  'kind': 'kept_items',
  'id': id,
  'at': updatedAt,
  'row': {
    'id': id,
    'kind': 'note',
    'ayah_id': null,
    'root_letters': null,
    'body': body,
    'tags': <String>[],
    'created_at': updatedAt,
    'updated_at': updatedAt,
    'deleted_at': deletedAt,
  },
};

Future<int> queued(Database db) async =>
    (await db.rawQuery('SELECT COUNT(*) AS n FROM outbox')).single['n']! as int;

/// The wait a transient failure earned, served. Real time cannot be waited out
/// in a test, and a fake clock seam would exist only for the test to hold.
Future<void> theClockMovesOn(Database db) =>
    db.rawUpdate('UPDATE outbox SET retry_after = NULL');

void main() {
  late Database db;
  late FakeWird server;

  setUp(() async {
    db = await testCorpus();
    await ensureKeptTable(db);
    await db.delete('kept_items');
    await db.execute('DROP TABLE IF EXISTS sync_state');
    server = await FakeWird.start();
  });

  tearDown(() async => server.stop());

  // The offline promise, two sets deep. Everything the reader did at 30,000
  // feet reaches the server when the plane lands — once each, not twice, and
  // not never.
  test('two sets read in airplane mode land exactly once on reconnect', () async {
    await server.stop(); // the plane

    await markSetUnderstood(db, newOpId(), [96001, 96002, 96003]);
    await keep(db, kind: KeptKind.note, body: 'the pen and what it writes');
    await markSetUnderstood(db, newOpId(), [68001, 68002]);
    await setReadingOrder(db, ReadingOrder.mushaf);

    final offline = await syncNow(db, SyncApi(server.dio));
    expect(offline.reachedServer, isFalse);
    expect(
      await queued(db),
      4,
      reason: 'a flush with no server to reach must not drop the queue',
    );

    // The plane lands.
    server = await FakeWird.start();
    final landed = await syncNow(db, SyncApi(server.dio));

    expect(landed.reachedServer, isTrue);
    expect(landed.landed, 4);
    expect(await queued(db), 0, reason: 'the queue did not drain');

    final kinds = server.opsReceived.map((op) => op['kind']).toList();
    expect(kinds, [
      'ayah_understood',
      'kept_upsert',
      'ayah_understood',
      'prefs_set',
    ]);
    final ids = server.opsReceived.map((op) => op['client_op_id']).toSet();
    expect(ids, hasLength(4), reason: 'an op was sent twice in one flush');
    // The reader's second set is still understood locally, whatever the
    // network did.
    expect(
      (await db.rawQuery(
        'SELECT COUNT(*) AS n FROM ayah_understood',
      )).single['n'],
      5,
    );
  });

  // The failure: a flush lands on the server and the answer is lost on the way
  // back. If the device dropped the op on send, the write is gone; if it
  // dropped it without an answer, a prayer is counted twice. It must send the
  // same op id again and wait to be told.
  test('a flush whose answer never arrived is sent again under the same op id, '
      'so the prayer is counted once', () async {
    final opId = newOpId();
    await markSetUnderstood(db, opId, [96001, 96002, 96003]);

    // The answer never comes back.
    await server.stop();
    await syncNow(db, SyncApi(server.dio));
    expect(await queued(db), 1);

    // The reconnect. The server has it already and says so.
    server = await FakeWird.start();
    server.verdict = (_) => 'duplicate';
    final report = await syncNow(db, SyncApi(server.dio));

    expect(server.opsReceived.single['client_op_id'], opId);
    expect(report.landed, 1);
    expect(
      await queued(db),
      0,
      reason: 'an op the server already has must leave the queue',
    );
  });

  // The plan's own defect: one op the server will never accept sits at the
  // head of the queue and holds everything behind it, on every reconnect,
  // until the reader loses it all.
  test('a poison op does not block the nineteen writes queued behind it', () async {
    final poison = newOpId();
    await markSetUnderstood(db, poison, [96001]);
    for (var i = 0; i < 19; i++) {
      await markSetUnderstood(db, newOpId(), [68001 + i]);
    }
    server.verdict = (id) => id == poison ? 'refused' : 'applied';

    final report = await syncNow(db, SyncApi(server.dio));

    expect(report.landed, 19);
    expect(report.refused, 1);
    expect(await pending(db), isEmpty);
    final parked = await deadLettered(db);
    expect(
      parked.map((op) => op.id),
      [poison],
      reason: 'the refused op must leave the queue, not sit at its head',
    );
  });

  // The server's own word for a refusal is that it "will never succeed however
  // often it is sent". Asking it four more times delays the moment the reader
  // is told and changes nothing else.
  test('a refused write is asked about four more times before the reader hears '
      'about it', () async {
    final poison = newOpId();
    await markSetUnderstood(db, poison, [96001]);
    server.verdict = (_) => 'refused';

    await syncNow(db, SyncApi(server.dio));

    final dead = await deadLettered(db);
    expect(dead.map((op) => op.id), [poison]);
    expect(dead.single.body['ayah_ids'], [96001]);

    // A good write made afterwards still flushes; the parked one does not ride
    // with it.
    server.verdict = (_) => 'applied';
    await markSetUnderstood(db, newOpId(), [68001]);
    await syncNow(db, SyncApi(server.dio));

    expect(
      server.batches.last.map((op) => op['client_op_id']),
      isNot(contains(poison)),
    );
  });

  // The defect: the server says `failed` and means "not applied, try again",
  // and the device spent one of five lives on it anyway. Five bad minutes
  // across five reconnects and a write nothing was wrong with is parked for
  // good.
  test('five transient server faults park a good write that should still be '
      'trying', () async {
    final good = newOpId();
    await markSetUnderstood(db, good, [96001]);
    server.verdict = (_) => 'failed';

    for (var reconnect = 0; reconnect < 5; reconnect++) {
      final report = await syncNow(db, SyncApi(server.dio));
      expect(report.reachedServer, isTrue);
      await theClockMovesOn(db);
    }

    expect(
      await deadLettered(db),
      isEmpty,
      reason: 'the server asked to be tried again, and was answering each time',
    );

    // The server has its good minute back.
    server.verdict = (_) => 'applied';
    final landed = await syncNow(db, SyncApi(server.dio));
    expect(landed.landed, 1);
    expect(await queued(db), 0);
  });

  // Without the delay the count is not a budget: a phone that reconnects every
  // few seconds — a train, a lift, a flaky router — spends all ten answers
  // before the server has finished restarting.
  test('a phone reconnecting every few seconds spends the whole retry budget '
      'during one restart', () async {
    await markSetUnderstood(db, newOpId(), [96001]);
    server.verdict = (_) => 'failed';

    await syncNow(db, SyncApi(server.dio));
    await syncNow(db, SyncApi(server.dio));
    await syncNow(db, SyncApi(server.dio));

    expect(
      server.batches,
      hasLength(1),
      reason: 'the second and third reconnects arrived inside the backoff',
    );
    expect(await deadLettered(db), isEmpty);
  });

  // And the budget is a budget: a server that keeps failing for good does not
  // leave the write pending forever with nobody told.
  test('a server that never recovers leaves the write pending forever and '
      'nobody is told', () async {
    await markSetUnderstood(db, newOpId(), [96001]);
    server.verdict = (_) => 'failed';

    for (var reconnect = 0; reconnect < maxAttempts; reconnect++) {
      await syncNow(db, SyncApi(server.dio));
      await theClockMovesOn(db);
    }

    expect(await pending(db), isEmpty);
    expect(await deadLettered(db), hasLength(1));
  });

  // The failure: a reader spends a week somewhere with no signal, the flush
  // fails five times against nothing at all, and the queue is thrown away
  // before it ever reaches a server.
  test('a week with no signal does not dead-letter a single write', () async {
    await markSetUnderstood(db, newOpId(), [96001]);
    await server.stop();

    for (var day = 0; day < 7; day++) {
      final report = await syncNow(db, SyncApi(server.dio));
      expect(report.reachedServer, isFalse);
    }

    expect(await deadLettered(db), isEmpty);
    expect((await pending(db)).single.attempts, 0);
  });

  // The failure the plan names: without the tombstone as a row, a note deleted
  // on the phone is handed straight back by the tablet on every pull.
  test('a kept note deleted on the phone is not resurrected by the tablet', () async {
    final id = await keep(db, kind: KeptKind.note, body: 'a thought');
    await forget(db, id);
    await syncNow(db, SyncApi(server.dio));

    // The tablet's copy of the note comes back on the next pull, as it will:
    // it is the same row, carrying the delete.
    final deletedAt = DateTime.now().toUtc().toIso8601String();
    server.pages = [
      {
        'changes': [
          keptRow(id, updatedAt: deletedAt, body: 'a thought', deletedAt: deletedAt),
        ],
        'cursor': '$deletedAt|$id',
        'more': false,
      },
    ];
    await syncNow(db, SyncApi(server.dio));

    expect(await keptItems(db), isEmpty);
    final row = (await db.query(
      'kept_items',
      where: 'id = ?',
      whereArgs: [id],
    )).single;
    expect(row['deleted_at'], isNotNull);
  });

  // And the same row arriving alive, from a device that had not seen the
  // delete yet, must not undo it either.
  test('an older copy of a note from a stale device does not undo the delete',
      () async {
    final id = await keep(db, kind: KeptKind.note, body: 'a thought');
    await forget(db, id);

    final stale = DateTime.now()
        .toUtc()
        .subtract(const Duration(days: 1))
        .toIso8601String();
    server.pages = [
      {
        'changes': [keptRow(id, updatedAt: stale, body: 'a thought')],
        'cursor': '$stale|$id',
        'more': false,
      },
    ];
    await syncNow(db, SyncApi(server.dio));

    expect(await keptItems(db), isEmpty);
  });

  // The failure: the cursor never moves, so every reconnect re-applies the
  // reader's whole history — years of it, over a phone connection.
  test('the second pull asks from the cursor and does not re-apply the whole '
      'history', () async {
    final at = DateTime.now().toUtc().toIso8601String();
    const note = '9b7c1d2e-0000-4000-8000-000000000001';
    server.pages = [
      {
        'changes': [keptRow(note, updatedAt: at, body: 'from the tablet')],
        'cursor': 'cursor-1',
        'more': false,
      },
    ];

    final first = await syncNow(db, SyncApi(server.dio));
    expect(first.applied, 1);
    expect((await keptItems(db)).single.body, 'from the tablet');

    final second = await syncNow(db, SyncApi(server.dio));
    expect(second.applied, 0);
    expect(server.cursorsAsked, ['', 'cursor-1']);
  });

  // A page that says there is more must be followed, or the reader restoring
  // onto a new phone gets the first five hundred rows and no more.
  test('a paged pull keeps asking until the server says it is finished', () async {
    final at = DateTime.now().toUtc().toIso8601String();
    server.pages = [
      {
        'changes': [keptRow('9b7c1d2e-0000-4000-8000-000000000002', updatedAt: at)],
        'cursor': 'cursor-1',
        'more': true,
      },
      {
        'changes': [keptRow('9b7c1d2e-0000-4000-8000-000000000003', updatedAt: at)],
        'cursor': 'cursor-2',
        'more': false,
      },
    ];

    final report = await syncNow(db, SyncApi(server.dio));

    expect(report.applied, 2);
    expect(server.cursorsAsked, ['', 'cursor-1']);
    expect(await keptItems(db), hasLength(2));
  });

  // The failure: hotel wifi answers every request with its own sign-in page
  // and a 200 on it. The device read that as the contract's JSON, and the
  // TypeError went straight out of the flush — past the one catch that knows
  // the queue is intact, and into whatever asked for the flush.
  test('a captive portal answering 200 throws out of the flush instead of '
      'being read as a server that was never reached', () async {
    await markSetUnderstood(db, newOpId(), [96001, 96002, 96003]);
    server.insteadAPortal = '<html><body>Sign in to Hotel Wifi</body></html>';

    final report = await syncNow(db, SyncApi(server.dio));

    expect(report.reachedServer, isFalse);
    expect(report.deadLettered, 0);
    expect(
      await queued(db),
      1,
      reason: 'the portal is not the server, so the write is still waiting',
    );

    // And the flush after it, on a network with a real server behind it,
    // carries the same write.
    server.insteadAPortal = null;
    expect((await syncNow(db, SyncApi(server.dio))).landed, 1);
  });

  // The in-prayer rule, as code rather than as a promise: the write path is
  // local. A server that accepts the connection and then says nothing at all
  // is the worst case for a screen that must not block, and the reader's mark
  // does not touch it.
  test('marking a set understood never waits on the network', () async {
    final silent = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    // Accept and answer nothing, forever.
    unawaited(silent.forEach((_) {}));
    addTearDown(() => silent.close(force: true));

    await markSetUnderstood(
      db,
      newOpId(),
      [96001, 96002, 96003],
    ).timeout(const Duration(seconds: 5));

    expect(await queued(db), 1);
  });
}
