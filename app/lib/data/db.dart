import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';

import 'sets.dart';

const _corpusAsset = 'assets/corpus.db';
const _fileName = 'wird.db';

/// Opens the one database the app has. sqflite cannot open an asset in place,
/// so first launch copies the corpus out of the bundle; the user's own tables
/// are then created inside that same file, because progress and kept items are
/// read by joining them against corpus rows and ATTACH DATABASE is fragile
/// across platforms.
Future<Database> openWird() async {
  // ponytail: sqflite's own databases directory, so the app needs no
  // path_provider. Move to the app support directory if the 24 MB corpus
  // showing up in a device backup ever becomes a complaint.
  final path = '${await getDatabasesPath()}/$_fileName';
  final file = File(path);
  if (!file.existsSync()) {
    final asset = await rootBundle.load(_corpusAsset);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(
      asset.buffer.asUint8List(asset.offsetInBytes, asset.lengthInBytes),
      flush: true,
    );
  }
  return openWirdAt(path);
}

/// Opens a file that already holds the corpus, and makes sure the user tables
/// are there beside it.
Future<Database> openWirdAt(String path) async {
  final db = await openDatabase(path);
  // ponytail: the plan's user rows carry a client-minted uuid and a user_id.
  // There is no account and no outbox until the sync phase, so the aya's own
  // id is the key; both columns arrive with the op log that needs them.
  await db.execute('''
    CREATE TABLE IF NOT EXISTS ayah_understood (
      ayah_id       INTEGER PRIMARY KEY REFERENCES ayahs(id),
      understood_at TEXT NOT NULL
    )''');
  await db.execute('''
    CREATE TABLE IF NOT EXISTS user_prefs (
      id            INTEGER PRIMARY KEY CHECK (id = 1),
      reading_order TEXT NOT NULL,
      updated_at    TEXT NOT NULL
    )''');
  return db;
}

Future<void> markUnderstood(Database db, int ayahId) => db.insert(
  'ayah_understood',
  {'ayah_id': ayahId, 'understood_at': DateTime.now().toIso8601String()},
  conflictAlgorithm: ConflictAlgorithm.ignore,
);

Future<ReadingOrder> readingOrder(Database db) async {
  final rows = await db.query('user_prefs', columns: ['reading_order']);
  final stored = rows.isEmpty ? null : rows.first['reading_order'];
  return ReadingOrder.values.firstWhere(
    (o) => o.name == stored,
    orElse: () => ReadingOrder.nuzul,
  );
}

Future<void> setReadingOrder(Database db, ReadingOrder order) => db.insert(
  'user_prefs',
  {
    'id': 1,
    'reading_order': order.name,
    'updated_at': DateTime.now().toIso8601String(),
  },
  conflictAlgorithm: ConflictAlgorithm.replace,
);

/// A word that shares the root, with the gloss it was given.
typedef Kin = ({String text, String? gloss});

class RootDetail {
  const RootDetail({
    required this.letters,
    required this.display,
    required this.translit,
    required this.occurrences,
    required this.sources,
    required this.kin,
  });

  final String letters;

  /// The three radicals spaced apart, the way a lexicon prints them.
  final String display;
  final String translit;
  final int occurrences;
  final List<String> sources;
  final List<Kin> kin;
}

Future<RootDetail?> rootDetail(Database db, String letters) async {
  final rows = await db.query(
    'roots',
    where: 'letters = ?',
    whereArgs: [letters],
    limit: 1,
  );
  if (rows.isEmpty) return null;
  final root = rows.first;
  // ponytail: eight kin, the ceiling the root screen draws on its dial.
  // The spine layout is what reads all 103 derivatives of a big root.
  final kin = await db.rawQuery(
    '''SELECT text_ar, MIN(gloss_en) AS gloss_en
         FROM words
        WHERE root_letters = ?
        GROUP BY text_ar
        ORDER BY COUNT(*) DESC
        LIMIT 8''',
    [letters],
  );
  return RootDetail(
    letters: letters,
    display: root['display']! as String,
    translit: root['translit']! as String,
    occurrences: root['quran_occurrences']! as int,
    sources: (jsonDecode(root['sources']! as String) as List).cast<String>(),
    kin: [
      for (final k in kin)
        (text: k['text_ar']! as String, gloss: k['gloss_en'] as String?),
    ],
  );
}

/// The reciter whose audio the corpus carries paths for.
Future<String?> reciterLabel(Database db) async {
  final rows = await db.query('recitations', limit: 1);
  if (rows.isEmpty) return null;
  final style = rows.first['style'] as String?;
  final name = rows.first['reciter_name']! as String;
  return style == null ? name : '$name · $style';
}
