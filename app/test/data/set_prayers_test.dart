import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wird/data/db.dart';
import 'package:wird/data/sets.dart';

import '../corpus.dart';

/// Everything the reader owns, gone. The corpus is what ships in the bundle
/// and survives; a reinstall is the user tables emptied and nothing else.
Future<void> reinstall(Database db) async {
  for (final table in [
    'ayah_understood',
    'user_prefs',
    'outbox',
    'set_prayers',
    'sets',
    'set_span',
  ]) {
    await db.delete(table);
  }
}

void main() {
  late Database db;

  setUp(() async => db = await testCorpus());

  test('a reinstall prays the same range and the server is told it is a '
      'second set', () async {
    final before = (await nextSet(db, ReadingOrder.nuzul))!;
    await recordSetPrayed(db, before);
    final first = (await db.query('sets')).single['id'];

    await reinstall(db);
    final after = (await nextSet(db, ReadingOrder.nuzul))!;
    await recordSetPrayed(db, after);

    expect((await db.query('sets')).single['id'], first);
    expect(
      after.id,
      before.id,
      reason: 'the id is derived from the range, so it survives the wipe',
    );
  });

  test('a second device praying the same range creates a set of its own',
      () async {
    final set = (await nextSet(db, ReadingOrder.nuzul))!;

    expect(
      setIdFor(ReadingOrder.nuzul, set.ayas.first.id, set.ayas.last.id),
      set.id,
      reason: 'any device with the same corpus derives this id and no other',
    );
    expect(
      setIdFor(ReadingOrder.mushaf, set.ayas.first.id, set.ayas.last.id),
      isNot(set.id),
      reason: 'the reading order is half of what names a set',
    );
    expect(set.id, matches(RegExp(r'^[0-9a-f-]{36}$')));
    expect(set.id[14], '5', reason: 'a version 5 uuid, which is the derived kind');
  });

  test('praying one set twice records it as two sets', () async {
    final set = (await nextSet(db, ReadingOrder.nuzul))!;

    await recordSetPrayed(db, set);
    await recordSetPrayed(db, set);

    expect((await db.query('sets')).length, 1);
    expect((await db.query('set_prayers')).length, 2);
    expect(await prayersOnSet(db, set.id), 2);
  });

  test('the prayer op names a set the server has never heard of', () async {
    final set = (await nextSet(db, ReadingOrder.nuzul))!;

    await recordSetPrayed(db, set);

    final op = (await db.query('outbox')).single;
    expect(op['kind'], 'set_prayed');
    final body = jsonDecode(op['body']! as String) as Map<String, dynamic>;
    expect(
      body.keys,
      containsAll([
        'set_id',
        'start_ayah_id',
        'end_ayah_id',
        'reading_order',
        'prayed_at',
      ]),
      reason: 'one op, carrying the range the server upserts the set from',
    );
    expect(body['set_id'], set.id);
    expect(body['id'], op['client_op_id']);
    expect(
      DateTime.parse(body['prayed_at'] as String).isUtc,
      isTrue,
      reason: 'the server reads RFC 3339 and refuses a zoneless instant',
    );
  });
}
