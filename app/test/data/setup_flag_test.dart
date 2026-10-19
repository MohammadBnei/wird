import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wird/data/db.dart';

void main() {
  late Directory dir;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });
  setUp(() async => dir = await Directory.systemTemp.createTemp('wird-setup'));
  tearDown(() => dir.delete(recursive: true));

  // The failure: an update puts every existing reader through the first-launch
  // setup, and folds the root panel they have always seen open.
  test('an install from before setup skips it and keeps its panel open',
      () async {
    final path = '${dir.path}/wird.db';
    final old = await openDatabase(path);
    await old.execute(
      'CREATE TABLE ayah_understood (ayah_id INTEGER PRIMARY KEY, '
      'understood_at TEXT NOT NULL)',
    );
    await old.close();

    final db = await openWirdAt(path);
    expect(await setupDone(db), isTrue);
    expect((await displayPrefs(db)).rootOpen, isTrue);
    await db.close();
  });

  // The failure: a new reader taps Start, and the second launch mistakes the
  // tables the first launch created for an old install — reopening the panel,
  // or skipping setup for someone who left it half way.
  test('a new install asks for setup until Start, and keeps its panel folded',
      () async {
    final path = '${dir.path}/wird.db';
    var db = await openWirdAt(path);
    expect(await setupDone(db), isFalse);
    await db.close();

    db = await openWirdAt(path);
    expect(await setupDone(db), isFalse, reason: 'left mid-setup');
    await markSetupDone(db);
    await db.close();

    db = await openWirdAt(path);
    expect(await setupDone(db), isTrue);
    expect((await displayPrefs(db)).rootOpen, isFalse);
    await db.close();
  });
}
