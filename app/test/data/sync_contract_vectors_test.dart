import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wird/data/db.dart';
import 'package:wird/data/kept_repo.dart';
import 'package:wird/data/outbox.dart';
import 'package:wird/data/sets.dart';
import 'package:wird/data/sync.dart';
import 'package:wird/features/report/report.dart';

import '../corpus.dart';

/// The second file both halves answer to, beside the set id vectors. The
/// server suite reads these same rows from
/// server/internal/store/sync_contract_vectors_test.go. Neither suite computes
/// what it asserts, so the two cannot agree with themselves while disagreeing
/// with each other — which is exactly how the set id shipped wrong.
const _contractPath = '../docs/adr/0002-sync-contract-vectors.json';

Map<String, dynamic> _contract() {
  final file = File(_contractPath);
  expect(
    file.existsSync(),
    isTrue,
    reason: 'without the shared contract nothing checks the device against '
        'the server',
  );
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

List<Map<String, dynamic>> _section(String name) {
  final vectors =
      ((_contract()[name] as Map)['vectors'] as List).cast<Object>();
  expect(
    vectors,
    isNotEmpty,
    reason: 'an empty $name section would pass without checking anything',
  );
  return [for (final v in vectors) (v as Map).cast<String, dynamic>()];
}

/// One page of changes, served once. The push half is never reached: these
/// tests start with an empty queue.
class _Stream {
  _Stream._(this._server, this._changes) {
    unawaited(_serve());
  }

  static Future<_Stream> serving(List<Map<String, dynamic>> changes) async =>
      _Stream._(
        await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
        changes,
      );

  final HttpServer _server;
  List<Map<String, dynamic>> _changes;

  Dio get dio => Dio(BaseOptions(baseUrl: 'http://127.0.0.1:${_server.port}'));

  Future<void> stop() => _server.close(force: true);

  Future<void> _serve() async {
    await for (final request in _server) {
      final page = {
        'changes': _changes,
        'cursor': 'seq:${_changes.length}',
        'more': false,
      };
      _changes = [];
      request.response
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(page));
      unawaited(request.response.close());
    }
  }
}

Map<String, dynamic> _change(Map<String, dynamic> vector) {
  final row = (vector['row'] as Map).cast<String, dynamic>();
  return {
    'kind': vector['kind'],
    'id': '${row['id'] ?? 'prefs'}',
    'at': '2026-09-23T07:20:00Z',
    'row': row,
  };
}

