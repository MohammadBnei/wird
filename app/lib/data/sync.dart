import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:sqflite/sqflite.dart';

import 'kept_repo.dart';
import 'outbox.dart';

/// Sync happens *around* the prayer, never during it.
///
/// Nothing here is awaited by a screen. The write path is [enqueue], which
/// touches the local database and returns; [syncNow] is run by whatever
/// notices the network came back. So a reader mid-prayer with no signal is
/// never waiting on this file, and there is no code path by which it can put a
/// spinner or an error in front of them.

/// One row as the server now holds it. A kept item with `deleted_at` set is
/// the tombstone: it is the row, not its absence, that stops this device
/// handing a deleted note straight back.
class Change {
  const Change(this.kind, this.id, this.row);

  factory Change.fromJson(Map<String, dynamic> json) => Change(
    json['kind'] as String,
    json['id'] as String,
    (json['row'] as Map).cast<String, dynamic>(),
  );

  final String kind;
  final String id;
  final Map<String, dynamic> row;
}

class ChangePage {
  const ChangePage(this.changes, this.cursor, this.more);

  factory ChangePage.fromJson(Map<String, dynamic> json) => ChangePage(
    [
      for (final c in json['changes'] as List)
        Change.fromJson((c as Map).cast<String, dynamic>()),
    ],
    json['cursor'] as String? ?? '',
    json['more'] as bool? ?? false,
  );

  final List<Change> changes;
  final String cursor;
  final bool more;
}

/// The two endpoints, and nothing else. Reads that a screen makes are local.
class SyncApi {
  const SyncApi(this.dio);

  final Dio dio;

  Future<List<OpVerdict>> push(List<PendingOp> ops) async {
    final answer = await dio.post<dynamic>(
      '/v1/sync',
      data: {
        'ops': [
          for (final op in ops)
            {'client_op_id': op.id, 'kind': op.kind, 'body': op.body},
        ],
      },
    );
    final results = _contract(answer)['results'];
    if (results is! List) _notTheContract(answer);
    return [
      for (final r in results)
        OpVerdict.fromJson((r as Map).cast<String, dynamic>()),
    ];
  }

  Future<ChangePage> pull(String cursor) async {
    final answer = await dio.get<dynamic>(
      '/v1/changes',
      queryParameters: {'since': cursor},
    );
    final page = _contract(answer);
    if (page['changes'] is! List) _notTheContract(answer);
    return ChangePage.fromJson(page);
  }
}

/// A 200 carrying something that is not this contract's JSON. The common one
/// is a captive portal, which answers every request with its own sign-in page
/// and a 200 — so the device is not talking to Wird at all.
///
/// It is raised as a [DioException] because that is what it is: the flush did
/// not reach the server. The alternative is what this used to do — read the
/// body anyway and throw a [TypeError] straight out of [syncNow], past the
/// one catch that knows the queue is intact and past every caller.
Never _notTheContract(Response<dynamic> answer) => throw DioException(
  requestOptions: answer.requestOptions,
  response: answer,
  message: 'the answer was not the JSON the sync contract promises',
);

Map<String, dynamic> _contract(Response<dynamic> answer) {
  final body = answer.data;
  return body is Map ? body.cast<String, dynamic>() : _notTheContract(answer);
}

class SyncReport {
  const SyncReport({
    this.reachedServer = false,
    this.landed = 0,
    this.refused = 0,
    this.applied = 0,
    this.deadLettered = 0,
    this.unknownKinds = const {},
  });

  /// False when the flush never got an answer. The queue is untouched and the
  /// reader has lost nothing; the next reconnect tries again.
  final bool reachedServer;
  final int landed;

  /// Answers that were not "the server has it" — a refusal, or a failure the
  /// server asked to be retried.
  final int refused;

  /// Rows the other device wrote that this one now holds.
  final int applied;

  /// Ops the reader has to be shown in settings: the server refused them
  /// outright, or failed on them until their retry budget ran out.
  final int deadLettered;

  /// Change kinds the server streamed that this build applies none of. Empty
  /// in every build that is not older than the server it is talking to.
  final Set<String> unknownKinds;
}

