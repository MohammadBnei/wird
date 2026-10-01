import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wird/data/db.dart';

import '../corpus.dart';

Future<int> rows(Database db, String table) async =>
    (await db.rawQuery('SELECT COUNT(*) AS n FROM $table')).single['n']! as int;

void main() {
  late Database db;

  setUp(() async => db = await testCorpus());

  test('a replayed mark counts the set understood twice', () async {
    final opId = newOpId();

    await markSetUnderstood(db, opId, [96001, 96002, 96003]);
    await markSetUnderstood(db, opId, [96001, 96002, 96003]);

    expect(await rows(db, 'outbox'), 1);
    expect(await rows(db, 'ayah_understood'), 3);
  });

  test('the set is understood on the device but nothing is queued for the '
      'server, so a phone that syncs later loses the prayer', () async {
    await markSetUnderstood(db, newOpId(), [96001, 96002]);

    final op = (await db.query('outbox')).single;
    final body = jsonDecode(op['body']! as String) as Map<String, dynamic>;

    expect(op['kind'], 'ayah_understood');
    expect(body['ayah_ids'], [96001, 96002]);
    expect(op['client_op_id'], matches(RegExp(r'^[0-9a-f-]{36}$')));
  });

  test('a set marked on a plane is recorded at the moment the reader read it, '
      'not at the moment the flush happened to reach a server', () async {
    final before = DateTime.now().toUtc();
    await markSetUnderstood(db, newOpId(), [96001]);

    final body =
        jsonDecode((await db.query('outbox')).single['body']! as String)
            as Map<String, dynamic>;
    final understoodAt = DateTime.parse(body['understood_at'] as String);

    expect(understoodAt.isUtc, isTrue, reason: 'the server reads RFC 3339');
    expect(
      understoodAt.difference(before).inMinutes,
      lessThan(1),
      reason: 'the op carries no time of its own, so the server will stamp it',
    );
  });

  test('two sets share one op id, so flushing the second overwrites the '
      'first', () async {
    await markSetUnderstood(db, newOpId(), [96001]);
    await markSetUnderstood(db, newOpId(), [96002]);

    expect(await rows(db, 'outbox'), 2);
  });
}
