import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:wird/features/index/aya_search.dart';

import '../../corpus.dart';

void main() {
  late Database db;
  late AyaSearch search;

  setUpAll(() async {
    db = await testCorpus();
    search = await AyaSearch.of(db);
  });

  tearDownAll(AyaSearch.forget);

  List<int> ids(List<AyaHit> hits) => [for (final h in hits) h.id];

  test('الكتاب typed without the muṣḥaf\'s marks finds nothing, although '
      '2:2 says it', () {
    expect(ids(search.words('الكتاب')).first, 2002);
  });

  test(
    'a reader searching in English or French is answered only in Arabic',
    () {
      expect(ids(search.words('ward off (evil)')), contains(2002));
      expect(ids(search.words('aucun doute')), contains(2002));
    },
  );

  test('a French word typed without its accent finds other ayas than the '
      'word with it', () {
    final accented = ids(search.words('prière'));
    expect(accented, isNotEmpty);
    expect(ids(search.words('priere')), accented);
  });

  test('two letters find half the Qur\'an', () {
    expect(search.words('ab'), isEmpty);
    expect(search.words('رب'), isEmpty);
  });

  test('a root typed as letters, spaced or not, or as its transliteration '
      'names a different root', () async {
    for (final q in ['كتب', 'ك ت ب', 'k-t-b', 'ktb']) {
      final roots = await search.roots(q);
      expect([for (final r in roots) r.translit], ['k-t-b'], reason: q);
      expect(roots.single.ayas, isNotEmpty, reason: q);
    }
  });

  test('two keystrokes before the text is read read it twice', () {
    expect(identical(AyaSearch.of(db), AyaSearch.of(db)), isTrue);
  });
}
