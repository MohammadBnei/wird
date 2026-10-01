import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:sqflite/sqflite.dart';

import 'kept_repo.dart';
import 'sets.dart' show translationsFor;

/// The most derivatives a dial can carry. Above this the root is read as a
/// spine instead, because a ninth satellite has nowhere on the ring to sit.
const dialCapacity = 8;

/// Qur'anic pause, sajda and section marks. The corpus keeps them on the word
/// they follow, so one derivative is stored twice — once bare, once marked —
/// and a root crosses the dial's capacity for a reason that has nothing to do
/// with how many derivatives it actually has.
///
/// The range stops short of U+06DF–U+06E8, which are spelling rather than
/// recitation: the small rounded zero over a silent alef belongs to the word,
/// and stripping it would print the Qur'an's text wrong.
final _pauseMarks = RegExp('[\u{6D6}-\u{6DE}\u{6E9}-\u{6ED}]');

/// One member of a root's family: the word as the corpus spells it, what it
/// was glossed as, what shape it is, how often it is read — and the aya it
/// opens. The aya is what makes a derivative a place rather than a caption,
/// and it is why every drawing of a family is built from this one record.
///
/// [ayahId] is where the form is **first met in the muṣḥaf**, not the nearest
/// occurrence to the reader. A form that occurs eighty times has no one aya,
/// and the first is the only one that can be named without inventing a rule
/// the reader cannot see.
///
/// [wordId] is that same first occurrence, to the word. It is what the parsing
/// is read against, and it is held beside [ayahId] rather than instead of it
/// because a family is drawn from the aya in four places and parsed in one.
typedef Derivative = ({
  String text,
  String? gloss,
  String? form,
  String? note,
  int wordId,
  int ayahId,
  int occurrences,
});

/// One segment of a word's parsing, in the order the word is written: a prefix,
/// the stem, a suffix. [role] is its part of speech and [features] the rest of
/// what the corpus says about it, both already named in words rather than codes.
///
/// Case and mood are assigned by the syntax of the verse, so a segment belongs
/// to one occurrence and never to a spelling. Whatever draws these has to say
/// which occurrence it is drawing.
typedef IrabSegment = ({int position, String role, List<String> features});

/// The sūra and aya an id names, written the way a reference is written.
String ayahRef(int ayahId) => '${ayahId ~/ 1000}:${ayahId % 1000}';

// The corpus's ids are its own references: an aya is sūra * 1000 + number,
// a word is aya * 1000 + position. These say which is meant where one is
// turned into the other.

/// The aya a word belongs to.
int ayahOfWord(int wordId) => wordId ~/ 1000;

/// The sūra a word belongs to.
int surahOfWord(int wordId) => wordId ~/ 1000000;

/// An aya's first word.
int firstWordOf(int ayahId) => ayahId * 1000 + 1;

/// The work the parsing is drawn from, named as its licence asks. Not
/// translated: the title, the version and the link are the attribution, and
/// a translated attribution attributes nothing. See data/SOURCES.md.
const irabWork = 'Quranic Arabic Corpus 0.4, corpus.quran.com';

/// Everything this device knows about one root. The family and the parsing come
/// from the bundled corpus; the sense comes from whatever pack was last fetched
/// into it (`senses.dart`). Lexicon prose and tafsir are fetched per root and
/// are not here.
class RootReading {
  const RootReading({
    required this.letters,
    required this.display,
    required this.translit,
    required this.occurrences,
    required this.surahCount,
    required this.sources,
    required this.coreSense,
    required this.senseSource,
    required this.senseBasis,
    required this.senseEvidence,
    required this.sensesFetched,
    required this.derivatives,
    required this.irab,
  });

  final String letters;

  /// The radicals spaced apart, the way a lexicon prints them.
  final String display;
  final String translit;

  /// Every occurrence in the Qur'an, not every distinct form.
  final int occurrences;
  final int surahCount;
  final List<String> sources;

  /// Wird's own reading of what the root means, in the language the screen
  /// asked for, or null where the pack this device fetched has no row for the
  /// root. The bundle carries none: [sensesFetched] is what tells "nobody has
  /// written one" apart from "this phone has fetched none".
  final String? coreSense;

