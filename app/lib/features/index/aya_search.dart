import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../prayer/voice_follow.dart';
import 'sura_picker.dart' show foldLetters;

/// An aya the search found: its id, its Arabic, and its English and French.
typedef AyaHit = ({int id, String ar, String en, String fr});

/// A root the search found, with the first ayas that carry a word of it.
typedef RootHit = ({String display, String translit, List<AyaHit> ayas});

/// Searching the text of the Qur'an for a word, in Arabic, English or French,
/// and for a root.
///
/// Every aya's Arabic and both translations are read once and kept folded the
/// way [searchKey] and [foldLetters] fold a query, so a reader who types
/// الصلاة finds ٱلصَّلَوٰةَ and one who types "priere" finds « prière ».
///
// ponytail: an in-memory scan of 6236 ayas, about 2.5 M characters, folded
// on the UI isolate as the picker first opens and kept, with the text it was
// folded from, for the life of the app (about 10 MB). Move the folded text
// into corpus.db, or an FTS table, if opening the picker is measured slow or
// the memory is missed on a low-end phone.
class AyaSearch {
  AyaSearch._(this._db, this._ayas, this._roots);

  final Database _db;
  final List<({AyaHit hit, String ar, String en, String fr})> _ayas;

  /// Every root, with its letters folded as a query is.
  final List<
    ({
      String letters,
      String key,
      String display,
      String translit,
      String latin,
    })
  >
  _roots;

  static final _open = <String, Future<AyaSearch>>{};

  /// The search over [db], read once per database however often it is asked
  /// for — two keystrokes before the first read ends wait on the same one.
  static Future<AyaSearch> of(Database db) =>
      _open[db.path] ??= _read(db).catchError((Object e) {
        _open.remove(db.path);
        throw e;
      });

  @visibleForTesting
  static void forget() => _open.clear();

  static Future<AyaSearch> _read(Database db) async {
    final rows = await db.rawQuery('''
      SELECT a.id, a.text_uthmani AS ar, e.text AS en, f.text AS fr
        FROM ayahs a
        LEFT JOIN ayah_translations e ON e.ayah_id = a.id AND e.lang = 'en'
        LEFT JOIN ayah_translations f ON f.ayah_id = a.id AND f.lang = 'fr'
       ORDER BY a.id''');
    final roots = await db.query(
      'roots',
      columns: ['letters', 'display', 'translit'],
    );
    return AyaSearch._(
      db,
      [
        for (final r in rows)
          _folded((
            id: r['id']! as int,
            ar: r['ar']! as String,
            en: (r['en'] as String?) ?? '',
            fr: (r['fr'] as String?) ?? '',
          )),
      ],
      [
        for (final r in roots)
          (
            letters: r['letters']! as String,
            key: recitationKey(r['letters']! as String),
            display: r['display']! as String,
            translit: r['translit']! as String,
            latin: foldLetters(r['translit']! as String),
          ),
      ],
    );
  }

  static ({AyaHit hit, String ar, String en, String fr}) _folded(AyaHit h) => (
    hit: h,
    ar: searchKey(h.ar),
    en: foldLetters(h.en),
    fr: foldLetters(h.fr),
  );

  /// Arabic as a reader typing it and the muṣḥaf writing it can agree on.
  ///
  /// [recitationKey] folds what the voice and the muṣḥaf share, but the
  /// muṣḥaf writes the long ā in ways modern spelling does not: a dagger alif
  /// (ٱلرَّحْمَـٰنِ for الرحمن), a wāw carrying one (ٱلصَّلَوٰةَ for الصلاة), and an
  /// alif maqṣūra with one (عَلَىٰ). A reader types either spelling, so the
  /// long ā is left out on both sides — every alif, the wāw or yāʾ seat that
  /// carries a dagger alif, and the alif maqṣūra — and الكتاب, الرحمن and
  /// الصلاة all meet the muṣḥaf.
  @visibleForTesting
  static String searchKey(String s) => recitationKey(
    s
        .replaceAll(RegExp('[\u0648\u0649]\u0670'), '')
        .replaceAll(RegExp('[\u0622\u0623\u0625\u0627\u0649\u0670\u0671]'), ''),
  );

  /// The ayas whose Arabic, English or French holds [query], in written
  /// order, at most [limit] of them, none of them in a sūra in [exclude]. A
  /// query of under three letters finds nothing: two letters are in half the
  /// Qur'an.
  List<AyaHit> words(
    String query, {
    int limit = 6,
    Set<int> exclude = const {},
  }) {
    final ar = searchKey(query);
    final latin = foldLetters(query);
    // Counted before the long ā is left out, or الله would be two letters.
    final arabic = recitationKey(query).length >= 3 && ar.isNotEmpty;
    if (!arabic && latin.length < 3) return const [];
    final out = <AyaHit>[];
    for (final a in _ayas) {
      if (exclude.contains(a.hit.id ~/ 1000)) continue;
      if ((arabic && a.ar.contains(ar)) ||
          (latin.length >= 3 &&
              (a.en.contains(latin) || a.fr.contains(latin)))) {
        out.add(a.hit);
        if (out.length == limit) break;
      }
    }
    return out;
  }

  /// The roots [query] names, by their letters — كتب, or ك ت ب — or by their
  /// transliteration, with or without its marks: ḥ-m-d, h-m-d or hmd. Each
  /// comes with the first [limit] ayas a word of it stands in, outside the
  /// sūras in [exclude], read from the same `words.root_letters` the
  /// constellation reads a root's family from.
  Future<List<RootHit>> roots(
    String query, {
    int limit = 6,
    Set<int> exclude = const {},
  }) async {
    final ar = recitationKey(query);
    final latin = foldLetters(query);
    // A root is two to four letters, its transliteration a few more; a
    // longer query is words, and is not looked for among the roots.
    final found = [
      for (final r in _roots)
        if (ar.isNotEmpty
            ? ar.length <= 4 && r.key == ar
            : latin.length >= 2 && latin.length <= 8 && r.latin == latin)
          r,
    ];
    // Folding meets ḥ and h, so hmd names both ḥ-m-d and h-m-d. The one
    // spelled as typed comes first.
    final typed = query.trim().toLowerCase();
    found.sort(
      (x, y) => (x.translit == typed ? 0 : 1) - (y.translit == typed ? 0 : 1),
    );
    final byId = {for (final a in _ayas) a.hit.id: a.hit};
    return [
      for (final r in found)
        (
          display: r.display,
          translit: r.translit,
          ayas: [
            for (final row in await _db.rawQuery(
              '''
              SELECT DISTINCT ayah_id FROM words
               WHERE root_letters = ?
                 AND ayah_id / 1000 NOT IN (${exclude.join(',')})
               ORDER BY ayah_id LIMIT ?''',
              [r.letters, limit],
            ))
              ?byId[row['ayah_id']! as int],
          ],
        ),
    ];
  }
}
