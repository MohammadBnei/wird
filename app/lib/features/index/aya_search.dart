import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../prayer/voice_follow.dart';
import 'sura_picker.dart';

/// An aya the search found: its id, its Arabic, and its English and French.
typedef AyaHit = ({int id, String ar, String en, String fr});

/// A root the search found, with the first ayas that carry a word of it.
typedef RootHit = ({String display, String translit, List<AyaHit> ayas});

/// Searching the text of the Qur'an for a word, in Arabic, English or French,
/// and for a root.
///
/// Every aya's Arabic and both translations are read once and kept folded the
/// way [recitationKey] and [foldLatin] fold a query, so a reader who types
/// الكتاب finds ٱلْكِتَـٰبُ and one who types "priere" finds « prière ».
///
// ponytail: an in-memory scan of 6236 ayas, about 2.5 M characters, rather
// than an index in the corpus. Move the folded text into corpus.db, or an
// FTS table, if opening the picker is measured slow on a low-end phone.
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
            latin: (r['translit']! as String).replaceAll('-', ''),
          ),
      ],
    );
  }

  static ({AyaHit hit, String ar, String en, String fr}) _folded(AyaHit h) =>
      (hit: h, ar: _arabic(h.ar), en: foldLatin(h.en), fr: foldLatin(h.fr));

  /// [recitationKey], keeping the waṣl alif as an alif. The voice drops it
  /// because a reciter runs over it; a reader typing ٱلْكِتَـٰبُ types الكتاب, and
  /// with the alif gone it would only be found where the word before it
  /// happens to end in one.
  static String _arabic(String s) => recitationKey(s.replaceAll('ٱ', 'ا'));

  /// The ayas whose Arabic, English or French holds [query], in written
  /// order, at most [limit] of them. A query of under three letters finds
  /// nothing: two letters are in half the Qur'an.
  List<AyaHit> words(String query, {int limit = 6}) {
    final ar = _arabic(query);
    final latin = foldLatin(query);
    if (ar.length < 3 && latin.length < 3) return const [];
    final out = <AyaHit>[];
    for (final a in _ayas) {
      if ((ar.length >= 3 && a.ar.contains(ar)) ||
          (latin.length >= 3 &&
              (a.en.contains(latin) || a.fr.contains(latin)))) {
        out.add(a.hit);
        if (out.length == limit) break;
      }
    }
    return out;
  }

  /// The roots [query] names, by their letters — كتب, or ك ت ب — or by their
  /// transliteration, k-t-b or ktb. Each comes with the first [limit] ayas a
  /// word of it stands in, read from the same `words.root_letters` the
  /// constellation reads a root's family from.
  Future<List<RootHit>> roots(String query, {int limit = 6}) async {
    final ar = recitationKey(query);
    final latin = query.toLowerCase().replaceAll(RegExp(r'[\s\-]'), '');
    // A root is two to four letters, its transliteration a few more; a
    // longer query is words, and is not looked for among the roots.
    final found = [
      for (final r in _roots)
        if (ar.isNotEmpty
            ? ar.length <= 4 && r.key == ar
            : latin.length >= 2 && latin.length <= 8 && r.latin == latin)
          r,
    ];
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
               ORDER BY ayah_id LIMIT ?''',
              [r.letters, limit],
            ))
              ?byId[row['ayah_id']! as int],
          ],
        ),
    ];
  }
}
