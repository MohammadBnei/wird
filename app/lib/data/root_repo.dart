import 'dart:convert';

import 'package:sqflite/sqflite.dart';

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

/// One derivative form of a root: the word as the corpus spells it, what it
/// was glossed as, and where it is first met.
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

  /// Authored prose about the root itself. The corpus ships the column and no
  /// rows yet, so this is usually absent.
  final String? coreSense;
  final List<Derivative> derivatives;

  bool get readsAsSpine => derivatives.length > dialCapacity;
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
    columns: ['note'],
    where: 'root_letters = ? AND word_id IS NULL',
    whereArgs: [letters],
    limit: 1,
  );

  return RootReading(
    letters: letters,
    display: root['display']! as String,
    translit: root['translit']! as String,
    occurrences: root['quran_occurrences']! as int,
    surahCount: surahs.length,
    sources: (jsonDecode(root['sources']! as String) as List).cast<String>(),
    coreSense: core.isEmpty ? null : core.first['note'] as String?,
    derivatives: derivatives,
  );
}

const keptRootOp = 'kept_root';

/// Whether this root has already been kept.
Future<bool> rootKept(Database db, String letters) async {
  final rows = await db.query(
    'outbox',
    where: 'kind = ? AND body = ?',
    whereArgs: [keptRootOp, jsonEncode({'root_letters': letters})],
    limit: 1,
  );
  return rows.isNotEmpty;
}

/// Keeps a root, once. The body is the whole identity of the op, so a second
/// press — or a screen reopened and pressed again — writes nothing new and the
/// sync phase has one row to send.
///
/// ponytail: keeping is one-way here. Un-keeping is a delete of a row the sync
/// phase may already have sent, which is that phase's problem to solve, and
/// screen 1e is where a reader will take something back off the list.
Future<void> keepRoot(Database db, String opId, String letters) async {
  if (await rootKept(db, letters)) return;
  await db.insert('outbox', {
    'client_op_id': opId,
    'kind': keptRootOp,
    'body': jsonEncode({'root_letters': letters}),
    'created_at': DateTime.now().toIso8601String(),
  });
}
