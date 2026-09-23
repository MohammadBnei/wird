import 'package:sqflite/sqflite.dart';
import 'package:wird/data/sets.dart';

/// The set the reader is holding when the prayer starts, read straight out of
/// the corpus. Which ayas the walk hands over is sets.dart's business and is
/// tested there; screen 1b is handed one and never generates it.
Future<StudySet> setOf(Database db, List<int> ayahIds) async {
  final ayas = <StudyAya>[];
  for (final id in ayahIds) {
    final row = (await db.rawQuery('''
      SELECT a.surah_id, a.number, s.name_en, s.name_ar,
             s.revelation_order, s.revelation_place
        FROM ayahs a JOIN surahs s ON s.id = a.surah_id
       WHERE a.id = ?''', [id])).single;
    final words = await db.rawQuery(
      '''SELECT id, text_ar, translit, gloss_en, root_letters
           FROM words WHERE ayah_id = ? ORDER BY position''',
      [id],
    );
    ayas.add(
      StudyAya(
        id: id,
        surahId: row['surah_id']! as int,
        number: row['number']! as int,
        surahNameEn: row['name_en']! as String,
        surahNameAr: row['name_ar']! as String,
        revelationOrder: row['revelation_order']! as int,
        revelationPlace: row['revelation_place']! as String,
        understood: false,
        words: [
          for (final w in words)
            StudyWord(
              id: w['id']! as int,
              text: w['text_ar']! as String,
              translit: w['translit'] as String?,
              gloss: w['gloss_en'] as String?,
              root: w['root_letters'] as String?,
            ),
        ],
      ),
    );
  }
  return StudySet(ayas);
}

/// Al-ʿAsr 103:1–3, the set the design draws on screen 1b.
Future<StudySet> alAsr(Database db) => setOf(db, [103001, 103002, 103003]);
