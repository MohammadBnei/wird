import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';

enum ReadingOrder { nuzul, mushaf }

/// A set is short enough to hold in the head through a prayer. The budget is
/// words rather than ayas because 2:282 is a page by itself and Aṣ-Ṣaffāt's
/// ayas run five words.
const setWordBudget = 25;
const setMaxAyas = 5;

/// How far out the reader may pull a set's end. The budget and the five ayas
/// above are what the walk *proposes*; this is the ceiling on what the reader
/// may make of it, and it is what the query has to fetch before any handle can
/// reach past what is in memory.
const setMaxDragAyas = 20;

/// The namespace every set id is derived under, which is
/// `uuidv5(NameSpaceURL, "https://wird.bnei.dev/set")` — ADR 0002, and what
/// `store.SetID` on the server uses. It is recomputed here rather than pasted
/// as a literal so the two halves cannot drift apart by transcription: a set
/// id derived under any other namespace is refused by the server, and a
/// refusal is permanent, so the prayer that carried it is lost.
final _setNamespace = _uuidV5(
  '6ba7b811-9dad-11d1-80b4-00c04fd430c8', // RFC 9562 NameSpace_URL
  'https://wird.bnei.dev/set',
);

/// A set's identity, which is a pure function of the range it holds and the
/// order it was read in. Nothing is minted and nothing is counted, so a
/// reinstall and a second device arrive at the same id for the same range
/// without having to agree on one — and because it says nothing about where
/// the reader is, the reading order stays switchable.
String setIdFor(ReadingOrder order, int startAyahId, int endAyahId) =>
    _uuidV5(_setNamespace, '${order.name}:$startAyahId:$endAyahId');

String _uuidV5(String namespace, String name) {
  final flat = namespace.replaceAll('-', '');
  final ns = [
    for (var i = 0; i < flat.length; i += 2)
      int.parse(flat.substring(i, i + 2), radix: 16),
  ];
  final bytes = sha1.convert([...ns, ...utf8.encode(name)]).bytes.sublist(0, 16);
  bytes[6] = (bytes[6] & 0x0f) | 0x50;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

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

  /// The same aya, now marked. The flag is baked at load, so a screen that
  /// marks a set without reloading it refreshes the copies it is showing —
  /// otherwise its progress bars go on saying the aya is open.
  StudyAya asUnderstood() => StudyAya(
    id: id,
    surahId: surahId,
    number: number,
    surahNameEn: surahNameEn,
    surahNameAr: surahNameAr,
    revelationOrder: revelationOrder,
    revelationPlace: revelationPlace,
    understood: true,
    words: words,
  );
}

class StudySet {
  const StudySet(this.ayas, {required this.order});

  final List<StudyAya> ayas;

  /// The order the set was read in, which is half of what names it.
  final ReadingOrder order;