/// Pushes everything queued, then pulls everything the other device wrote.
///
/// Push first: the pull then answers with our own writes already in it, so
/// last-write-wins compares against what the server actually holds.
Future<SyncReport> syncNow(Database db, SyncApi api) async {
  await ensureKeptTable(db);
  await ensureOutboxAttempts(db);
  await _ensureSyncState(db);

  var landed = 0;
  var refused = 0;
  var applied = 0;
  // One attempt per op per reconnect. An op the server failed on stays in the
  // queue, and without this it would be picked up again by the very next
  // round and spend its whole retry budget inside one flush.
  final sent = <String>{};
  final unknownKinds = <String>{};
  try {
    while (true) {
      final queue = [
        for (final op in await pending(db))
          if (!sent.contains(op.id)) op,
      ];
      if (queue.isEmpty) break;
      sent.addAll(queue.map((op) => op.id));
      final verdicts = await api.push(queue);
      await settle(db, verdicts);
      landed += verdicts.where((v) => v.landed).length;
      refused += verdicts.where((v) => !v.landed).length;
    }

    var cursor = await _cursor(db);
    while (true) {
      final page = await api.pull(cursor);
      applied += await _apply(db, page.changes, unknownKinds);
      cursor = page.cursor;
      await _saveCursor(db, cursor);
      if (!page.more) break;
    }
  } on DioException {
    // No answer, or no server. The queue is exactly as it was.
    return SyncReport(
      landed: landed,
      refused: refused,
      applied: applied,
      deadLettered: (await deadLettered(db)).length,
      unknownKinds: unknownKinds,
    );
  }
  return SyncReport(
    reachedServer: true,
    landed: landed,
    refused: refused,
    applied: applied,
    deadLettered: (await deadLettered(db)).length,
    unknownKinds: unknownKinds,
  );
}

/// Writes what the server holds onto this device, row by row.
///
/// Reconciliation is last-write-wins on `updated_at`. Where that is the wrong
/// rule it is not applied:
///
///   * `ayah_understood` is monotonic, not last-write-wins. An aya understood
///     on either device is understood, and there is no op that un-marks one —
///     so the older row wins by being left alone rather than overwritten with
///     a later timestamp.
///   * `user_prefs` genuinely is last-write-wins, and that is a real loss: set
///     the reading order on the phone and then open a tablet that has been
///     asleep for a week, and the tablet's older answer can arrive later than
///     the phone's. It is one field, visible on screen, and the reader can set
///     it again — which is why it is accepted rather than versioned.
///   * `sets` and `set_prayers` are inserted and never updated. A set's id is
///     derived from its range and order, so the same range is the same row on
///     every device and there is nothing to reconcile; a prayer is an event
///     that happened once. They used to be dropped on the floor, back when the
///     device had no tables to put them in — with the result that a phone
///     counted only the prayers it had made itself, and "the fourth prayer on
///     this set" was a different number on the tablet.
Future<int> _apply(
  Database db,
  List<Change> changes,
  Set<String> unknownKinds,
) async {
  var applied = 0;
  await db.transaction((txn) async {
    for (final change in changes) {
      applied += switch (change.kind) {
        'ayah_understood' => await _applyUnderstood(txn, change.row),
        'kept_items' => await _applyKept(txn, change.row),
        'sets' => await _applySet(txn, change.row),
        'set_prayers' => await _applySetPrayer(txn, change.row),
        'user_prefs' => await _applyPrefs(txn, change.row),
        _ => _unknownKind(change.kind, unknownKinds),
      };
    }
  });
  return applied;
}

/// A kind this build has never heard of. It used to be `_ => 0`: the device
/// stopped writing a whole table and said nothing, on either side of the wire.
///
/// The assert is what makes a renamed kind a failure while someone is still
/// in a position to fix it. It is stripped from a release build on purpose —
/// a reader whose phone is older than the server keeps syncing the kinds
/// it does understand, and the name is carried out in [SyncReport.unknownKinds]
/// rather than thrown at them mid-prayer.
int _unknownKind(String kind, Set<String> seen) {
  seen.add(kind);
  assert(
    false,
    'the server streams changes of kind "$kind" and this build applies none '
    'of them, so that table silently stops being written',
  );
  return 0;
}

Future<int> _applyUnderstood(Transaction txn, Map<String, dynamic> row) =>
    txn.insert('ayah_understood', {
      'ayah_id': row['ayah_id'],
      'understood_at': _local(row['understood_at'] as String),
    }, conflictAlgorithm: ConflictAlgorithm.ignore).then((_) => 1);

