import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wird/data/root_repo.dart';
import 'package:wird/data/senses.dart';

import '../corpus.dart';
import 'fake_wird.dart';

/// A pack as the route writes one.
Map<String, dynamic> pack(
  String version,
  List<Map<String, dynamic>> senses, {
  String basis = 'Nobody has checked this.',
}) => {
  'version': version,
  'source': 'Wird',
  'attribution': 'Wird, CC BY 4.0',
  'basis': basis,
  'senses': senses,
};

Map<String, dynamic> sense(String root, String en, [String? fr]) => {
  'root': root,
  'en': en,
  'fr': ?fr,
};

/// The senses the server owns, counted apart from any note a word carries.
Future<int> served(Database db) async =>
    (await db.rawQuery(
      'SELECT COUNT(*) AS n FROM root_notes WHERE word_id IS NULL',
    )).single['n']!
        as int;

/// Notes keyed to one word rather than to the root, which the server does not
/// own and must not take with it.
Future<int> perWord(Database db) async =>
    (await db.rawQuery(
      'SELECT COUNT(*) AS n FROM root_notes WHERE word_id IS NOT NULL',
    )).single['n']!
        as int;

Future<String?> installed(Database db) async {
  final rows = await db.query('sense_pack', columns: ['version'], limit: 1);
  return rows.isEmpty ? null : rows.first['version'] as String?;
}

