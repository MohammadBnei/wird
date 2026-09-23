import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../../data/db.dart';
import '../../data/outbox.dart';

/// The three kinds the server accepts. A fourth word is a body its column
/// constraint refuses, and a refusal is permanent — so the words are an enum
/// here rather than whatever the screen happened to label a button.
enum ReportKind { bug, request, improvement }

/// The build a report was written from.
///
/// ponytail: the number is written here and pinned to pubspec.yaml by a test.
/// Reading it at runtime means package_info_plus, a dependency and a platform
/// channel, to learn one string that changes when a human edits pubspec.
const appVersion = '1.0.0';

/// The platform the report was written on, in the three words the server
/// knows. Android, iOS and macOS are what this app builds for.
///
/// ponytail: `defaultTargetPlatform` rather than `dart:io`, so a widget test
/// reports what a device would. A fourth build target is a report the server
/// refuses until its constraint learns the word.
String get platformName => defaultTargetPlatform.name.toLowerCase();

/// What a reader does not have to type, read once so the screen can show the
/// reader exactly the values that will be sent.
Future<Map<String, Object?>> reportContext(
  Database db, {
  required String screen,
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
  };
}

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
  Database db, {
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
