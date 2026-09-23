import 'dart:convert';

import 'package:sqflite/sqflite.dart';

/// The queue every write leaves by. There is no second path: a write that went
/// straight to the network and timed out after the server had already applied
/// it would end up queued as well, and then be sent twice.
///
/// A row here is one op, keyed by the id the device minted for it. That id is
/// what makes a replay a replay, on the device and again on the server.

/// The server draws a line this file honours: a `refused` op is one that
/// "will never succeed however often it is sent", a `failed` one is the
/// server "having a bad minute, and worth retrying". They get different
/// endings.
///
/// A refusal parks the op at once. Sending a malformed body a second time
/// asks the same question and gets the same answer, so the four extra rounds
/// buy nothing and only delay the reader hearing about it.
///
/// A transient failure is retried, with the delay doubling each time, and only
/// parks after this many answers. Ten spans a little over half a day of a
/// server that keeps answering and keeps failing — longer than an outage,
/// shorter than the reader's memory of what they wrote. Past that it is not a
/// bad minute, and leaving the write to rot unmentioned is the worse ending.
///
/// Only an answer counts as an attempt. A flush that never reached a server —
/// no signal, a captive portal, a dead socket — leaves the count alone, so a
/// week in airplane mode cannot throw away the reader's writes.
const maxAttempts = 10;

/// A minute, then two, then four, capped at about four hours. Without this a
/// network that flaps once a second spends the whole budget before the server
/// has finished restarting.
Duration retryIn(int attempts) =>
    Duration(minutes: 1 << (attempts - 1).clamp(0, 8));

/// One queued write, as it will go over the wire.
class PendingOp {
  const PendingOp({
    required this.id,
    required this.kind,
    required this.body,
    required this.attempts,
  });

  final String id;
  final String kind;
  final Map<String, dynamic> body;

  /// How many times the server has answered "failed" for this op.
  final int attempts;
}

/// What the server said about one op. The four statuses are the server's own.
class OpVerdict {
  const OpVerdict(this.id, this.status, {this.reason = ''});

  factory OpVerdict.fromJson(Map<String, dynamic> json) => OpVerdict(
    json['client_op_id'] as String,
    json['status'] as String,
    reason: json['reason'] as String? ?? '',
  );

  final String id;
  final String status;
  final String reason;

  /// Applied and duplicate are both "the server has it": a duplicate is this
  /// op's own earlier flush, which is exactly what the op id is for.
  bool get landed => status == 'applied' || status == 'duplicate';

  /// Permanent. Anything else the server answers — `failed`, or a status this
  /// build has never heard of — is read as transient, because retrying a write
  /// that cannot land costs a delay and dropping one that could costs the
  /// write.
  bool get permanent => status == 'refused';
}

/// Adds the columns an outbox written before there was anything to flush to
/// does not have: how often the server has failed this op, when it may ride
/// again, and whether it has been parked for the reader.
Future<void> ensureOutboxAttempts(Database db) async {
  final columns = await db.rawQuery('PRAGMA table_info(outbox)');
  final have = {for (final c in columns) c['name'] as String};
  if (!have.contains('attempts')) {
    await db.execute(
      'ALTER TABLE outbox ADD COLUMN attempts INTEGER NOT NULL DEFAULT 0',
    );
  }
  if (!have.contains('retry_after')) {
    await db.execute('ALTER TABLE outbox ADD COLUMN retry_after TEXT');
  }
  if (!have.contains('dead_at')) {
    await db.execute('ALTER TABLE outbox ADD COLUMN dead_at TEXT');
  }
}

/// Queues one write. Called inside whatever transaction is already changing
/// the local rows, so the local change and the op that carries it to the
/// server commit together or not at all.
///
/// A second call under the same [opId] is the same press: the row is already
/// there and nothing is queued twice.
Future<void> enqueue(
  DatabaseExecutor db, {
  required String opId,
  required String kind,
  required Map<String, dynamic> body,
}) => db.insert('outbox', {
  'client_op_id': opId,
  'kind': kind,
  'body': jsonEncode(body),
  'created_at': DateTime.now().toIso8601String(),
}, conflictAlgorithm: ConflictAlgorithm.ignore);