  /// Whose reading [coreSense] is. It is the difference between a claim and a
  /// quotation, so it travels with the sense rather than being assumed.
  final String? senseSource;

  /// Why the sense is kept: one paragraph saying it was written from this
  /// root's own words and not quoted from any lexicon.
  final String? senseBasis;

  /// The words [coreSense] was read from, in the order the bar wrote them —
  /// which is grouped by morphological shape, so the order is information
  /// and not to be sorted away.
  final List<String> senseEvidence;

  /// Whether this device has ever fetched a pack of senses. A root with no
  /// [coreSense] is two different states and they need two different
  /// sentences: nobody wrote a sense for this root, or nothing has been
  /// downloaded yet. Without this the screen can only say the first, and on a
  /// phone that has never had a signal it would be saying it 1,642 times and
  /// wrongly.
  final bool sensesFetched;

  final List<Derivative> derivatives;

  /// The parsing of each derivative's first occurrence, keyed by its word id.
  /// Read in one query with the family rather than one per turn of the dial: a
  /// root's whole family is a few hundred segments, and a screen that fetches
  /// on selection draws the section empty for a frame every time.
  final Map<int, List<IrabSegment>> irab;

  bool get readsAsSpine => derivatives.length > dialCapacity;

  /// The four forms screen 1a's root panel has room for. The dial raises this
  /// to eight and the spine reads all of them; the panel is the narrowest of
  /// the three views of the same family, not a different family.
  List<Derivative> get kin => derivatives.take(4).toList(growable: false);

  /// The form [spelling] writes, or null when the family carries none of them.
  ///
  /// A derivative is held with the recitation marks taken off, while the aya
  /// — and the evidence a sense was read from — keep them, and they fall
  /// inside a word as well as after it. So the spelling is stripped the same
  /// way before it is looked for, rather than only matched as a prefix.
  Derivative? spelled(String? spelling) {
    if (spelling == null) return null;
    final bare = spelling.replaceAll(_pauseMarks, '').trim();
    for (final derivative in derivatives) {
      if (derivative.text == bare) return derivative;
    }
    for (final derivative in derivatives) {
      if (bare.startsWith(derivative.text)) return derivative;
    }
    return null;
  }
}

