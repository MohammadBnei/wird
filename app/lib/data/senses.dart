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
  final installed = await _installedVersion(db);
  if (offered == null || offered.isEmpty) {
    // Something between here and the server dropped the header — nginx does it
    // when it gzips, Apache rewrites it. For a device that already holds a pack
    // that is a reason to do nothing. For one that holds none it would mean
    // never being offered anything at all, which is the blank screen this whole
    // path exists to avoid, so offer: [installSenses] takes the version from
    // the body and never from the header.
    return installed == null ? unknownSenseVersion : null;
  }
  return offered == installed ? null : offered;
}

/// What [sensesOnOffer] answers when the server did not say which version it
/// has and this device has none. It is never stored: whatever is installed is
/// named by the body.
const unknownSenseVersion = 'unknown';

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
  try {
    return await db.transaction((txn) => _writePack(txn, pack));
  } on _SensesNotForThisCorpus {
    // The transaction rolled back, so the reader still has what they had. This
    // is the server and this corpus disagreeing about what a root is called,
    // which no reader can act on and no retry can mend — so it answers null,
    // the way a check that found nothing does, rather than throwing out of a
    // foreground call.
    return null;
  }
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

  // The invariant is that the reader ends up with senses they can SEE, not that
  // the pack arrived non-empty. A pack of roots this corpus does not record
  // installs cleanly, joins to nothing, and leaves every root saying "nobody
  // wrote a sense for this" — with the version recorded, so the device believes
  // it is current and never offers again. There is no bundled floor to fall back
  // to and no recovery short of clearing the app's data.
  //
  // That is not hypothetical here: root letters are Arabic, this repo already
  // keeps `foldArabic` because identity across pipelines has bitten it before,
  // and nothing compares the server's root list to the corpus's. An empty pack
  // fails the same check, so it needs no separate guard.
  //
  // Throwing rolls the transaction back, so nothing is deleted and no version is
  // recorded: the next check offers the pack again.
  final visible = Sqflite.firstIntValue(await txn.rawQuery(
    'SELECT COUNT(*) FROM root_notes n JOIN roots r ON r.letters = n.root_letters '
    'WHERE n.word_id IS NULL',
  ));
  if (visible == null || visible == 0) {
    throw const _SensesNotForThisCorpus();
  }

  await txn.insert('sense_pack', {
    'id': 1,
    'version': pack.version,
    'fetched_at': DateTime.now().toIso8601String(),
  }, conflictAlgorithm: ConflictAlgorithm.replace);
  return pack.version;
}

/// A pack whose roots this corpus does not record. Thrown from inside the
/// transaction so the reader's senses survive it — see [_writePack].
class _SensesNotForThisCorpus implements Exception {
  const _SensesNotForThisCorpus();

  @override
  String toString() =>
      'the senses that arrived name no root this corpus records, so none of '
      'them could ever be read; the pack was not installed';
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
  // Keyed by root, last wins. `root_notes` has no primary key and the read at
  // root_repo.dart takes `limit: 1` with no order, so two rows for one root
  // would make which sense a reader sees unspecified. Deduping here rather than
  // with a unique index because an index on a shipped table is checked when the
  // database opens, and a corpus that failed it would take the whole app down
  // rather than one pack.
  final senses = <String, _Sense>{};
  for (final row in served) {
    if (row is! Map) _notTheContract(answer);
    final root = row['root'];
    final en = row['en'];
    final fr = row['fr'];
    if (root is! String || root.isEmpty || en is! String || en.isEmpty) {
      _notTheContract(answer);
    }
    if (fr != null && fr is! String) _notTheContract(answer);
    senses[root] = (root: root, en: en, fr: fr as String?);
  }
  // Through the same gate as the rows, not a bare cast. `source` and `basis` are
  // written into every row, so a number here threw a TypeError straight out of
  // installSenses — past the one catch that knows the reader's senses are
  // intact, which is the exact failure sync.dart's guard exists to prevent.
  final source = body['source'];
  final basis = body['basis'];
  if (source != null && source is! String) _notTheContract(answer);
  if (basis != null && basis is! String) _notTheContract(answer);
  return (
    version: version,
    source: source as String?,
    basis: basis as String?,
    senses: senses.values.toList(growable: false),
  );
}
