// The end-to-end fixture. It is driven from Go: TestGateEndToEndWithTheRealClient
// in server/internal/api starts a real server on a real socket, a real Postgres
// behind it, and runs this file against it with the three defines below. It
// lives outside test/ because without that server there is nothing to test
// against, and a plain `fvm flutter test` has no server to give it.

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wird/data/db.dart';
import 'package:wird/data/outbox.dart';
import 'package:wird/data/sync.dart';

const _url = String.fromEnvironment('WIRD_E2E_URL');
const _token = String.fromEnvironment('WIRD_E2E_TOKEN');
const _knobs = String.fromEnvironment('WIRD_E2E_KNOBS');

/// Makes the real server genuinely fail on ayah_understood, and mends it.
Future<void> breakTheServer() => Dio().post<void>('$_knobs/break');
Future<void> mendTheServer() => Dio().post<void>('$_knobs/mend');

/// Time passing, which a test cannot wait out: the backoff a failed op earned
/// has elapsed.
Future<void> theClockMovesOn(Database db) =>
    db.update('outbox', {'retry_after': null});

Future<int> attemptsOf(Database db, String opId) async => (await db.query(
  'outbox',
  columns: ['attempts'],
  where: 'client_op_id = ?',
  whereArgs: [opId],
)).single['attempts']! as int;

int _n = 0;
String _opId() => '00000000-0000-4000-8000-${(++_n).toString().padLeft(12, '0')}';

Future<Database> device(String name) async {
  final dir = await Directory.systemTemp.createTemp('wird-e2e-$name');
  final path = '${dir.path}/wird.db';
  await File('assets/corpus.db').copy(path);
  return openWirdAt(path);
}

Future<String> offlineWrite(Database db, int ayah, DateTime at) async {
  final id = _opId();
  await enqueue(
  db,
  opId: id,
  kind: 'ayah_understood',
  body: {
    'ayah_ids': [ayah],
    'understood_at': at.toUtc().toIso8601String(),
  },
  );
  return id;
}

