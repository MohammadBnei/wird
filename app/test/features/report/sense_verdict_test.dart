import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:wird/features/report/report.dart';

import '../../corpus.dart';

/// Whether a reader's verdict on a root's sense leaves the phone, and whether it
/// takes anything else with it.
///
/// The senses are written from lexicography and checked against the Qurʼan for
/// contradiction, and neither can see whether a sense is complete — ر ح م shipped
/// without "womb" past a gate scoring six terms. So the reader is the reviewer,
/// and a verdict that never reaches anybody is a button that does nothing.
void main() {
  late Database db;
  setUp(() async {
    db = await testCorpus();
    await db.delete('outbox');
  });

  Future<Map<String, Object?>> only() async {
    final rows = await db.query('outbox');
    expect(rows, hasLength(1), reason: 'one verdict, one queued op');
    return jsonDecode(rows.single['body']! as String) as Map<String, Object?>;
  }

  test('a verdict is queued rather than sent, and names the root', () async {
    await judgeSense(
      db,
      root: 'رحم',
      good: false,
      context: await reportContext(db, screen: 'study'),
    );
    final body = await only();
    // The root is the one thing this may carry that sendReport's own doc says
    // stays on the phone. It is here because a verdict with no subject is a
    // number nobody can act on, and because the reader pressed a button about
    // this root.
    expect(body['body'], 'sense bad: رحم');
    expect(body['kind'], 'improvement');
    // sense_version is what says WHICH sense was judged: the senses arrive over
    // HTTP, so two readers on the same corpus can be shown two different
    // sentences and both report the same corpus_version.
    expect(body['sense_version'], isA<String>());
    expect(body['corpus_version'], isA<int>());
    expect(body['screen'], 'study');
  });

  test('a good verdict and a bad one are told apart', () async {
    await judgeSense(db, root: 'صبر', good: true, context: const {});
    expect((await only())['body'], 'sense good: صبر');
  });

  test('nothing but the verdict, the root and the build travels', () async {
    await judgeSense(
      db,
      root: 'صبر',
      good: true,
      context: await reportContext(db, screen: 'study'),
    );
    final body = await only();
    expect(
      body.keys.toSet(),
      {'kind', 'body', 'app_version', 'platform', 'screen', 'corpus_version',
        'sense_version', 'created_at'},
      reason: 'a new key here is reader data leaving the phone; add it on '
          'purpose or not at all',
    );
  });
}
