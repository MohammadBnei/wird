import 'package:record/record.dart';
import 'package:sqflite/sqflite.dart';

/// What the reader answered when Settings asked for the microphone.
///
/// Voice-follow is off by default. The answer is recorded here so the
/// in-prayer screen never has to ask: a permission dialog raised mid-prayer is
/// the one thing that screen may not do.
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
/// ponytail: `record` is here for the recitation stream anyway and its
/// `hasPermission` raises the same system prompt, so voice-follow costs one
/// dependency rather than two. Reach for `permission_handler` the first time
/// this needs to tell a refusal apart from a refusal the reader can only undo
/// in the system settings, and offer to open them.
///
/// A platform with no microphone to offer throws rather than refusing, and
/// that is a different sentence on the Settings screen: refused is the
/// reader's answer and can be asked again, unavailable is the device's.
Future<MicPermission> askForMic(
  Database db, {
  Future<bool> Function()? ask,
}) async {
  MicPermission answer;
  try {
    answer = await (ask ?? _prompt)()
        ? MicPermission.granted
        : MicPermission.denied;
  } on Object {
    answer = MicPermission.unavailable;
  }
  await setMicPermission(db, answer);
  return answer;
}

Future<bool> _prompt() async {
  final mic = AudioRecorder();
  try {
    return await mic.hasPermission();
  } finally {
    await mic.dispose();
  }
}
