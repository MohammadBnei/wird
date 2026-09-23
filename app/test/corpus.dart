import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wird/data/db.dart';

Database? _db;

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
    _db = await openWirdAt(path);
  }
  for (final table in [
    'ayah_understood',
    'user_prefs',
    'outbox',
    'mic_consent',
    'set_prayers',
    'sets',
    'set_span',
  ]) {
    await _db!.delete(table);
  }
  return _db!;
}