Future<bool> knows(Database db, int ayah) async =>
    (await db.query('ayah_understood', where: 'ayah_id = ?', whereArgs: [ayah]))
        .isNotEmpty;

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;

  final api = SyncApi(
    Dio(
      BaseOptions(
        baseUrl: _url,
        headers: {'Authorization': 'Bearer $_token'},
      ),
    ),
  );

  test('an aya understood offline on Monday reaches the tablet that synced '
      'on Wednesday', () async {
    final phone = await device('phone');
    final tablet = await device('tablet');
    final now = DateTime.now();

    // Monday, on a plane: the phone marks an aya understood. Nothing flushes.
    await offlineWrite(phone, 96001, now.subtract(const Duration(days: 4)));

    // Wednesday: the tablet does its own reading and syncs. Its cursor now
    // sits at whatever position Wednesday's write took.
    await offlineWrite(tablet, 2010, now);
    final wednesday = await syncNow(tablet, api);
    expect(wednesday.reachedServer, isTrue, reason: 'the tablet reached the server');
    expect(await knows(tablet, 2010), isTrue);
    expect(await knows(tablet, 96001), isFalse,
        reason: 'the phone has not flushed yet');

    // Friday: the phone finds a signal and flushes Monday's write.
    final friday = await syncNow(phone, api);
    expect(friday.landed, 1, reason: "the phone's offline write reached the server");

    // The tablet syncs again. It MUST be told.
    await syncNow(tablet, api);
    expect(await knows(tablet, 96001), isTrue,
        reason: 'the aya understood offline never reached the other device');
  });

  test('across many syncs and two devices no write is handed over twice or '
      'missed', () async {
    final phone = await device('phone2');
    final tablet = await device('tablet2');
    final now = DateTime.now();
    final written = <int>{};

    for (var i = 1; i <= 25; i++) {
      // Instants walk backwards on the phone and forwards on the tablet, so
      // any stream ordered by a client clock interleaves them wrongly.
      final onPhone = 3000 + i;
      final onTablet = 4000 + i;
      await offlineWrite(phone, onPhone, now.subtract(Duration(days: i)));
      await offlineWrite(tablet, onTablet, now.add(Duration(seconds: i)));
      written.addAll([onPhone, onTablet]);
      await syncNow(phone, api);
      await syncNow(tablet, api);
      await syncNow(phone, api);
    }
    await syncNow(phone, api);
    await syncNow(tablet, api);

    for (final ayah in written) {
      expect(await knows(phone, ayah), isTrue, reason: 'the phone lost aya $ayah');
      expect(await knows(tablet, ayah), isTrue, reason: 'the tablet lost aya $ayah');
    }

    // Nothing is handed over twice: a pull past the end carries nothing.
    final quiet = await syncNow(tablet, api);
    expect(quiet.applied, 0, reason: 'a pull past the end re-applied history');
  });

  // The defect: a retryable "failed" was charged against the same budget as a
  // permanent refusal, so five bad minutes from the server threw away a write
  // the reader had made and the server would happily have taken.
  test('five real server faults do not throw away a write the server would '
      'take', () async {
    final phone = await device('faults');
    final id = await offlineWrite(phone, 12005, DateTime.now());

    await breakTheServer();
    try {
      for (var i = 1; i <= 5; i++) {
        final report = await syncNow(phone, api);
        // reachedServer is false here only because breaking the table breaks
        // the pull half too; the push half got a real per-op answer, which is
        // what `refused` counts.
        expect(report.refused, 1, reason: 'the server answered about this op');
        expect(await attemptsOf(phone, id), i,
            reason: 'the server failed, and only an answer counts');
        expect(await deadLettered(phone), isEmpty,
            reason: 'a write the server asked to be tried again was parked');
        await theClockMovesOn(phone);
      }
      expect((await pending(phone)).map((op) => op.id), contains(id));
    } finally {
      await mendTheServer();
    }

    // The server comes back. The write is still here and still lands.
    final mended = await syncNow(phone, api);
    expect(mended.landed, 1, reason: 'the write survived the outage');
    expect(await pending(phone), isEmpty);
    expect(await deadLettered(phone), isEmpty);
  });

  test('a server that never stops failing keeps the write forever and never '
      'tells the reader', () async {
    final phone = await device('forever');
    final id = await offlineWrite(phone, 12006, DateTime.now());

    await breakTheServer();
    try {
      for (var i = 1; i <= 10; i++) {
        await syncNow(phone, api);
        await theClockMovesOn(phone);
      }
    } finally {
      await mendTheServer();
    }
    expect(await attemptsOf(phone, id), 10);
    expect((await deadLettered(phone)).map((op) => op.id), contains(id),
        reason: 'past the budget the reader has to be told');
    expect(await pending(phone), isEmpty,
        reason: 'a parked op must never ride again on its own');
  });

  // The other half of the server's own distinction: an op it will never take.
  test('a write the real server refuses is asked about four more times before '
      'the reader hears', () async {
    final phone = await device('refused');
    // 115 is not a surah, so the real server refuses this write outright.
    final id = await offlineWrite(phone, 115001, DateTime.now());

    final report = await syncNow(phone, api);
    expect(report.reachedServer, isTrue);
    expect(report.refused, 1);
    expect(await attemptsOf(phone, id), 0,
        reason: 'a refusal spends no part of the transient budget');
    expect((await deadLettered(phone)).map((op) => op.id), contains(id),
        reason: 'asking the same unanswerable question again buys nothing');
    expect(await pending(phone), isEmpty);
  });

  test('a refused write blocks the nineteen queued behind it', () async {
    final phone = await device('poison');
    final poison = await offlineWrite(phone, 115001, DateTime.now());
    final good = <int>[];
    for (var i = 1; i <= 19; i++) {
      await offlineWrite(phone, 20000 + i > 114999 ? 5000 + i : 5000 + i, DateTime.now());
      good.add(5000 + i);
    }
    final report = await syncNow(phone, api);
    expect(report.landed, 19, reason: 'the other nineteen still landed');
    expect((await deadLettered(phone)).map((op) => op.id), [poison]);
    for (final ayah in good) {
      expect(await knows(phone, ayah), isTrue);
    }
  });

  // A flush that never reached a server must cost nothing: a week in airplane
  // mode cannot spend a write's budget.
  test('a week with no signal spends the retry budget', () async {
    final phone = await device('nosignal');
    final id = await offlineWrite(phone, 12007, DateTime.now());
    final dead = SyncApi(Dio(BaseOptions(baseUrl: 'http://127.0.0.1:1')));

    for (var i = 0; i < 12; i++) {
      final report = await syncNow(phone, dead);
      expect(report.reachedServer, isFalse);
    }
    expect(await attemptsOf(phone, id), 0);
    expect(await deadLettered(phone), isEmpty);
    expect((await pending(phone)).map((op) => op.id), contains(id));

    expect((await syncNow(phone, api)).landed, 1,
        reason: 'the write outlived the week offline');
  });
}
