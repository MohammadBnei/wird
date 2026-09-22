import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wird/data/db.dart';
import 'package:wird/data/sets.dart';

import '../corpus.dart';

Future<void> understandEverythingBefore(Database db, String where) => db
    .execute("INSERT INTO ayah_understood SELECT id, '' FROM ayahs WHERE $where");

void main() {
  late Database db;

  setUp(() async => db = await testCorpus());

  test('a new reader is handed the muṣḥaf from the front instead of the first '
      'revelation', () async {
    final set = await nextSet(db, ReadingOrder.nuzul);

    expect(set!.ayas.first.id, 96001);
    expect(set.ayas.first.surahNameEn, contains('Alaq'));
    expect(set.ayas.length, setMaxAyas);
  });

  test('the walk resumes after the last aya read, skipping an earlier one the '
      'reader never understood', () async {
    await markSetUnderstood(db, newOpId(), [96003]);

    final set = await nextSet(db, ReadingOrder.nuzul);

    expect(set!.ayas.first.id, 96001);
    expect(set.ayas.singleWhere((a) => a.id == 96003).understood, isTrue);
  });

  test('the revelation walk falls into Al-Baqara at the end of Al-ʿAlaq '
      'instead of jumping to Al-Qalam', () async {
    await understandEverythingBefore(db, 'surah_id = 96');

    final set = await nextSet(db, ReadingOrder.nuzul);

    expect(set!.ayas.first.id, 68001);
  });

  test('a set that runs off the end of a sūra stops short instead of carrying '
      'on into the next one', () async {
    await understandEverythingBefore(db, 'surah_id = 96 AND number < 19');

    final set = await nextSet(db, ReadingOrder.nuzul);

    expect(set!.ayas.first.id, 96019);
    expect(set.crossesSurah, isTrue);
    expect(set.ayas.map((a) => a.surahId), contains(68));
    expect(set.title, 'Al-\'Alaq 19 – Al-Qalam ${set.ayas.last.number}');
  });

  test('switching to muṣḥaf order loses the progress made reading '
      'chronologically, or serves an aya over again', () async {
    await understandEverythingBefore(db, 'surah_id = 96');
    final understoodBefore = await db.query('ayah_understood');

    await setReadingOrder(db, ReadingOrder.mushaf);
    final set = await nextSet(db, await readingOrder(db));

    expect(await db.query('ayah_understood'), understoodBefore);
    expect(set!.ayas.first.id, 1001, reason: 'the muṣḥaf starts at Al-Fātiḥa');
    expect(
      set.ayas.where((a) => a.understood),
      isEmpty,
      reason: 'nothing already understood is served as the next thing to read',
    );
  });

  test('an aya longer than the whole word budget stalls the walk at the same '
      'place forever', () async {
    await understandEverythingBefore(db, 'id < 2282');

    final set = await nextSet(db, ReadingOrder.mushaf);

    expect(set!.ayas.single.id, 2282);
    expect(set.ayas.single.words.length, greaterThan(setWordBudget));
  });

  test('the reader who has understood every aya is served the walk again from '
      'the start', () async {
    await understandEverythingBefore(db, '1 = 1');

    expect(await nextSet(db, ReadingOrder.nuzul), isNull);
    expect(await nextSet(db, ReadingOrder.mushaf), isNull);
  });
}
