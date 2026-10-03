import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' show Sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wird/data/audio.dart';
import 'package:wird/data/db.dart';
import 'package:wird/data/kept_repo.dart';

void main() {
  late Directory dir;
  late File target;
  final shipped = File('assets/corpus.db');

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('wird_upgrade');
    target = File('${dir.path}/wird.db');
    await shipped.copy(target.path);
    // An install from one corpus back, with a reader's rows in it.
    final db = await openWirdAt(target.path);
    await ensureKeptTable(db);
    await db.update('corpus_meta', {
      'corpus_version': bundledCorpusVersion - 1,
    });
    await db.insert('ayah_understood', {
      'ayah_id': 1001,
      'understood_at': '2026-09-01T00:00:00Z',
    });
    await db.insert('kept_items', {
      'id': 'k1',
      'kind': 'ayah',
      'ayah_id': 2255,
      'created_at': '2026-09-01T00:00:00Z',
      'updated_at': '2026-09-01T00:00:00Z',
    });
    await db.insert('outbox', {
      'client_op_id': 'op1',
      'kind': 'ayah_understood',
      'body': '{}',
      'created_at': '2026-09-01T00:00:00Z',
    });
    await db.insert('root_notes', {
      'root_letters': 'رحم',
      'note': 'mercy; the womb',
      'source': 'senses',
    });
    await setPlaybackKnob(db, HearWhileReciting.cut);
    await setPrayerPrefs(db, (
      preset: null,
      rakahs: 2,
      voice: false,
      pace: true,
      wpm: 55,
      gloss: false,
      around: true,
      arabicSize: 70,
    ));
    await db.close();
  });

  tearDown(() => dir.deleteSync(recursive: true));

  Future<int> count(Database db, String table) async =>
      Sqflite.firstIntValue(await db.rawQuery('SELECT count(*) FROM $table'))!;

  test(
    'the app compares installs against a version other than the one it '
    'ships, so a newer corpus is never installed or always reinstalled',
    () async {
      expect(
        await installedCorpusVersion(shipped.absolute.path),
        bundledCorpusVersion,
      );
    },
  );

  test('an install on an older corpus never receives the newer one, or loses '
      "the reader's rows getting it", () async {
    await upgradeCorpus(target, shipped.readAsBytesSync());

    expect(await installedCorpusVersion(target.path), bundledCorpusVersion);
    final db = await openWirdAt(target.path);
    expect(await count(db, 'ayah_understood'), 1);
    expect(await count(db, 'kept_items'), 1);
    expect(await count(db, 'outbox'), 1);
    expect(
      await count(db, 'root_notes'),
      1,
      reason: 'the senses this device fetched were dropped with the old corpus',
    );
    expect(
      (await prayerPrefs(db)).arabicSize,
      70,
      reason: 'the prayer was set up afresh after the corpus moved on',
    );
    expect(
      (await playbackPref(db)).hear,
      HearWhileReciting.cut,
      reason: 'the reader\'s playback choice went with the old corpus',
    );
    await db.close();
    expect(File('${target.path}.next').existsSync(), isFalse);
  });

  test(
    'a corpus that cannot be read takes the installed one down with it',
    () async {
      final garbage = Uint8List.fromList(List.filled(4096, 7));

      await expectLater(upgradeCorpus(target, garbage), throwsA(isA<Object>()));

      expect(
        await installedCorpusVersion(target.path),
        bundledCorpusVersion - 1,
      );
      final db = await openWirdAt(target.path);
      expect(await count(db, 'ayah_understood'), 1);
      await db.close();
      expect(File('${target.path}.next').existsSync(), isFalse);
    },
  );
}