  /// Derived, never minted: see [setIdFor].
  String get id => setIdFor(order, ayas.first.id, ayas.last.id);

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
///
/// A set is a run of *consecutive unread* ayas: it starts at the first unread
/// aya and ends at the aya before the next understood one, so nothing already
/// understood is ever served again.
///
/// That run is the *proposal*. Where the reader has pulled the set's end out,
/// [dragSpan] says how wide they made it and the widening wins: it may cross
/// an aya already understood, which is then recited along with the rest and
/// not marked again.
///
/// [alsoUnderstood] reads past ayas that are not marked in the database —
/// screen 1a computes the set after this one that way, to prefetch it, and
/// writes nothing.
Future<StudySet?> nextSet(
  Database db,
  ReadingOrder order, {
  Set<int> alsoUnderstood = const {},
}) async {
  final key = _orderKey(order);
  // Ids come from the corpus, never from the reader, so they go in as text.
  final also = alsoUnderstood.isEmpty
      ? ''
      : ' OR a.id IN (${alsoUnderstood.join(',')})';
  final rows = await db.rawQuery('''
    SELECT a.id, a.surah_id, a.number,
           s.name_en, s.name_ar, s.revelation_order, s.revelation_place,
           (SELECT COUNT(*) FROM words w WHERE w.ayah_id = a.id) AS word_count,
           (u.ayah_id IS NOT NULL$also) AS understood
      FROM ayahs a
      JOIN surahs s ON s.id = a.surah_id
      LEFT JOIN ayah_understood u ON u.ayah_id = a.id
     WHERE $key >= (SELECT MIN($key)
                      FROM ayahs a
                      JOIN surahs s ON s.id = a.surah_id
                     WHERE NOT (EXISTS (SELECT 1 FROM ayah_understood u
                                         WHERE u.ayah_id = a.id)$also))
     ORDER BY $key
     LIMIT $setMaxDragAyas''');
  if (rows.isEmpty) return null;

  final span = await dragSpan(db, rows.first['id']! as int);
  // The proposal stops at the first understood aya instead of swallowing it:
  // a set is what the reader recites in one prayer, so it is consecutive, and
  // marking out of order leaves holes the walk must not read across. A reader
  // who pulls the end out past one has said to recite it anyway.
  final reachable = span == null
      ? rows.takeWhile((r) => (r['understood']! as int) == 0).toList()
      : rows;
  final taken = reachable
      .take(
        _setWidth([
          for (final r in reachable) r['word_count']! as int,
        ], span: span),
      )
      .toList();

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

  return StudySet(order: order, [
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

/// How many ayas the set starting at the head of [wordCounts] holds.
///
/// Without a [span] this is the walk's own proposal: up to [setMaxAyas], and
/// inside [setWordBudget] — except that the first aya goes in whatever it
/// costs, because 2:282 is 128 words and would otherwise be skipped forever,
/// stalling the walk at the same place.
int _setWidth(List<int> wordCounts, {int? span}) {
  if (span != null) return span.clamp(1, max(1, min(setMaxDragAyas, wordCounts.length)));
  var taken = 0;
  var words = 0;
  for (final count in wordCounts) {
    if (taken == setMaxAyas) break;
    if (taken > 0 && words + count > setWordBudget) break;
    words += count;
    taken++;
  }
  return taken;
}

/// How wide the reader pulled the set that starts at this aya, or null where
/// they left the proposal alone.
///
/// A width, never a position, and it never leaves the device. The walk still
/// finds where the reader is from `ayah_understood` alone, which is what keeps
/// the reading order switchable.
Future<int?> dragSpan(Database db, int startAyahId) async {
  final rows = await db.query(
    'set_span',
    columns: ['ayas'],
    where: 'start_ayah_id = ?',
    whereArgs: [startAyahId],
    limit: 1,
  );
  return rows.isEmpty ? null : rows.first['ayas']! as int;
}

/// Remembers the width the reader gave this set, so leaving screen 1a does not
/// silently discard it.
Future<void> setDragSpan(Database db, int startAyahId, int ayas) => db.insert(
  'set_span',
  {'start_ayah_id': startAyahId, 'ayas': ayas.clamp(1, setMaxDragAyas)},
  conflictAlgorithm: ConflictAlgorithm.replace,
);

/// How many sets the reader has finished, replayed from the walk itself.
///
/// Counting rows in `sets` would count the sets *prayed*, which is a different
/// number: a set prayed twice and never marked would read as two sets
/// understood, and prayers-per-set would divide by it.
Future<int> setsUnderstood(Database db, ReadingOrder order) async {
  final key = _orderKey(order);
  final rows = await db.rawQuery('''
    SELECT a.id, (u.ayah_id IS NOT NULL) AS understood,
           COALESCE(c.n, 0) AS word_count
      FROM ayahs a
      JOIN surahs s ON s.id = a.surah_id
      LEFT JOIN ayah_understood u ON u.ayah_id = a.id
      LEFT JOIN (SELECT ayah_id, COUNT(*) AS n FROM words GROUP BY ayah_id) c
             ON c.ayah_id = a.id
     ORDER BY $key''');
  final spans = {
    for (final r in await db.query('set_span'))
      r['start_ayah_id']! as int: r['ayas']! as int,
  };

  var sets = 0;
  var i = 0;
  while (i < rows.length) {
    if ((rows[i]['understood']! as int) == 0) {
      // An aya the reader marked out of order leaves a hole. It belongs to no
      // finished set, and the set after it starts on the far side.
      i++;
      continue;
    }
    final run = <int>[];
    while (i + run.length < rows.length &&
        run.length < setMaxDragAyas &&
        (rows[i + run.length]['understood']! as int) == 1) {
      run.add(rows[i + run.length]['word_count']! as int);
    }
    i += _setWidth(run, span: spans[rows[i]['id']! as int]);
    sets++;
  }
  return sets;
}
