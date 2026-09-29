import 'package:dio/dio.dart';
import 'package:sqflite/sqflite.dart';

import 'flush.dart';

/// The senses, fetched rather than bundled.
///
/// The Qur'an, the morphology and the timings come from upstream sources and
/// ship inside the binary. A sense is Wird's own sentence, it is corrected
/// continuously by the reader's own thumb, and freezing it into a 24 MB asset
/// put every correction behind a store release. So the server holds the senses
/// and this file brings them down and writes them as rows into the one database
/// the app already has — no second file, no ATTACH, no swap, and the reader's
/// own tables untouched. ADR 0010.
///
/// Two calls, because the reader picks when bytes move: [sensesOnOffer] asks
/// with a HEAD whether there is anything new, and [installSenses] is what the
/// answered prompt runs.
///
/// The route is open and the Dio these build carries no token: requiring an
/// account to learn what a root means would put the sense — and the thumb that
/// corrects it — out of reach of the readers likeliest to need both.

/// One root's sense as the wire carries it. `fr` is optional because the route
/// may serve English alone.
typedef _Sense = ({String root, String en, String? fr});

/// Everything a fetch brings back. `source` and `basis` are pack-level on the
/// wire and per-row in SQLite — the same two strings against all 1,642 rows,
/// which is what leaves the read in `root_repo.dart` unchanged.
typedef _SensePack = ({
  String version,
  String? source,
  String? basis,
  List<_Sense> senses,
});

/// The version the server is offering, or null when this device already has it.
///
/// A HEAD, so the check itself moves no bytes: the body is ~800 KB and a
/// foreground check that fetched it would be a download per unlock.
///
/// ponytail: `over` is the seam a test hands a loopback socket through. The
/// default is [syncOrigin] rather than a literal of its own, so a
/// `--dart-define=WIRD_ORIGIN` debug build points the senses at the same
/// laptop as the queue — and so `qa.sh`'s URL ledger has one row to account
/// for, not two.
Future<String?> sensesOnOffer(Database db, {Dio? over}) async {
  final answer = await (over ?? _wird()).head<void>(_route);
  final offered = _tag(answer.headers.value('etag'));
  if (offered == null || offered.isEmpty) return null;
  return offered == await _installedVersion(db) ? null : offered;
}

/// Fetches the pack and replaces what this device holds, in one transaction.
/// Returns the version installed, or null when nothing was.
///
/// No atomic-rename dance like `installCorpus`: that earned one because it was
/// a non-transactional 24 MB file copy. This is a real sqflite transaction, so
/// a phone killed mid-write rolls back on the next open.
///
/// The body is checked **before** the transaction opens. Dio buffers and
/// decodes the whole answer, so a truncated or captive-portal 200 throws while
/// the reader's senses are still where they were.
Future<String?> installSenses(Database db, {Dio? over}) async {
  final answer = await (over ?? _wird()).get<dynamic>(_route);
  final pack = _thePack(answer);
  return db.transaction((txn) => _writePack(txn, pack));
}

const _route = '/v1/senses';

Dio _wird() => Dio(BaseOptions(baseUrl: syncOrigin));

/// The pack as rows, inside whatever executor the caller opened.
///
/// Split off [installSenses] so the transaction is the only thing the public
/// call owns. `root_notes` is a *shipped* table and `app/test/corpus.dart`
/// empties only the reader's own tables between tests, so a committed rewrite
/// of it outlives the test that made it.
Future<String?> _writePack(DatabaseExecutor txn, _SensePack pack) async {
  // ponytail: an empty pack is not an error — the route never 404s, and
  // `{"version":"1-0-0","senses":[]}` is what an unseeded environment answers —
  // but it is nothing to install either. Applying it would delete every sense
  // the reader has, with no bundled floor to fall back to and no recovery short
  // of clearing the app's data; and recording the version would tell the screen
  // a pack had been fetched, so 1,642 roots would say "nobody wrote a sense for
  // this" about a server that has not been seeded. Nothing is written and the
  // reader keeps what they have. The next HEAD offers the seeded version,
  // because the version is a hash of the rows.
  if (pack.senses.isEmpty) return null;

  // Scoped to the root-level rows. There are none of the other kind today, but
  // `word_id` and the join that reads it exist, and a per-word note is not the
  // server's to replace.
  await txn.delete('root_notes', where: 'word_id IS NULL');
  final rows = txn.batch();
  for (final sense in pack.senses) {
    rows.insert('root_notes', {
      'root_letters': sense.root,
      'note': sense.en,
      // ponytail: stored, and drawn by nothing. `note_fr` is a shipped column
      // no screen reads (docs/walkthrough.md:391); the locale read is its own
      // change, and dropping the French on the floor here would mean fetching
      // it again the day that lands.
      'note_fr': sense.fr,
      'source': pack.source,
      'basis': pack.basis,
      // No evidence words: the served drafts were not read off a word list,
      // and the basis prose is what says so.
      'evidence': null,
    });
  }
  await rows.commit(noResult: true);
  await txn.insert('sense_pack', {
    'id': 1,
    'version': pack.version,
    'fetched_at': DateTime.now().toIso8601String(),
  }, conflictAlgorithm: ConflictAlgorithm.replace);
  return pack.version;
}

Future<String?> _installedVersion(DatabaseExecutor db) async {
  final rows = await db.query('sense_pack', columns: ['version'], limit: 1);
  return rows.isEmpty ? null : rows.first['version'] as String?;
}

/// An ETag as the wire spells it. Quotes and the weak marker are the header's
/// syntax, not part of the version, and a proxy is free to add them.
String? _tag(String? etag) {
  if (etag == null) return null;
  var tag = etag.trim();
  if (tag.startsWith('W/')) tag = tag.substring(2);
  if (tag.length > 1 && tag.startsWith('"') && tag.endsWith('"')) {
    tag = tag.substring(1, tag.length - 1);
  }
  return tag;
}

/// A 200 carrying something that is not this contract's JSON — a captive
/// portal answers every request with its own sign-in page and a 200, so the
/// device is not talking to Wird at all.
///
/// ponytail: `sync.dart` has the same guard and keeps it private. Two eight-line
/// throws beat making one of them a public door that `qa.sh` then has to excuse.
Never _notTheContract(Response<dynamic> answer) => throw DioException(
  requestOptions: answer.requestOptions,
  response: answer,
  message: 'the answer was not the JSON the senses contract promises',
);

/// The whole body, checked. Anything missing, empty or of the wrong shape
/// throws here, where nothing has been written yet.
_SensePack _thePack(Response<dynamic> answer) {
  final body = answer.data;
  if (body is! Map) _notTheContract(answer);
  final version = body['version'];
  final served = body['senses'];
  if (version is! String || version.isEmpty || served is! List) {
    _notTheContract(answer);
  }
  final senses = <_Sense>[];
  for (final row in served) {
    if (row is! Map) _notTheContract(answer);
    final root = row['root'];
    final en = row['en'];
    final fr = row['fr'];
    if (root is! String || root.isEmpty || en is! String || en.isEmpty) {
      _notTheContract(answer);
    }
    if (fr != null && fr is! String) _notTheContract(answer);
    senses.add((root: root, en: en, fr: fr as String?));
  }
  return (
    version: version,
    source: body['source'] as String?,
    basis: body['basis'] as String?,
    senses: senses,
  );
}
