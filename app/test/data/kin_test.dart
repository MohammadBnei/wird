import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wird/data/db.dart';
import 'package:wird/data/root_repo.dart';

import '../corpus.dart';

/// Roots a reader meets in the first sets of either order, and one — ق ر أ —
/// whose forms the corpus stores both bare and with a pause mark on them.
const _roots = ['قرأ', 'علق', 'عصر', 'رحم'];

void main() {
  late Database db;

  setUp(() async => db = await testCorpus());

  test('a kin names an aya the root is not in, so a reader who follows it '
      'lands on a verse the word never appears in', () async {
    for (final letters in _roots) {
      for (final kin in (await rootDetail(db, letters))!.kin) {
        final carried = await db.rawQuery(
          'SELECT COUNT(*) AS n FROM words WHERE ayah_id = ? AND root_letters = ?',
          [kin.ayahId, letters],
        );
        expect(
          carried.single['n'],
          greaterThan(0),
          reason: '$letters · ${ayahRef(kin.ayahId)} · ${kin.text}',
        );
      }
    }
  });
}