/// The ops a flush should carry: oldest first, never one the reader has
/// already been told about, and never one that is still serving its backoff.
/// The limit stays well under the server's cap of 500 per batch, which is
/// refused whole and would leave the queue stuck. A parked op stays in the
/// table — it is the reader's to retry or discard from settings — but it never
/// rides again on its own, because that is how one poison op blocks a queue
/// forever.
Future<List<PendingOp>> pending(Database db, {int limit = 200}) async {
  await ensureOutboxAttempts(db);
  final rows = await db.query(
    'outbox',
    where: 'dead_at IS NULL AND (retry_after IS NULL OR retry_after <= ?)',
    whereArgs: [DateTime.now().toIso8601String()],
    orderBy: 'created_at, client_op_id',
    limit: limit,
  );
  return rows.map(_op).toList();
}

/// The ops that will not ride again on their own: refused once, or failed
/// until the budget ran out. Settings shows these; nothing mid-prayer ever
/// does.
Future<List<PendingOp>> deadLettered(Database db) async {
  await ensureOutboxAttempts(db);
  final rows = await db.query(
    'outbox',
    where: 'dead_at IS NOT NULL',
    orderBy: 'created_at',
  );
  return rows.map(_op).toList();
}

/// Records what the server said. An op it has is dropped; an op it will never
/// take is parked for the reader; an op it failed on waits out a doubling
/// delay and rides again, until the budget is spent and it too is parked.
///
/// Ops the answer does not mention are left exactly as they were — a truncated
/// response must not drop a write.
Future<void> settle(Database db, List<OpVerdict> verdicts) =>
    db.transaction((txn) async {
      final now = DateTime.now();
      for (final verdict in verdicts) {
        if (verdict.landed) {
          await txn.delete(
            'outbox',
            where: 'client_op_id = ?',
            whereArgs: [verdict.id],
          );
        } else if (verdict.permanent) {
          await txn.update(
            'outbox',
            {'dead_at': now.toIso8601String()},
            where: 'client_op_id = ?',
            whereArgs: [verdict.id],
          );
        } else {
          final attempts = await _attempts(txn, verdict.id) + 1;
          await txn.update(
            'outbox',
            {
              'attempts': attempts,
              'retry_after': now.add(retryIn(attempts)).toIso8601String(),
              if (attempts >= maxAttempts) 'dead_at': now.toIso8601String(),
            },
            where: 'client_op_id = ?',
            whereArgs: [verdict.id],
          );
        }
      }
    });

Future<int> _attempts(DatabaseExecutor db, String opId) async {
  final rows = await db.query(
    'outbox',
    columns: ['attempts'],
    where: 'client_op_id = ?',
    whereArgs: [opId],
    limit: 1,
  );
  return rows.isEmpty ? 0 : (rows.first['attempts'] as int?) ?? 0;
}

/// Sends a parked op back into the queue, because the reader asked. It rides
/// on the next flush rather than waiting out the delay it had earned.
Future<void> retry(Database db, String opId) => db.update(
  'outbox',
  {'attempts': 0, 'retry_after': null, 'dead_at': null},
  where: 'client_op_id = ?',
  whereArgs: [opId],
);

/// Clears one parked op, for the settings panel that shows it.
Future<void> discard(Database db, String opId) =>
    db.delete('outbox', where: 'client_op_id = ?', whereArgs: [opId]);

PendingOp _op(Map<String, Object?> row) => PendingOp(
  id: row['client_op_id']! as String,
  kind: row['kind']! as String,
  body: jsonDecode(row['body']! as String) as Map<String, dynamic>,
  attempts: (row['attempts'] as int?) ?? 0,
);

/// Local timestamps are written the way the rest of the app writes them —
/// `DateTime.now().toIso8601String()`, which carries no zone. The server reads
/// RFC 3339 and would refuse that, so an op body says the same instant in UTC.
String wireTime(String local) =>
    DateTime.parse(local).toUtc().toIso8601String();
