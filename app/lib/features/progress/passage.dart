import 'package:sqflite/sqflite.dart';

import '../../data/db.dart';
import '../../data/sets.dart';

/// The Ḥafṣ count. Stated as a constant because it is an assumption: another
/// counting tradition would make every percentage on this screen different.
const ayasInTheQuran = 6236;

/// Where each juz starts, as an ayah id (sūra × 1000 + number). The corpus
/// carries no juz column, and these thirty boundaries are the same in every
/// printed Ḥafṣ muṣḥaf.
const juzStarts = [
  1001, 2142, 2253, 3092, 4024, 4148, 5082, 6111, 7088, 8041, //
  9093, 11006, 12053, 15001, 17001, 18075, 21001, 23001, 25021, 27056,
  29046, 33031, 36028, 39032, 41047, 46001, 51031, 58001, 67001, 78001,
];

/// One sūra's row: how much of it the reader has understood.
class SuraPassage {
  const SuraPassage({
    required this.id,
    required this.nameEn,
    required this.nameAr,
    required this.understood,
    required this.ayahCount,
    required this.current,
  });

  final int id;
  final String nameEn;
  final String nameAr;
  final int understood;
  final int ayahCount;

  /// The sūra the next set comes from, which the design draws lit while the
  /// rest are dimmed.
  final bool current;

  double get fraction => understood / ayahCount;
}

/// Everything screen 1d shows, derived at read time. Nothing here is stored:
/// a count that is written down goes wrong the first time a sync replays an
/// op, and then the one number the app exists to show is a lie.
class Passage {
  const Passage({
    required this.understood,
    required this.setsUnderstood,
    required this.prayers,
    required this.juz,
    required this.suras,
    required this.rootsKnown,
    required this.rootsKnownCount,
    required this.wordsAhead,
    required this.wordsAheadKnown,
    required this.currentJuz,
    required this.currentSet,
    required this.prayersOnCurrentSet,
  });

  final int understood;
  final int setsUnderstood;
  final int prayers;

  /// Thirty fractions, one per juz, which is what the ring's arcs are lit by.
  final List<double> juz;
  final List<SuraPassage> suras;

  /// The three roots the reader has met most often, spelled as a lexicon
  /// prints them, and how many there are in total.
  final List<String> rootsKnown;
  final int rootsKnownCount;

  final int wordsAhead;
  final int wordsAheadKnown;

  /// One-based, and 30 once there is nothing left to read.
  final int currentJuz;

  /// One-based: the sets the walk has finished, plus the one being read. It
  /// comes from the walk and not from counting rows, because the rows record
  /// sets *prayed* and a set can be prayed without ever being understood.
  final int currentSet;

  /// How many prayers the set being read has already carried, so the screen
  /// can say which one the next prayer will be.
  final int prayersOnCurrentSet;

  double get fraction => understood / ayasInTheQuran;

  /// Prayers per set. Null before the first set, because a new reader must be
  /// shown an em dash rather than a division by zero.
  double? get prayersPerSet =>
      setsUnderstood == 0 ? null : prayers / setsUnderstood;

  int get coverageAhead =>
      wordsAhead == 0 ? 0 : (100 * wordsAheadKnown / wordsAhead).round();
}

/// The juz an aya belongs to, one-based.
int juzOf(int ayahId) {
  var juz = 1;
  for (var i = 1; i < juzStarts.length; i++) {
    if (ayahId >= juzStarts[i]) juz = i + 1;
  }
  return juz;
}

Future<Passage> readPassage(Database db) async {
  final order = await readingOrder(db);
  // The set generator is the one place that knows where the reader is, so the
  // juz and set the ring names come from it rather than from a second walk.
  final next = await nextSet(db, order);

  final marks = await db.rawQuery('''
    SELECT a.id, (u.ayah_id IS NOT NULL) AS understood
      FROM ayahs a
      LEFT JOIN ayah_understood u ON u.ayah_id = a.id''');
  final total = List.filled(juzStarts.length, 0);
  final done = List.filled(juzStarts.length, 0);
  var understood = 0;
  for (final row in marks) {
    final juz = juzOf(row['id']! as int) - 1;
    total[juz]++;
    if ((row['understood']! as int) == 1) {
      done[juz]++;
      understood++;
    }
  }

  final suras = await db.rawQuery('''
    SELECT s.id, s.name_en, s.name_ar, s.ayah_count,
           COUNT(u.ayah_id) AS understood
      FROM surahs s
      LEFT JOIN ayahs a ON a.surah_id = s.id
      LEFT JOIN ayah_understood u ON u.ayah_id = a.id
     GROUP BY s.id''');
  final currentSura = next?.ayas.first.surahId;

  final roots = await db.rawQuery('''
    SELECT r.display, COUNT(*) AS met
      FROM words w
      JOIN ayah_understood u ON u.ayah_id = w.ayah_id
      JOIN roots r ON r.letters = w.root_letters
     GROUP BY r.letters
     ORDER BY met DESC''');

  // What the roots already met are worth against the text still to come.
  final ahead = await db.rawQuery(
    '''
    SELECT COUNT(*) AS ahead,
           COALESCE(SUM(CASE WHEN w.root_letters IN (
             SELECT w2.root_letters FROM words w2
               JOIN ayah_understood u2 ON u2.ayah_id = w2.ayah_id)
             THEN 1 ELSE 0 END), 0) AS known
      FROM words w
     WHERE NOT EXISTS (SELECT 1 FROM ayah_understood u WHERE u.ayah_id = w.ayah_id)''',
  );

  final finished = await setsUnderstood(db, order);
  return Passage(
    understood: understood,
    setsUnderstood: finished,
    prayers: Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM set_prayers'),
    )!,
    juz: [
      for (var i = 0; i < total.length; i++)
        total[i] == 0 ? 0 : done[i] / total[i],
    ],
    suras: _rows(suras, currentSura),
    rootsKnown: [for (final r in roots.take(3)) r['display']! as String],
    rootsKnownCount: roots.length,
    wordsAhead: ahead.first['ahead']! as int,
    wordsAheadKnown: ahead.first['known']! as int,
    currentJuz: next == null ? juzStarts.length : juzOf(next.ayas.first.id),
    currentSet: finished + 1,
    prayersOnCurrentSet: next == null ? 0 : await prayersOnSet(db, next.id),
  );
}

/// The four rows the design draws: the sūra the reader is in, then the ones
/// they have got furthest through.
List<SuraPassage> _rows(List<Map<String, Object?>> rows, int? currentSura) {
  final all = [
    for (final row in rows)
      SuraPassage(
        id: row['id']! as int,
        nameEn: row['name_en']! as String,
        nameAr: row['name_ar']! as String,
        understood: row['understood']! as int,
        ayahCount: row['ayah_count']! as int,
        current: row['id'] == currentSura,
      ),
  ];
  final current = all.where((s) => s.current);
  final rest = all.where((s) => !s.current && s.understood > 0).toList()
    ..sort((a, b) => b.understood.compareTo(a.understood));
  return [...current, ...rest].take(4).toList();
}
