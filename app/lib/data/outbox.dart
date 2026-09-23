import 'dart:convert';

import 'package:sqflite/sqflite.dart';

/// The queue every write leaves by. There is no second path: a write that went
/// straight to the network and timed out after the server had already applied
/// it would end up queued as well, and then be sent twice.
///
/// A row here is one op, keyed by the id the device minted for it. That id is
/// what makes a replay a replay, on the device and again on the server.

/// How many times an op the server answered for is sent again before the
/// reader is told about it instead. Five, per the plan.
///
/// Only an answer counts as an attempt. A flush that never reached a server —
/// no signal, a captive portal, a dead socket — leaves the count alone, so a
/// week in airplane mode cannot throw away the reader's writes.
const maxAttempts = 5;

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

  /// How many answers this op has already been refused by.
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
}

/// Adds the `attempts` column to an outbox written before there was anything
/// to flush to.
Future<void> ensureOutboxAttempts(Database db) async {
  final columns = await db.rawQuery('PRAGMA table_info(outbox)');
  if (columns.any((c) => c['name'] == 'attempts')) return;
  await db.execute(
    'ALTER TABLE outbox ADD COLUMN attempts INTEGER NOT NULL DEFAULT 0',
  );
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

/// The ops a flush should carry: oldest first, and never one the reader has
/// already been told about. The limit stays well under the server's cap of
/// 500 per batch, which is refused whole and would leave the queue stuck. A dead-lettered op stays in the table — it is the
/// reader's to retry or discard from settings — but it never rides again on
/// its own, because that is how one poison op blocks a queue forever.
Future<List<PendingOp>> pending(Database db, {int limit = 200}) async {
  await ensureOutboxAttempts(db);
  final rows = await db.query(
    'outbox',
    where: 'attempts < ?',
    whereArgs: [maxAttempts],
    orderBy: 'created_at, client_op_id',
    limit: limit,
  );
  return rows.map(_op).toList();
}

/// The ops the server refused five times. Settings shows these; nothing
/// mid-prayer ever does.
Future<List<PendingOp>> deadLettered(Database db) async {
  await ensureOutboxAttempts(db);
  final rows = await db.query(
    'outbox',
    where: 'attempts >= ?',
    whereArgs: [maxAttempts],
    orderBy: 'created_at',
  );
  return rows.map(_op).toList();
}

/// Records what the server said. An op it has is dropped; an op it answered
/// for and would not take counts one attempt against its five.
///
/// Ops the answer does not mention are left exactly as they were — a truncated
/// response must not drop a write.
Future<void> settle(Database db, List<OpVerdict> verdicts) =>
    db.transaction((txn) async {
      for (final verdict in verdicts) {
        if (verdict.landed) {
          await txn.delete(
            'outbox',
            where: 'client_op_id = ?',
            whereArgs: [verdict.id],
          );
        } else {
          await txn.rawUpdate(
            'UPDATE outbox SET attempts = attempts + 1 WHERE client_op_id = ?',
            [verdict.id],
          );
        }
      }
    });

/// Clears one dead-lettered op, for the settings screen that shows it.
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
