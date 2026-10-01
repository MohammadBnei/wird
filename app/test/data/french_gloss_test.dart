import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wird/data/db.dart';
import 'package:wird/data/sets.dart';

import '../corpus.dart';

void main() {
  test('a reader in French reads the gloss under each word of the aya in '
      'English', () async {
    final db = await testCorpus();
    final words = (await wordsFor(db, [112001]))[112001]!;

    expect(words.first.glossIn(const Locale('fr')), 'Dis');
    expect(words.first.glossIn(const Locale('en')), 'Say');
  });

  // The failure: an install from before corpus 5 keeps its old wird.db, which
  // has no gloss_fr, and every query naming it throws — the reading screen
  // would not open at all for anyone who updated.
  test(
    'an install from before the French glosses cannot read the words of an aya',
    () async {
      await testCorpus(); // initialises the ffi factory
      final dir = await Directory.systemTemp.createTemp('wird-old-install');
      addTearDown(() => dir.delete(recursive: true));
      final path = '${dir.path}/wird.db';
      await File('assets/corpus.db').copy(path);
      final old = await openDatabase(path);
      await old.execute('ALTER TABLE words DROP COLUMN gloss_fr');
      await old.close();

      final db = await openWirdAt(path);
      addTearDown(db.close);
      final words = (await wordsFor(db, [112001]))[112001]!;

      expect(words.first.glossIn(const Locale('fr')), 'Say');
    },
  );
}
