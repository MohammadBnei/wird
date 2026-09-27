import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wird/data/db.dart';

Database? _db;

/// The tables the app puts beside the corpus, asked of the database rather
/// than listed here. A list had to be kept in step with the schema by hand
/// and was not: `display_prefs` arrived, nothing emptied it, and every test
/// after one that changed the display ran against the preference it left
/// behind — a gloss switched off in one test was still off three tests later.
Set<String> _userTables = const {};

Future<Set<String>> _tablesIn(Database db) async => {
  for (final row in await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type = 'table' "
    "AND name NOT LIKE 'sqlite_%'",
  ))
    row['name']! as String,
};

/// The real bundled corpus, copied once into a temp file so the user tables
/// can be written, and emptied of user state before each test. Tests run
/// against the shipped 24 MB corpus on purpose: a set generator that walks a
/// hand-built fixture proves nothing about the walk the reader gets.
Future<Database> testCorpus() async {
  if (_db == null) {
    sqfliteFfiInit();
    // No isolate: a widget test runs in a fake-async zone, and a reply from a
    // background isolate never arrives there, so the screen would hang loading.
    databaseFactory = databaseFactoryFfiNoIsolate;
    _sweepUpAfterOlderRuns();
    final dir = await Directory.systemTemp.createTemp('wird-corpus');
    final path = '${dir.path}/wird.db';
    await File('assets/corpus.db').copy(path);
    final corpus = await openDatabase(path);
    final shipped = await _tablesIn(corpus);
    await corpus.close();
    _db = await openWirdAt(path);
    _userTables = (await _tablesIn(_db!)).difference(shipped);
  }
  for (final table in _userTables) {
    await _db!.delete(table);
  }
  return _db!;
}

/// How screen 1a heads an aya: the sūra's name and the aya's number. What a
/// test asserts on to say the reader landed where a reference pointed.
Future<String> surahAndAya(Database db, int ayahId) async {
  final rows = await db.query(
    'surahs',
    columns: ['name_en'],
    where: 'id = ?',
    whereArgs: [ayahId ~/ 1000],
  );
  return '${rows.single['name_en']} ${ayahId % 1000}';
}

/// Throws away the corpus copies older runs left behind.
///
/// Each test PROCESS copies the 24 MB corpus into a temp directory of its own,
/// and `flutter test` starts one per test file, so a full run leaks about a
/// gigabyte. Left alone that reached 342 GB across 13,780 directories and took
/// two runs down with `No space left on device` before anybody looked at
/// $TMPDIR. No teardown can do this job: [_db] is cached per process rather
/// than per test, so an `addTearDown` registered on the first test of a file
/// would delete the corpus the rest of the file is still reading.
///
/// **Age, not ownership.** Sibling processes of this very run hold their own
/// directories while this one sweeps, and a sweep that cannot tell them apart
/// would delete a live corpus out from under a passing test. An hour is far
/// longer than any test process lives and far shorter than the gap between
/// runs that matters.
///
/// ponytail: swept on the way in, never on the way out, for the reason
/// [VoiceModel.sweepUpAfterAnOlderModel] gives about the same shape — and it
/// never throws, because a temp directory that cannot be tidied is not a reason
/// to fail a suite.
void _sweepUpAfterOlderRuns() {
  final stale = DateTime.now().subtract(const Duration(hours: 1));
  try {
    for (final entry in Directory.systemTemp.listSync()) {
      if (entry is! Directory) continue;
      if (!entry.path.split(Platform.pathSeparator).last.startsWith(
        'wird-corpus',
      )) {
        continue;
      }
      try {
        if (entry.statSync().modified.isBefore(stale)) {
          entry.deleteSync(recursive: true);
        }
      } on Object {
        // Another run's, already gone, or not ours to remove.
      }
    }
  } on Object {
    // Nothing here is worth failing a suite over.
  }
}
