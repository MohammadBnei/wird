import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'kept_repo.dart';

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
typedef Derivative = ({
  String text,
  String? gloss,
  String? form,
  String? note,
  int ayahId,
  int occurrences,
});

/// The sūra and aya an id names, written the way a reference is written.
String ayahRef(int ayahId) => '${ayahId ~/ 1000}:${ayahId % 1000}';

/// Everything the bundled corpus knows about one root. Lexicon prose, tafsir
/// and iʿrāb are fetched rather than bundled, so they are not here.
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
    required this.derivatives,
  });

  final String letters;

  /// The radicals spaced apart, the way a lexicon prints them.
  final String display;
  final String translit;

  /// Every occurrence in the Qur'an, not every distinct form.
  final int occurrences;
  final int surahCount;
  final List<String> sources;

  /// Wird's own reading of what the root means, or null where the root's own
  /// words did not bear one out. 523 of 1,642 roots carry it.
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

  final List<Derivative> derivatives;

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

Future<RootReading?> rootReading(Database db, String letters) async {
  final rows = await db.query(
    'roots',
    where: 'letters = ?',
    whereArgs: [letters],
    limit: 1,
  );
  if (rows.isEmpty) return null;
  final root = rows.first;

  final words = await db.rawQuery(
    '''SELECT w.id, w.text_ar, w.gloss_en, w.form, MIN(n.note) AS note
         FROM words w
         LEFT JOIN root_notes n ON n.word_id = w.id
        WHERE w.root_letters = ?
        GROUP BY w.id
        ORDER BY w.id''',
    [letters],
  );

  final order = <String>[];
  final held = <String, Map<String, Object?>>{};
  final counts = <String, int>{};
  final surahs = <int>{};
  for (final word in words) {
    final id = word['id']! as int;
    surahs.add(id ~/ 1000000);
    final text = (word['text_ar']! as String).replaceAll(_pauseMarks, '').trim();
    counts[text] = (counts[text] ?? 0) + 1;
    final seen = held[text];
    if (seen == null) {
      order.add(text);
      held[text] = {
        'id': id,
        'gloss': word['gloss_en'],
        'form': word['form'],
        'note': word['note'],
      };
    } else {
      // A form occurs many times and not every occurrence was annotated, so
      // the first answer any of them gives is the one the reader sees.
      seen['gloss'] ??= word['gloss_en'];
      seen['form'] ??= word['form'];
      seen['note'] ??= word['note'];
    }
  }

  final derivatives = [
    for (final text in order)
      (
        text: text,
        gloss: held[text]!['gloss'] as String?,
        form: held[text]!['form'] as String?,
        note: held[text]!['note'] as String?,
        ayahId: (held[text]!['id']! as int) ~/ 1000,
        occurrences: counts[text]!,
      ),
  ]..sort((a, b) {
    final byWeight = b.occurrences.compareTo(a.occurrences);
    return byWeight != 0 ? byWeight : a.ayahId.compareTo(b.ayahId);
  });

  final core = await db.query(
    'root_notes',
    columns: ['note', 'source', 'basis', 'evidence'],
    where: 'root_letters = ? AND word_id IS NULL',
    whereArgs: [letters],
    limit: 1,
  );
  final sense = core.isEmpty ? const <String, Object?>{} : core.first;

  return RootReading(
    letters: letters,
    display: root['display']! as String,
    translit: root['translit']! as String,
    occurrences: root['quran_occurrences']! as int,
    surahCount: surahs.length,
    sources: (jsonDecode(root['sources']! as String) as List).cast<String>(),
    coreSense: sense['note'] as String?,
    senseSource: sense['source'] as String?,
    senseBasis: sense['basis'] as String?,
    senseEvidence: _evidenceWords(sense['evidence'] as String?),
    derivatives: derivatives,
  );
}

/// The evidence column is the words themselves, joined by the middle dot a
/// lexicon separates headwords with.
List<String> _evidenceWords(String? evidence) => [
  if (evidence != null)
    for (final word in evidence.split(' · '))
      if (word.trim().isNotEmpty) word.trim(),
];

/// Whether this root is already on the kept list.
Future<bool> rootKept(Database db, String letters) async {
  await ensureKeptTable(db);
  final rows = await db.query(
    'kept_items',
    where: 'kind = ? AND root_letters = ? AND deleted_at IS NULL',
    whereArgs: [KeptKind.root.name, letters],
    limit: 1,
  );
  return rows.isNotEmpty;
}

/// Keeps a root, once. A second press — or the screen reopened and pressed
/// again — finds it already there and writes nothing, so the kept list never
/// carries the same root twice.
///
/// ponytail: keeping is one-way from here. Taking a root back off the list is
/// what screen 1e's own delete is for, and it already leaves the tombstone the
/// sync needs.
Future<void> keepRoot(Database db, String letters) async {
  if (await rootKept(db, letters)) return;
  await keep(db, kind: KeptKind.root, rootLetters: letters);
}