/// [readIn] is the locale the screen asking is drawn in — `Localizations.localeOf`,
/// which IS the locale MaterialApp resolved, not a second reading of the same
/// two steps. Required rather than defaulted: a sense drawn in the wrong
/// language is silent, and a caller that forgets should not compile.
Future<RootReading?> rootReading(
  Database db,
  String letters, {
  required Locale readIn,
}) async {
  final rows = await db.query(
    'roots',
    where: 'letters = ?',
    whereArgs: [letters],
    limit: 1,
  );
  if (rows.isEmpty) return null;
  final root = rows.first;

  final words = await db.rawQuery(
    '''SELECT w.id, w.text_ar, w.gloss_en, w.gloss_fr, w.form, MIN(n.note) AS note
         FROM words w
         LEFT JOIN root_notes n ON n.word_id = w.id
        WHERE w.root_letters = ?
        GROUP BY w.id
        ORDER BY w.id''',
    [letters],
  );

  // ponytail: two locales, so one column and a fallback. A third language is a
  // third column and a code-to-column map here, not a different shape.
  final french = readIn.languageCode == 'fr';
  // The French where there is one: a word the French pages skip keeps its
  // English rather than going blank.
  Object? glossOf(Map<String, Object?> word) =>
      (french ? word['gloss_fr'] : null) ?? word['gloss_en'];

  final order = <String>[];
  final held = <String, Map<String, Object?>>{};
  final counts = <String, int>{};
  final surahs = <int>{};
  for (final word in words) {
    final id = word['id']! as int;
    surahs.add(surahOfWord(id));
    final text = (word['text_ar']! as String)
        .replaceAll(_pauseMarks, '')
        .trim();
    counts[text] = (counts[text] ?? 0) + 1;
    final seen = held[text];
    if (seen == null) {
      order.add(text);
      held[text] = {
        'id': id,
        'gloss': glossOf(word),
        'form': word['form'],
        'note': word['note'],
      };
    } else {
      // A form occurs many times and not every occurrence was annotated, so
      // the first answer any of them gives is the one the reader sees.
      seen['gloss'] ??= glossOf(word);
      seen['form'] ??= word['form'];
      seen['note'] ??= word['note'];
    }
  }

  final derivatives =
      [
        for (final text in order)
          (
            text: text,
            gloss: held[text]!['gloss'] as String?,
            form: held[text]!['form'] as String?,
            note: held[text]!['note'] as String?,
            wordId: held[text]!['id']! as int,
            ayahId: ayahOfWord(held[text]!['id']! as int),
            occurrences: counts[text]!,
          ),
      ]..sort((a, b) {
        final byWeight = b.occurrences.compareTo(a.occurrences);
        return byWeight != 0 ? byWeight : a.ayahId.compareTo(b.ayahId);
      });

  final core = await db.query(
    'root_notes',
    columns: ['note', 'note_fr', 'source', 'basis', 'evidence'],
    where: 'root_letters = ? AND word_id IS NULL',
    whereArgs: [letters],
    limit: 1,
  );
  final sense = core.isEmpty ? const <String, Object?>{} : core.first;

  // One row or none, and only its presence is read. The version itself belongs
  // to the report a thumb sends, not to the screen.
  final pack = await db.query('sense_pack', columns: ['version'], limit: 1);

  return RootReading(
    letters: letters,
    display: root['display']! as String,
    translit: root['translit']! as String,
    occurrences: root['quran_occurrences']! as int,
    surahCount: surahs.length,
    sources: (jsonDecode(root['sources']! as String) as List).cast<String>(),
    // Falling back to the English rather than drawing nothing: a root whose
    // French never arrived is still worth reading, and the "no sense written"
    // notice would be a lie about it.
    coreSense:
        (french ? sense['note_fr'] as String? : null) ??
        sense['note'] as String?,
    senseSource: sense['source'] as String?,
    senseBasis: sense['basis'] as String?,
    senseEvidence: _evidenceWords(sense['evidence'] as String?),
    sensesFetched: pack.isNotEmpty,
    derivatives: derivatives,
    irab: await _irab(db, [
      for (final d in derivatives) d.wordId,
    ], french: french),
  );
}

/// The parsing of one word, segment by segment. Empty only for a word the
/// corpus carries no morphology for, which the ETL's own gate refuses to write.
Future<List<IrabSegment>> wordIrab(
  Database db,
  int wordId, {
  required Locale readIn,
}) async =>
    (await _irab(db, [wordId], french: readIn.languageCode == 'fr'))[wordId] ??
    const [];

/// The parsing of several words at once, keyed by word id.
///
/// Two queries rather than one: the segment rows name their part of speech by a
/// code, and the features beside it are a list of codes in one column, which no
/// join can spread. The vocabulary is 142 rows, so it is read whole and looked
/// up here.
///
/// The role names are read in the reader's language: a French sense beside an
/// English parsing is two apps on one screen.
Future<Map<int, List<IrabSegment>>> _irab(
  Database db,
  List<int> wordIds, {
  required bool french,
}) async {
  if (wordIds.isEmpty) return const {};
  final column = french ? 'role_fr' : 'role_en';
  final roles = {
    for (final row in await db.query('irab_roles', columns: ['code', column]))
      row['code']! as String: row[column]! as String,
  };
  final rows = await db.query(
    'irab',
    columns: ['word_id', 'position', 'code', 'features'],
    where: 'word_id IN (${List.filled(wordIds.length, '?').join(',')})',
    whereArgs: wordIds,
    orderBy: 'word_id, position',
  );
  final out = <int, List<IrabSegment>>{};
  for (final row in rows) {
    final code = row['code']! as String;
    // A code the vocabulary does not name cannot be written: Corpus.Check stops
    // the build over it. If one ever arrives, the code itself is shown rather
    // than a blank, so the defect is on the screen and not hidden by it.
    out.putIfAbsent(row['word_id']! as int, () => []).add((
      position: row['position']! as int,
      role: roles[code] ?? code,
      features: [
        for (final feature in (row['features']! as String).split(' '))
          if (feature.isNotEmpty) roles[feature] ?? feature,
      ],
    ));
  }
  return out;
}

