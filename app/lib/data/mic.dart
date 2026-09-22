import 'package:sqflite/sqflite.dart';

/// What the reader answered when screen 1a asked for the microphone.
///
/// Voice-follow is a later phase and off by default. The answer is recorded
/// here so the in-prayer screen never has to ask: a permission dialog raised
/// mid-prayer is the one thing that screen may not do.
enum MicPermission { notAsked, granted, denied, unavailable }

Future<MicPermission> micPermission(Database db) async {
  final rows = await db.query('mic_consent', columns: ['state'], limit: 1);
  final stored = rows.isEmpty ? null : rows.first['state'];
  return MicPermission.values.firstWhere(
    (p) => p.name == stored,
    orElse: () => MicPermission.notAsked,
  );
}

Future<void> setMicPermission(Database db, MicPermission state) => db.insert(
  'mic_consent',
  {
    'id': 1,
    'state': state.name,
    'answered_at': DateTime.now().toIso8601String(),
  },
  conflictAlgorithm: ConflictAlgorithm.replace,
);

/// Raises the system microphone prompt and records what came back.
///
/// Nothing in the stack table can raise that prompt — `permission_handler` is
/// the package for it, and adding one is an ask-first decision — so this build
/// answers `unavailable` rather than recording a consent the reader never
/// gave. The stored answer and every caller are already the shape the real
/// request needs.
Future<MicPermission> askForMic(Database db) async {
  const answer = MicPermission.unavailable;
  await setMicPermission(db, answer);
  return answer;
}
