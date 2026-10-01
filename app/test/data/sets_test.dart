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
    expect(
      set.ayas.map((a) => a.id),
      [96001, 96002],
      reason: 'the run ends at the aya before the one already understood',
    );
  });

  test('an aya the reader understood out of order is served again inside a '
      'later set', () async {
    // Al-ʿAlaq 1–3 read in order, then aya 5 on its own: aya 4 is the hole.
    await markSetUnderstood(db, newOpId(), [96001, 96002, 96003]);
    await markSetUnderstood(db, newOpId(), [96005]);

    expect(
      (await nextSet(db, ReadingOrder.nuzul))!.ayas.map((a) => a.id),
      [96004],
      reason: 'the set is the hole alone, and stops short of aya 5',
    );

    // Then read on, marking every set understood, and no set may ever hold an
    // aya the database already has.
    for (var i = 0; i < 20; i++) {
      final understood = {
        for (final r in await db.query('ayah_understood', columns: ['ayah_id']))
          r['ayah_id']! as int,
      };
      final set = await nextSet(db, ReadingOrder.nuzul);
      if (set == null) break;
      final ids = [for (final a in set.ayas) a.id];
      expect(
        ids.where(understood.contains),
        isEmpty,
        reason: '${set.title} re-serves an aya already understood',
      );
      await markSetUnderstood(db, newOpId(), ids);
    }
  });

  test('the set after this one is computed by writing the current one off as '
      'understood', () async {
    final first = await nextSet(db, ReadingOrder.nuzul);
    final ahead = await nextSet(
      db,
      ReadingOrder.nuzul,
      alsoUnderstood: {for (final a in first!.ayas) a.id},
    );

    expect(ahead!.ayas.first.id, 96006);
    expect(
      await db.query('ayah_understood'),
      isEmpty,
      reason: 'reading ahead marks nothing',
    );
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

  test('the set is five ayas however far the reader pulls its end out',
      () async {
    await setDragSpan(db, 96001, 8);

    final set = await nextSet(db, ReadingOrder.nuzul);

    expect(set!.ayas.length, 8);
    expect(set.ayas.last.id, 96008);
    expect(
      set.ayas.map((a) => a.understood),
      everyElement(isFalse),
      reason: 'a wider set is still a set of ayas the reader has not read',
    );
  });

  test('a set pulled across an aya already understood stops short of it, or '
      'serves it as unread', () async {
    await markSetUnderstood(db, newOpId(), [96003]);
    await setDragSpan(db, 96001, 5);

    final set = await nextSet(db, ReadingOrder.nuzul);

    expect(set!.ayas.map((a) => a.id), [96001, 96002, 96003, 96004, 96005]);
    expect(
      set.ayas.singleWhere((a) => a.id == 96003).understood,
      isTrue,
      reason: 'the aya is present, and present as already counted',
    );
  });

  test('a set pulled wider than the twenty ayas anyone recites in one prayer',
      () async {
    await setDragSpan(db, 96001, 60);

    expect((await nextSet(db, ReadingOrder.nuzul))!.ayas.length, setMaxDragAyas);
  });

  test('the width the reader gave one set is applied to the set after it too',
      () async {
    await setDragSpan(db, 96001, 8);
    final first = (await nextSet(db, ReadingOrder.nuzul))!;
    await markSetUnderstood(db, newOpId(), [for (final a in first.ayas) a.id]);

    final second = await nextSet(db, ReadingOrder.nuzul);

    expect(second!.ayas.first.id, 96009);
    expect(
      second.ayas.length,
      5,
      reason: 'the width belongs to the set it was given to, not to the walk',
    );
  });

  test('two sets read one after the other are counted as one, because the '
      'count comes from the rows instead of the walk', () async {
    expect(await setsUnderstood(db, ReadingOrder.nuzul), 0);

    for (var i = 0; i < 2; i++) {
      final set = (await nextSet(db, ReadingOrder.nuzul))!;
      await markSetUnderstood(db, newOpId(), [for (final a in set.ayas) a.id]);
    }

    expect(await setsUnderstood(db, ReadingOrder.nuzul), 2);
  });

  test('a set the reader pulled wider is counted as two sets afterwards',
      () async {
    await setDragSpan(db, 96001, 8);
    final set = (await nextSet(db, ReadingOrder.nuzul))!;
    await markSetUnderstood(db, newOpId(), [for (final a in set.ayas) a.id]);

    expect(await setsUnderstood(db, ReadingOrder.nuzul), 1);
  });

  test('an aya marked on its own out of order counts as a whole set',
      () async {
    await markSetUnderstood(db, newOpId(), [96005]);

    expect(
      await setsUnderstood(db, ReadingOrder.nuzul),
      1,
      reason: 'one set, and the hole before it belongs to none',
    );
  });
}