/// The evidence column is the words themselves, joined by the middle dot a
/// lexicon separates headwords with.
List<String> _evidenceWords(String? evidence) => [
  if (evidence != null)
    for (final word in evidence.split(' · '))
      if (word.trim().isNotEmpty) word.trim(),
];

/// The id this root is kept under, or null where it is not kept.
///
/// Newest first, which the query has to say: `kept_items` is indexed on its id
/// alone, so an unordered `limit: 1` hands back whichever row was inserted
/// first. That was inert while the button latched. It is not now — a root can
/// carry more than one live row, because the server's own table has only `id`
/// as its primary key and two devices, one of them offline, can each mint one.
Future<String?> rootKept(Database db, String letters) async =>
    _keptId(db, 'root_letters = ?', [KeptKind.root.name, letters]);

/// Keeps a root, once, and answers with the id it is kept under — the one just
/// minted, or the one it was already kept under. A second press finds it there
/// and writes nothing, so the kept list never carries the same root twice.
Future<String> keepRoot(Database db, String letters) async =>
    await rootKept(db, letters) ??
    await keep(db, kind: KeptKind.root, rootLetters: letters);

/// Takes a root back off the kept list.
///
/// Every live row for it, not the one the screen is holding: a root reachable
/// under two live ids would come back the moment the screen reloaded, with the
/// button reading Keep again and the root still on screen 1e. An undo that
/// leaves the thing undone is worse than no undo.
Future<void> forgetRoot(Database db, String letters) async {
  for (final id in await _liveKeptIds(db, 'root_letters = ?', [
    KeptKind.root.name,
    letters,
  ])) {
    await forget(db, id);
  }
}

/// The newest live kept row for one target, or null. [what] is the column test
/// that names the target, and [args] the kind followed by that test's values.
Future<String?> _keptId(Database db, String what, List<Object?> args) async =>
    (await _liveKeptIds(db, what, args)).firstOrNull;

/// Every live kept row for one target, newest first.
///
/// The order is stated because `kept_items` carries no index but its primary
/// key, so an unordered read answers with whichever row was written first. Two
/// rows stamped in the same microsecond are still not told apart — that is not
/// worth a tiebreaker, because the undo above clears every live row rather
/// than the one this picked.
Future<List<String>> _liveKeptIds(
  Database db,
  String what,
  List<Object?> args,
) async {
  await ensureKeptTable(db);
  final rows = await db.query(
    'kept_items',
    columns: ['id'],
    where: 'kind = ? AND $what AND deleted_at IS NULL',
    whereArgs: args,
    orderBy: 'created_at DESC',
  );
  return [for (final row in rows) row['id']! as String];
}

/// The same reader, for an aya. It lives here rather than beside the deep dive
/// because the ordering and the duplicate rule above are the same rule, and a
/// second copy of them is a second place for them to drift.
Future<String?> ayaKept(Database db, int ayahId) async =>
    _keptId(db, 'ayah_id = ?', [KeptKind.aya.name, ayahId]);

/// And the same keep: a press finds the row this aya is already kept under and
/// writes nothing. The screen's own `_keptId` cannot answer this — it is read
/// once when the screen opens, so a row kept on screen 1e or arriving from a
/// sync while the deep dive sits open would mint a second live row for one aya.
Future<String> keepAya(Database db, int ayahId) async =>
    await ayaKept(db, ayahId) ??
    await keep(db, kind: KeptKind.aya, ayahId: ayahId);

/// And the same undo.
Future<void> forgetAya(Database db, int ayahId) async {
  for (final id in await _liveKeptIds(db, 'ayah_id = ?', [
    KeptKind.aya.name,
    ayahId,
  ])) {
    await forget(db, id);
  }
}

/// One lemma of a root: the dictionary form the corpus files its words under,
/// and how many words of the Qur'an are that lemma. [key] is the corpus's own
/// spelling of it, which tells apart two lemmas written alike.
typedef Lemma = ({String key, String text, int occurrences});