Future<int> _applyKept(Transaction txn, Map<String, dynamic> row) async {
  final id = row['id'] as String;
  final remote = DateTime.parse(row['updated_at'] as String);
  final mine = await txn.query(
    'kept_items',
    columns: ['updated_at'],
    where: 'id = ?',
    whereArgs: [id],
    limit: 1,
  );
  if (mine.isNotEmpty &&
      !remote.isAfter(DateTime.parse(mine.first['updated_at']! as String))) {
    return 0;
  }
  // The tombstone travels as a column, so a delete on the other device lands
  // here as a row that is present and dead rather than as a row that is gone
  // and gets recreated on the next pull.
  await txn.insert('kept_items', {
    'id': id,
    'kind': row['kind'],
    'ayah_id': row['ayah_id'],
    'root_letters': row['root_letters'],
    'body': row['body'] ?? '',
    'tags': _tags(row['tags']),
    'created_at': _local(row['created_at'] as String),
    'updated_at': _local(row['updated_at'] as String),
    'deleted_at': row['deleted_at'] == null
        ? null
        : _local(row['deleted_at'] as String),
  }, conflictAlgorithm: ConflictAlgorithm.replace);
  return 1;
}

/// The set itself. `ordinal` is the server's own numbering and has no column
/// here — the device names a set by the id derived from its range, and the
/// number a reader's sets are counted in is the server's to keep.
///
/// A prayer can only arrive after the set it names, because the server writes
/// both in one transaction and the stream is ordered by that, so the local
/// foreign key is never reached before its row exists.
Future<int> _applySet(Transaction txn, Map<String, dynamic> row) =>
    txn.insert('sets', {
      'id': row['id'],
      'start_ayah_id': row['start_ayah_id'],
      'end_ayah_id': row['end_ayah_id'],
      'reading_order': row['reading_order'],
      'created_at': _local(row['created_at'] as String),
    }, conflictAlgorithm: ConflictAlgorithm.ignore).then((_) => 1);

/// One prayer, which is what "the fourth prayer on this set" counts. There is
/// no `prayer_name` column: the app has never asked which of the five it was.
Future<int> _applySetPrayer(Transaction txn, Map<String, dynamic> row) =>
    txn.insert('set_prayers', {
      'id': row['id'],
      'set_id': row['set_id'],
      'prayed_at': _local(row['prayed_at'] as String),
    }, conflictAlgorithm: ConflictAlgorithm.ignore).then((_) => 1);

Future<int> _applyPrefs(Transaction txn, Map<String, dynamic> row) async {
  final remote = DateTime.parse(row['updated_at'] as String);
  final mine = await txn.query('user_prefs', columns: ['updated_at']);
  if (mine.isNotEmpty &&
      !remote.isAfter(DateTime.parse(mine.first['updated_at']! as String))) {
    return 0;
  }
  await txn.insert('user_prefs', {
    'id': 1,
    'reading_order': row['reading_order'],
    'updated_at': _local(row['updated_at'] as String),
  }, conflictAlgorithm: ConflictAlgorithm.replace);
  return 1;
}

/// Postgres hands `tags` over as a JSON array; the device keeps it as the
/// encoded string the kept list already reads.
String _tags(Object? tags) {
  final list = (tags as List?) ?? const [];
  return jsonEncode([for (final t in list) t as String]);
}

/// The wire speaks RFC 3339 in UTC; local rows are written in local time
/// without a zone, which is what the kept list and the progress ring parse.
String _local(String wire) =>
    DateTime.parse(wire).toLocal().toIso8601String();

Future<void> _ensureSyncState(Database db) => db.execute('''
  CREATE TABLE IF NOT EXISTS sync_state (
    id     INTEGER PRIMARY KEY CHECK (id = 1),
    cursor TEXT NOT NULL
  )''');

Future<String> _cursor(Database db) async {
  final rows = await db.query('sync_state', columns: ['cursor']);
  return rows.isEmpty ? '' : rows.first['cursor']! as String;
}

Future<void> _saveCursor(Database db, String cursor) => db.insert(
  'sync_state',
  {'id': 1, 'cursor': cursor},
  conflictAlgorithm: ConflictAlgorithm.replace,
);