/// This file rewrites `root_notes`, which the corpus *ships* — so
/// `app/test/corpus.dart` does not empty it between tests and what one test
/// applies the next one still sees. That is why every test here installs the
/// pack it asserts on rather than leaning on the 523 bundled senses, and why
/// the one test that writes a word-level row takes it back out again.
void main() {
  late Database db;
  late FakeWird server;

  setUp(() async {
    db = await testCorpus();
    server = await FakeWird.start();
  });

  tearDown(() async => server.stop());

  test('a phone that has never fetched cannot tell that apart from a root '
      'nobody wrote a sense for', () async {
    expect(await installed(db), isNull);
    expect((await rootReading(db, 'صبر'))!.sensesFetched, isFalse);

    server.senses = pack('1-1-1', [sense('صبر', 'to bear')]);
    expect(await installSenses(db, over: server.dio), '1-1-1');
    expect((await rootReading(db, 'صبر'))!.sensesFetched, isTrue);
  });

  test('the device re-downloads 800 KB it already has, because the check '
      'compares nothing', () async {
    server.senses = pack('2-2-2', [sense('صبر', 'to bear')]);
    expect(await sensesOnOffer(db, over: server.dio), '2-2-2');
    await installSenses(db, over: server.dio);
    expect(await sensesOnOffer(db, over: server.dio), isNull);

    server.senses = pack('3-3-3', [sense('صبر', 'to hold out')]);
    expect(await sensesOnOffer(db, over: server.dio), '3-3-3');

    // The header's own syntax is not part of the version, and a proxy on the
    // way is free to add it.
    server.sensesEtag = '"3-3-3"';
    expect(await sensesOnOffer(db, over: server.dio), '3-3-3');
    server.sensesEtag = 'W/"2-2-2"';
    expect(await sensesOnOffer(db, over: server.dio), isNull);
  });

  test('the check and the fetch travel signed, so a reader with no account '
      'can never learn what a root means', () async {
    // Also the proof that `sense_pack` is one of the tables corpus.dart empties
    // between tests: the test above installed 2-2-2 into this same database.
    expect(await installed(db), isNull);
    server.senses = pack('4-4-4', [sense('جمع', 'to gather', 'rassembler')]);
    await sensesOnOffer(db, over: server.dio);
    await installSenses(db, over: server.dio);
    // This Dio is the test's own; what keeps the production one unsigned is
    // that senses.dart builds it without the AuthHeader interceptor that
    // flush.dart puts on the queue's.
    expect(server.bearers, isNotEmpty);
    expect(server.bearers, everyElement(isNull));
  });

  test('a fetched sense arrives with nothing saying whose reading it is, and '
      'the roots the pack drops keep the prose it replaced', () async {
    server.senses = pack('5-5-5', [
      sense('جمع', 'to gather', 'rassembler'),
    ], basis: 'Wird wrote this and no person has checked it.');
    expect(await installSenses(db, over: server.dio), '5-5-5');
    expect(await installed(db), '5-5-5');
    expect(await served(db), 1);

    final gathered = (await rootReading(db, 'جمع'))!;
    expect(gathered.coreSense, 'to gather');
    expect(gathered.senseSource, 'Wird');
    expect(gathered.senseBasis, contains('no person has checked it'));
    // The served drafts were not read off a word list, so there is nothing to
    // put under "the words this was read from".
    expect(gathered.senseEvidence, isEmpty);

    // A full replace, not a merge: صبر carried a bundled sense and the pack
    // does not name it, so it has none. Anything else and a correction that
    // *removes* a sense could never reach a reader.
    expect((await rootReading(db, 'صبر'))!.coreSense, isNull);
    expect((await rootReading(db, 'صبر'))!.sensesFetched, isTrue);
  });

  test('the pack takes a note keyed to one word with it, though the server '
      'does not own one', () async {
    await db.insert('root_notes', {
      'root_letters': 'صبر',
      'word_id': 2153010,
      'note': 'what this one word does here',
    });
    server.senses = pack('6-6-6', [sense('جمع', 'to gather')]);
    await installSenses(db, over: server.dio);

    expect(await perWord(db), 1);
    await db.delete('root_notes', where: 'word_id IS NOT NULL');
  });

  test('an empty pack wipes every sense on the phone, with nothing bundled to '
      'fall back on', () async {
    server.senses = pack('7-7-7', [sense('جمع', 'to gather')]);
    await installSenses(db, over: server.dio);

    // What an unseeded laptop behind --dart-define=WIRD_ORIGIN answers, and it
    // is a 200: the route never 404s.
    server.senses = pack('1-0-0', []);
    expect(await installSenses(db, over: server.dio), isNull);
    expect(await served(db), 1);
    expect((await rootReading(db, 'جمع'))!.coreSense, 'to gather');
    expect(await installed(db), '7-7-7');
  });

  test('an empty pack on a phone with nothing to lose is recorded as a fetch, '
      'so every root says nobody wrote a sense rather than nothing arrived',
      () async {
    await db.delete('root_notes');
    server.senses = pack('1-0-0', []);
    expect(await installSenses(db, over: server.dio), isNull);
    expect(await installed(db), isNull);
    expect((await rootReading(db, 'جمع'))!.sensesFetched, isFalse);
  });

  test('a captive portal answers 200 with its own sign-in page and the '
      'reader loses every sense they had', () async {
    server.senses = pack('8-8-8', [sense('جمع', 'to gather')]);
    await installSenses(db, over: server.dio);

    server.insteadAPortal = '<html><body>Hotel wifi: sign in</body></html>';
    await expectLater(
      installSenses(db, over: server.dio),
      throwsA(isA<DioException>()),
    );
    expect(await served(db), 1);
    expect(await installed(db), '8-8-8');
  });

  test('a row with no sense in it is written as a root whose meaning is the '
      'empty string', () async {
    server.senses = pack('9-9-9', [sense('جمع', 'to gather')]);
    await installSenses(db, over: server.dio);

    for (final broken in [
      pack('a', [
        {'root': 'جمع'},
      ]),
      pack('b', [
        {'root': '', 'en': 'to gather'},
      ]),
      pack('c', [
        {'root': 'جمع', 'en': ''},
      ]),
      pack('d', [
        {'root': 'جمع', 'en': 'to gather', 'fr': 7},
      ]),
      {'version': '', 'senses': <Map<String, dynamic>>[]},
      {'version': 'e', 'senses': 'all of them'},
    ]) {
      server.senses = broken;
      await expectLater(
        installSenses(db, over: server.dio),
        throwsA(isA<DioException>()),
        reason: '$broken',
      );
    }
    expect(await served(db), 1);
    expect(await installed(db), '9-9-9');
  });

  // The failure the empty-pack guard was written for, arriving the way the guard
  // does not see: a pack that is not empty, whose roots this corpus does not
  // record. Every row installs, none of them joins to anything, and the version
  // is recorded — so the device believes it is current, never offers again, and
  // the reader is left with 1,642 roots all saying nobody wrote a sense for
  // them, with no bundled floor and no way back short of clearing app data.
  //
  // Root letters are Arabic and this repo already keeps foldArabic because
  // identity across pipelines has bitten it before, so a server and a corpus
  // disagreeing about a spelling is the ordinary case, not the exotic one.
  test('a pack of roots this corpus never heard of takes the senses it has '
      'with it, and tells the reader they are up to date', () async {
    final db = await testCorpus();
    final server = await FakeWird.start();
    addTearDown(server.stop);

    // Seeded rather than leaning on the bundle: testCorpus caches its database
    // for the whole file and root_notes is a shipped table, so an earlier test
    // here has already replaced what the bundle shipped.
    server.senses = pack('6-6-6', [sense('صبر', 'to bind oneself fast')]);
    expect(await installSenses(db, over: server.dio), '6-6-6');
    final before = await served(db);

    server.senses = pack('7-7-7', [
      sense('zzz', 'not a root in this corpus'),
      sense('qqq', 'nor this one'),
    ]);
    expect(await installSenses(db, over: server.dio), isNull);

    expect(await served(db), before, reason: 'the reader kept what they had');
    expect(await installed(db), '6-6-6', reason: 'so the next check offers again');
    expect((await rootReading(db, 'صبر'))?.coreSense, 'to bind oneself fast');
  });

  // The same invariant from the other side: a pack whose roots DO match lands,
  // even though the bundle is replaced wholesale on the way.
  test('a pack the corpus recognises replaces what the bundle shipped', () async {
    final db = await testCorpus();
    final server = await FakeWird.start();
    addTearDown(server.stop);

    server.senses = pack('8-8-8', [sense('صبر', 'to bind oneself fast')]);
    expect(await installSenses(db, over: server.dio), '8-8-8');

    expect(await served(db), 1);
    expect((await rootReading(db, 'صبر'))?.coreSense, 'to bind oneself fast');
  });
}
