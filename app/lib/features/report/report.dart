import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../../data/db.dart';
import '../../data/outbox.dart';
import '../../data/senses.dart';

/// The three kinds the server accepts. A fourth word is a body its column
/// constraint refuses, and a refusal is permanent — so the words are an enum
/// here rather than whatever the screen happened to label a button.
enum ReportKind { bug, request, improvement }

/// The build a report was written from.
///
/// Passed in by the release build (`--dart-define=WIRD_VERSION`), read from
/// the pubspec's own version line, so the number is written in one place
/// (ADR 0022). Any other build says `dev`: a report from a build nobody
/// released should not claim a version that was.
const appVersion = String.fromEnvironment('WIRD_VERSION', defaultValue: 'dev');

/// The platform the report was written on, in the three words the server
/// knows. Android, iOS and macOS are what this app builds for.
///
/// ponytail: `defaultTargetPlatform` rather than `dart:io`, so a widget test
/// reports what a device would. A fourth build target is a report the server
/// refuses until its constraint learns the word.
String get platformName => defaultTargetPlatform.name.toLowerCase();

/// The longest report the server will take: `reports.body` is
/// `CHECK (length(body) <= 4000)`, and a CHECK violation is a refusal, which
/// is permanent — the op parks and the reader's longest report is the one
/// that never arrives. So the limit is met on the screen, where a reader can
/// see it, rather than in an answer nobody reads.
///
/// ponytail: Dart counts UTF-16 units and Postgres counts characters, so a
/// report written in emoji is cut shorter here than the server would cut it.
/// Count runes if anybody ever reports in them.
const reportMaxChars = 4000;

/// What a reader does not have to type, read once so the screen can show the
/// reader exactly the values that will be sent.
///
/// [locale] is the language code of the screen the reader was looking at —
/// `Localizations.localeOf(context).languageCode` — or '' where nobody knows.
Future<Map<String, Object?>> reportContext(
  DatabaseExecutor db, {
  required String screen,
  required String locale,
}) async {
  final meta = await db.query(
    'corpus_meta',
    columns: ['corpus_version'],
    limit: 1,
  );
  return {
    'app_version': appVersion,
    'platform': platformName,
    'screen': screen,
    'corpus_version': meta.isEmpty ? 0 : meta.first['corpus_version']! as int,
    // Which sense pack the reader was looking at. Empty when no pack has been
    // fetched: '' is the server's own word for a device that did not say
    // (migration 00009), and a report is never worth refusing over it.
    'sense_version': await installedSenseVersion(db) ?? '',
    // The language the screen was drawn in. A sense is written twice, and a
    // verdict on the French says nothing about the English.
    'locale': locale,
    // Which sentence a verdict was about, filled in by [judgeSense]. Empty on
    // every other report, and still drawn, because the screen shows the reader
    // every key that leaves the phone.
    'sense_hash': '',
  };
}

/// The first 12 hex characters of the sha256 of [sense], exactly as stored —
/// the whole `; `-joined string, before the screen splits it into lines.
///
/// The server hashes the same string to tell which draft a verdict was on, so
/// a redraft is judged afresh rather than inheriting the old one's thumbs.
/// Trimming or splitting here would make every hash miss.
String senseHash(String sense) =>
    sha256.convert(utf8.encode(sense)).toString().substring(0, 12);

/// The route the reader came from, as a word a person reading the report can
/// use. Home is a slash on its own and says nothing.
String screenName(String route) => route == '/' ? 'home' : route.substring(1);

/// Queues one report and returns.
///
/// It leaves by the outbox, like marking a set understood and for the same
/// reason: a reader who hits a bug on a plane writes it there and it flushes
/// when a signal returns. Nothing here touches the network, so no screen can
/// end up waiting on one.
///
/// The body carries the reader's own words and the context above, and nothing
/// else. What they were reading, what they have understood and what they
/// wrote in their notes stay on the phone.
Future<void> sendReport(
  DatabaseExecutor db, {
  required ReportKind kind,
  required String body,
  required Map<String, Object?> context,
}) => enqueue(
  db,
  opId: newOpId(),
  kind: 'report_written',
  body: {
    'kind': kind.name,
    'body': body.trim(),
    ...context,
    'created_at': DateTime.now().toUtc().toIso8601String(),
  },
);

/// A reader's verdict on the sense drawn for one root.
///
/// The senses are written from lexicography and checked against the Qurʼan for
/// contradiction, and neither of those can tell whether a sense is COMPLETE —
/// ر ح م shipped without "womb" past a gate scoring six terms, and a reader
/// found it in one sitting. So the reader is the reviewer, and this is how a
/// verdict leaves the phone.
///
/// **This names the root, and [sendReport] above says what a reader was reading
/// stays here.** The exception is narrow and it is the reader's own: they pressed
/// a button about a root in front of them, which is them choosing to send it.
/// Nothing else travels — not the aya they were in, not the word they tapped, not
/// what they have understood. A judgement with no subject would be a number
/// nobody could act on, which is the only reason the exception exists.
///
/// ponytail: `improvement` rather than a fourth [ReportKind], because the
/// server's column constraint refuses an unknown word and a migration to carry
/// one bit is not worth it.
///
/// [sense] is the sentence the reader judged, as stored, and `sense_hash` is
/// what says WHICH sentence that was: `sense_version` names a pack, and a pack
/// carries two languages and outlives a redraft of any one root. The locale
/// comes from [context], which the caller built from the same `readIn` that
/// picked [sense] — a verdict filed under the wrong language would be a vote
/// on a sentence the reader never saw.
///
/// The op and the device's own memory of the verdict ([senseJudged]) commit
/// together: a verdict remembered but never queued would hide the thumbs from
/// a reader whose answer nobody received.
Future<void> judgeSense(
  Database db, {
  required String root,
  required String sense,
  required bool good,
  required Map<String, Object?> context,
}) {
  final hash = senseHash(sense);
  return db.transaction((txn) async {
    await sendReport(
      txn,
      kind: ReportKind.improvement,
      body: 'sense ${good ? 'good' : 'bad'}: $root',
      context: {...context, 'sense_hash': hash},
    );
    await txn.insert('sense_verdicts', {
      'root': root,
      'locale': context['locale'] as String? ?? '',
      'sense_hash': hash,
      'verdict': good ? 'good' : 'bad',
      'judged_at': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  });
}

/// Whether this reader has already judged [sense] for [root] in [locale]. A
/// redraft is a new hash and a new question, and so is the other language.
Future<bool> senseJudged(
  DatabaseExecutor db, {
  required String root,
  required String locale,
  required String sense,
}) async => (await db.query(
  'sense_verdicts',
  where: 'root = ? AND locale = ? AND sense_hash = ?',
  whereArgs: [root, locale, senseHash(sense)],
  limit: 1,
)).isNotEmpty;
