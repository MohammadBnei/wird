import 'package:sqflite/sqflite.dart';

enum ReadingOrder { nuzul, mushaf }

/// A set is short enough to hold in the head through a prayer. The budget is
/// words rather than ayas because 2:282 is a page by itself and Aṣ-Ṣaffāt's
/// ayas run five words.
const setWordBudget = 25;
const setMaxAyas = 5;

/// The written order puts the long sūras first; the revelation order walks the
/// text as it arrived. One expression each, so the setting is a comparator and
/// never a second copy of the walk.
String _orderKey(ReadingOrder order) => switch (order) {
  ReadingOrder.nuzul => 's.revelation_order * 1000 + a.number',
  ReadingOrder.mushaf => 'a.surah_id * 1000 + a.number',
};

class StudyWord {
  const StudyWord({
    required this.id,
    required this.text,
    this.translit,
    this.gloss,
    this.root,
  });

  final int id;
  final String text;
  final String? translit;
  final String? gloss;

  /// The root's letters, or null where the word carries none — particles and
  /// proper nouns. Only a word with a root opens the root panel.
  final String? root;
}

class StudyAya {
  const StudyAya({
    required this.id,
    required this.surahId,
    required this.number,
    required this.surahNameEn,
    required this.surahNameAr,
    required this.revelationOrder,
    required this.revelationPlace,
    required this.understood,
    required this.words,
  });

  final int id;
  final int surahId;
  final int number;
  final String surahNameEn;
  final String surahNameAr;
  final int revelationOrder;
  final String revelationPlace;
  final bool understood;
  final List<StudyWord> words;
}

class StudySet {
  const StudySet(this.ayas);

  final List<StudyAya> ayas;

  bool get crossesSurah => ayas.first.surahId != ayas.last.surahId;

  String get title {
    final first = ayas.first;
    final last = ayas.last;
    if (crossesSurah) {
      return '${first.surahNameEn} ${first.number} – '
          '${last.surahNameEn} ${last.number}';
    }
    return first.number == last.number
        ? '${first.surahNameEn} ${first.number}'
        : '${first.surahNameEn} ${first.number}–${last.number}';
  }
}

/// The next set to read, or null once nothing is left unread.
///
/// The walk resumes at the next aya **not yet understood** in the chosen
/// order, never after the last understood one: that is what lets the reader
/// switch between the two orders at any time without losing or re-reading
/// anything.
Future<StudySet?> nextSet(Database db, ReadingOrder order) async {
  final key = _orderKey(order);
  final rows = await db.rawQuery('''
    SELECT a.id, a.surah_id, a.number,
           s.name_en, s.name_ar, s.revelation_order, s.revelation_place,
           (SELECT COUNT(*) FROM words w WHERE w.ayah_id = a.id) AS word_count,
           (u.ayah_id IS NOT NULL) AS understood
      FROM ayahs a
      JOIN surahs s ON s.id = a.surah_id
      LEFT JOIN ayah_understood u ON u.ayah_id = a.id
     WHERE $key >= (SELECT MIN($key)
                      FROM ayahs a
                      JOIN surahs s ON s.id = a.surah_id
                     WHERE NOT EXISTS (SELECT 1 FROM ayah_understood u
                                        WHERE u.ayah_id = a.id))
     ORDER BY $key
     LIMIT $setMaxAyas''');
  if (rows.isEmpty) return null;

  final taken = <Map<String, Object?>>[];
  var words = 0;
  for (final row in rows) {
    final count = row['word_count']! as int;
    // The first aya goes in whatever it costs. 2:282 is 128 words and would
    // otherwise be skipped forever, stalling the walk at the same place.
    if (taken.isNotEmpty && words + count > setWordBudget) break;
    taken.add(row);
    words += count;
  }

  final byAya = <int, List<StudyWord>>{for (final r in taken) r['id']! as int: []};
  final marks = List.filled(byAya.length, '?').join(',');
  final wordRows = await db.rawQuery(
    '''SELECT id, ayah_id, text_ar, translit, gloss_en, root_letters
         FROM words
        WHERE ayah_id IN ($marks)
        ORDER BY ayah_id, position''',
    byAya.keys.toList(),
  );
  for (final w in wordRows) {
    final root = w['root_letters'] as String?;
    byAya[w['ayah_id']! as int]!.add(
      StudyWord(
        id: w['id']! as int,
        text: w['text_ar']! as String,
        translit: w['translit'] as String?,
        gloss: w['gloss_en'] as String?,
        root: (root == null || root.isEmpty) ? null : root,
      ),
    );
  }

  return StudySet([
    for (final r in taken)
      StudyAya(
        id: r['id']! as int,
        surahId: r['surah_id']! as int,
        number: r['number']! as int,
        surahNameEn: r['name_en']! as String,
        surahNameAr: r['name_ar']! as String,
        revelationOrder: r['revelation_order']! as int,
        revelationPlace: r['revelation_place']! as String,
        understood: (r['understood']! as int) == 1,
        words: byAya[r['id']! as int]!,
      ),
  ]);
}
