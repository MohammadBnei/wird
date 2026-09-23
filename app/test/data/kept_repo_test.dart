import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wird/data/kept_repo.dart';

import '../corpus.dart';

void main() {
  late Database db;

  setUp(() async {
    db = await testCorpus();
    await ensureKeptTable(db);
    await db.delete('kept_items');
  });

  test('an item the reader deleted is handed back by the next sync, because '
      'the delete left nothing behind to say it is gone', () async {
    final id = await keep(db, kind: KeptKind.note, body: 'a thought');
    await forget(db, id);

    expect(await keptItems(db, kind: KeptKind.note), isEmpty);
    final rows = await db.query('kept_items', where: 'id = ?', whereArgs: [id]);
    expect(
      rows.single['deleted_at'],
      isNotNull,
      reason:
          'the row is gone from the device, so every other device the '
          'reader owns will send it straight back',
    );
  });

  test('a deleted item comes back the moment the reader keeps something '
      'else', () async {
    final id = await keep(db, kind: KeptKind.note, body: 'a thought');
    await forget(db, id);
    await keep(db, kind: KeptKind.note, body: 'another thought');

    final left = await keptItems(db, kind: KeptKind.note);
    expect(left.map((i) => i.body), ['another thought']);
  });

  test('a search in the spelling a reader types misses the aya they kept, '
      'because the corpus writes it fully vowelled', () async {
    // 103:3, which the corpus holds as وَتَوَاصَوْا بِالصَّبْرِ.
    await keep(db, kind: KeptKind.aya, ayahId: 103003);

    final found = await keptItems(db, kind: KeptKind.aya, search: 'بالصبر');
    expect(found, hasLength(1));
  });

  test('an aya whose Uthmani spelling hides a long vowel behind a dagger alef '
      'cannot be found in the spelling a reader types', () async {
    // 1:2, which the corpus holds as ٱلْعَٰلَمِينَ: the long a is a superscript
    // alef, U+0670, and nobody searching types it. Dropping that mark leaves
    // العلمين, which the ordinary spelling does not match.
    await keep(db, kind: KeptKind.aya, ayahId: 1002);

    final found = await keptItems(db, kind: KeptKind.aya, search: 'العالمين');
    expect(found, hasLength(1));
  });

  test('writing the dagger alef out as a full alef loses the words whose '
      'ordinary spelling does not carry one either', () async {
    // The other half of the same mark, and why one folding cannot serve both:
    // ٱلرَّحْمَٰنِ is spelled الرحمن, with no alef, in the script a reader
    // types. Expanding U+0670 would make it الرحمان and lose the aya.
    await keep(db, kind: KeptKind.aya, ayahId: 1003);

    final found = await keptItems(db, kind: KeptKind.aya, search: 'الرحمن');
    expect(found, hasLength(1));
  });

  test('a note the reader can only remember by their own words cannot be '
      'found', () async {
    await keep(
      db,
      kind: KeptKind.note,
      body:
          'the form VI verb makes it '
          'mutual',
    );
    await keep(db, kind: KeptKind.note, body: 'something else entirely');

    final found = await keptItems(db, kind: KeptKind.note, search: 'mutual');
    expect(found.map((i) => i.body), ['the form VI verb makes it mutual']);
  });

  test('the list hands back a kind the reader did not ask for, so the filter '
      'decides nothing', () async {
    await keep(db, kind: KeptKind.aya, ayahId: 103003);
    await keep(db, kind: KeptKind.root, rootLetters: 'صبر');
    await keep(db, kind: KeptKind.note, body: 'a thought');

    for (final kind in KeptKind.values) {
      final found = await keptItems(db, kind: kind);
      expect(found.map((i) => i.kind), [kind], reason: kind.name);
    }
  });
}