void main() {
  late Database db;

  setUp(() async {
    db = await testCorpus();
    await ensureKeptTable(db);
    await db.delete('kept_items');
    await db.execute('DROP TABLE IF EXISTS sync_state');
  });

  // The failure: the device names a field one thing and the server's decoder
  // another. That decoder disallows unknown fields, so it refuses the whole
  // body — and a refusal is permanent, so the reader's note, prayer or
  // understood aya is parked and never arrives. The names here are checked in
  // rather than read off the device's own code, so a rename on either side of
  // the wire reddens this.
  test('every op the device builds carries the field names the server will '
      'accept, so no write is refused forever', () async {
    for (final vector in _section('op_bodies')) {
      if (vector['built_by_device'] != true) continue;
      final kind = vector['kind'] as String;
      await db.delete('outbox');

      switch (kind) {
        case 'ayah_understood':
          await markSetUnderstood(db, newOpId(), [1001, 1002]);
        case 'kept_upsert':
          await keep(db, kind: KeptKind.note, body: 'the mercy named twice');
        case 'kept_delete':
          final id = await keep(db, kind: KeptKind.note, body: 'to drop');
          await db.delete('outbox');
          await forget(db, id);
        case 'set_prayed':
          await recordSetPrayed(db, (await nextSet(db, ReadingOrder.nuzul))!);
        case 'prefs_set':
          await setReadingOrder(db, ReadingOrder.mushaf);
        case 'report_written':
          await sendReport(
            db,
            kind: ReportKind.bug,
            body: 'the audio stops at the end of the set',
            context: await reportContext(db, screen: 'prayer'),
          );
        default:
          fail('the shared contract carries an op kind "$kind" that no write '
              'path on this device builds, so nothing checks it');
      }

      final row = (await db.query('outbox')).single;
      expect(row['kind'], kind);
      final body = jsonDecode(row['body']! as String) as Map<String, dynamic>;
      expect(
        body.keys.toSet(),
        (vector['body'] as Map).keys.cast<String>().toSet(),
        reason: '${vector['label']}: the server refuses a body whose keys are '
            'not exactly these, and the refusal is permanent',
      );
    }
  });

  // The failure: the server renames one of its four answers. The device reads
  // an unknown word as transient, so it either retries a write that can never
  // land until the budget runs out and parks it anyway, or parks a write that
  // would have landed. Both suites stayed green through that until this file.
  test('the device parks and retries on the outcome words the server actually '
      'answers with', () {
    for (final vector in _section('op_results')) {
      final verdict = OpVerdict('op-1', vector['status'] as String);
      expect(
        verdict.landed,
        vector['landed'],
        reason: '${vector['label']}: the device disagrees about whether the '
            'server has this write',
      );
      expect(
        verdict.permanent,
        vector['permanent'],
        reason: '${vector['label']}: the device disagrees about whether this '
            'write can ever land',
      );
    }
  });

  // The failure: a second device prays a set and this one never counts it,
  // because the change arrives under a kind the apply switch has no arm for
  // and is dropped in silence. "The fourth prayer on this set" then reads
  // differently on the phone and on the tablet.
  test('every table the server streams changes for is written on this device, '
      'so a second device\'s prayers are counted here too', () async {
    final vectors = _section('change_kinds');
    final server = await _Stream.serving([for (final v in vectors) _change(v)]);
    addTearDown(server.stop);

    final report = await syncNow(db, SyncApi(server.dio));

    expect(report.unknownKinds, isEmpty);
    expect(
      report.applied,
      vectors.length,
      reason: 'a kind the server streams did not reach a local table',
    );
    expect(
      await prayersOnSet(db, '6cb8c394-ae9a-5092-a2ea-8f88749613c7'),
      1,
      reason: 'the prayer the other device made is not counted on this one',
    );
    expect(
      (await db.query('sets')).single['reading_order'],
      'mushaf',
      reason: 'the set the other device prayed did not reach this one',
    );
    expect((await db.query('ayah_understood')), hasLength(1));
    expect((await db.query('kept_items')), hasLength(1));
    expect((await db.query('user_prefs')).single['reading_order'], 'nuzul');
  });

  // The failure: the reader prays once, the server hands that prayer back on
  // the next pull, and the device counts it a second time — so the screen says
  // the fifth prayer on a set that has carried four. The ids are the device's
  // own, which is what makes the round trip idempotent, and the row shapes are
  // the ones the shared contract pins.
  test('a prayer the reader made comes back from the server and is counted '
      'twice', () async {
    final set = (await nextSet(db, ReadingOrder.nuzul))!;
    await recordSetPrayed(db, set);
    final body =
        jsonDecode((await db.query('outbox')).single['body']! as String)
            as Map<String, dynamic>;
    await db.delete('outbox');

    final server = await _Stream.serving([
      {
        'kind': 'sets',
        'id': body['set_id'],
        'at': body['prayed_at'],
        'row': {
          'id': body['set_id'],
          'ordinal': 1,
          'start_ayah_id': body['start_ayah_id'],
          'end_ayah_id': body['end_ayah_id'],
          'reading_order': body['reading_order'],
          'created_at': body['prayed_at'],
        },
      },
      {
        'kind': 'set_prayers',
        'id': body['id'],
        'at': body['prayed_at'],
        'row': {
          'id': body['id'],
          'set_id': body['set_id'],
          'prayer_name': '',
          'prayed_at': body['prayed_at'],
        },
      },
    ]);
    addTearDown(server.stop);

    await syncNow(db, SyncApi(server.dio));

    expect(await prayersOnSet(db, set.id), 1);
    expect((await db.query('sets')), hasLength(1));
  });

  // The failure: the server starts streaming a kind this build has never heard
  // of — a rename, or a table added after this app shipped — and the old
  // default arm returned zero, so the device stopped writing that table and
  // neither side said anything.
  test('a change kind this build cannot apply is raised rather than dropped in '
      'silence', () async {
    final server = await _Stream.serving([
      {
        'kind': 'root_known',
        'id': 'r1',
        'at': '2026-09-23T07:20:00Z',
        'row': {'root_letters': 'ح م د'},
      },
    ]);
    addTearDown(server.stop);

    await expectLater(
      syncNow(db, SyncApi(server.dio)),
      throwsA(isA<AssertionError>()),
    );
  });

  // The failure: the two halves spell a reading order differently. The word is
  // half of what a set id is derived from, so a third spelling is not a bad
  // value — it is a set no other device can name, and a prayer the server
  // refuses forever.
  test('the device can send only the reading-order words the server accepts',
      () {
    expect(
      {for (final order in ReadingOrder.values) order.name},
      ((_contract()['reading_orders'] as Map)['vectors'] as List)
          .cast<String>()
          .toSet(),
      reason: 'a word on one side of this that is not on the other is a set '
          'the other half cannot name',
    );
  });
}
