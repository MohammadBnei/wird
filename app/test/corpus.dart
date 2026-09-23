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
