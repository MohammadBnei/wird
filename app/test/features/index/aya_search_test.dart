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

  test('a reader typing the modern spelling of the Qur\'an\'s commonest '
      'words finds nothing, because the muṣḥaf writes their long ā its own '
      'way', () {
    expect(ids(search.words('الرحمن')).first, 1001);
    expect(ids(search.words('الصلاة')), contains(2003));
    expect(ids(search.words('الزكاة')), isNotEmpty);
    expect(ids(search.words('الحياة')), isNotEmpty);
    expect(ids(search.words('الله')).first, 1001);
  });

  test('a root typed without the marks of its transliteration is never '
      'found', () async {
    for (final q in ['hmd', 'h-m-d', 'ḥ-m-d']) {
      expect(
        [for (final r in await search.roots(q)) r.translit],
        contains('ḥ-m-d'),
        reason: q,
      );
    }
    // Folded, ḥ meets h; the root spelled as typed is named first.
    expect((await search.roots('ḥ-m-d')).first.translit, 'ḥ-m-d');
    expect((await search.roots('h-m-d')).first.translit, 'h-m-d');
    expect([
      for (final r in await search.roots('rhm')) r.translit,
    ], contains('r-ḥ-m'));
  });

  test('an English word ending in h finds French words that lack it', () {
    final hits = search.words('faith');
    expect(hits, isNotEmpty);
    for (final h in hits) {
      expect(
        h.en.toLowerCase().contains('faith') ||
            h.fr.toLowerCase().contains('faith'),
        isTrue,
        reason: '${h.id}',
      );
    }
  });

  test('a sūra left out of the chooser still takes up the places of the '
      'ayas it offers', () async {
    final words = search.words('Lord', exclude: {1});
    expect(words, hasLength(6));
    expect(words.where((h) => h.id ~/ 1000 == 1), isEmpty);
    final rhm = (await search.roots('رحم', exclude: {1})).single.ayas;
    expect(rhm, hasLength(6));
    expect(rhm.where((h) => h.id ~/ 1000 == 1), isEmpty);
  });
}