/// A root's lemmas, the commonest first. These are what the reading screen
/// calls its forms: raḥīm, raḥma and raḥmān, not every spelling with a prefix
/// or a suffix on it, which is how [RootReading.derivatives] groups them.
Future<List<Lemma>> lemmasOf(Database db, String root) async => [
  for (final r in await db.rawQuery(
    '''SELECT lemma_key, lemma, COUNT(*) AS n FROM words
        WHERE root_letters = ? AND lemma_key IS NOT NULL
        GROUP BY lemma_key ORDER BY n DESC, MIN(id)''',
    [root],
  ))
    (
      key: r['lemma_key']! as String,
      text: r['lemma']! as String,
      occurrences: r['n']! as int,
    ),
];

/// How many words of sūra [surah] are built on [root].
Future<int> rootCountInSurah(Database db, String root, int surah) async =>
    Sqflite.firstIntValue(
      await db.rawQuery(
        'SELECT COUNT(*) FROM words WHERE root_letters = ? '
        'AND ayah_id BETWEEN ? AND ?',
        [root, surah * 1000, surah * 1000 + 999],
      ),
    ) ??
    0;

/// One aya read for a root: its place, its words, and which of them carry
/// the root.
typedef AyaReading = ({String surahName, int number, List<AyaWord> words});

/// One word of an aya: its id, so the parsing of this occurrence can be
/// read, and whether it carries the root asked about.
typedef AyaWord = ({int id, String text, bool lit});

/// The words of each of [ayahIds], in order, marked where they carry
/// [letters]. One query however many ayas: the root sheet asks for twenty.
Future<Map<int, List<AyaWord>>> _litWords(
  Database db,
  List<int> ayahIds,
  String letters,
) async {
  final byAya = {for (final id in ayahIds) id: <AyaWord>[]};
  if (ayahIds.isEmpty) return byAya;
  final marks = List.filled(ayahIds.length, '?').join(',');
  for (final w in await db.rawQuery(
    '''SELECT id, ayah_id, text_ar, root_letters FROM words
        WHERE ayah_id IN ($marks) ORDER BY ayah_id, position''',
    ayahIds,
  )) {
    byAya[w['ayah_id']! as int]!.add((
      id: w['id']! as int,
      text: w['text_ar']! as String,
      lit: w['root_letters'] == letters,
    ));
  }
  return byAya;
}

/// The aya as it is printed, with the words carrying [letters] marked. Null
/// when the corpus has no such aya.
Future<AyaReading?> ayaReading(Database db, int ayahId, String letters) async {
  final place = await db.rawQuery(
    '''SELECT a.number, s.name_en
         FROM ayahs a
         JOIN surahs s ON s.id = a.surah_id
        WHERE a.id = ?''',
    [ayahId],
  );
  if (place.isEmpty) return null;
  return (
    surahName: place.first['name_en']! as String,
    number: place.first['number']! as int,
    words: (await _litWords(db, [ayahId], letters))[ayahId]!,
  );
}

/// An aya where a root is read, for the list of other ayas under a root: its
/// words with the root's lit, and its translation where the corpus has one.
typedef RootAya = ({int ayahId, List<AyaWord> words, String? translation});

/// The ayas [root] is read in, in muṣḥaf order, leaving out [except].
///
/// The translation is the reader's language's, Pickthall's English or Rashid
/// Maash's French.
///
/// ponytail: the first [limit] ayas, not a page. أ ل ه is read in some two
/// thousand; page this list if a reader ever wants them all.
Future<List<RootAya>> rootAyas(
  Database db,
  String root, {
  required String lang,
  int? except,
  int limit = 20,
}) async {
  final ids = [
    for (final r in await db.rawQuery(
      '''SELECT DISTINCT ayah_id FROM words
          WHERE root_letters = ? AND ayah_id != ?
          ORDER BY ayah_id LIMIT ?''',
      [root, except ?? 0, limit],
    ))
      r['ayah_id']! as int,
  ];
  final words = await _litWords(db, ids, root);
  final translated = await translationsFor(db, ids, lang);
  return [
    for (final id in ids)
      (ayahId: id, words: words[id]!, translation: translated[id]),
  ];
}
