import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';

import 'outbox.dart';
import 'root_repo.dart';
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
  // ponytail: the plan's user rows also carry a user_id. There is no account
  // until the auth phase, so the aya's own id is the key here; the column
  // arrives with the sign-in that needs it.
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
  await db.execute('''
    CREATE TABLE IF NOT EXISTS mic_consent (
      id          INTEGER PRIMARY KEY CHECK (id = 1),
      state       TEXT NOT NULL,
      answered_at TEXT NOT NULL
    )''');
  // The sets the reader has prayed, mirroring the server's own two tables.
  // There is no ordinal here: the id is derived from the range and the reading
  // order (see setIdFor), so a reinstall recomputes the same id for the same
  // range and the server is never asked to take a second set for it. The
  // ordinal is the server's to assign.
  await db.execute('''
    CREATE TABLE IF NOT EXISTS sets (
      id            TEXT PRIMARY KEY,
      start_ayah_id INTEGER NOT NULL,
      end_ayah_id   INTEGER NOT NULL,
      reading_order TEXT NOT NULL,
      created_at    TEXT NOT NULL
    )''');
  await db.execute('''
    CREATE TABLE IF NOT EXISTS set_prayers (
      id        TEXT PRIMARY KEY,
      set_id    TEXT NOT NULL REFERENCES sets(id),
      prayed_at TEXT NOT NULL
    )''');
  // How wide the reader pulled a set, keyed to the aya it starts at. Local
  // only, and a width rather than a position.
  await db.execute('''
    CREATE TABLE IF NOT EXISTS set_span (
      start_ayah_id INTEGER PRIMARY KEY REFERENCES ayahs(id),
      ayas          INTEGER NOT NULL
    )''');
  // The op id is the primary key rather than a column, so a write that is
  // replayed — a flush that timed out after the server had already applied it,
  // a button pressed twice — lands on the same row instead of a second one.
  await db.execute('''
    CREATE TABLE IF NOT EXISTS outbox (
      client_op_id TEXT PRIMARY KEY,
      kind         TEXT NOT NULL,
      body         TEXT NOT NULL,
      created_at   TEXT NOT NULL,
      attempts     INTEGER NOT NULL DEFAULT 0
    )''');
  await ensureOutboxAttempts(db);
  return db;
}

final _entropy = Random.secure();

/// A version 4 uuid, minted on the device so an op created offline already
/// carries the identity the server will deduplicate it by.
String newOpId() {
  final bytes = List<int>.generate(16, (_) => _entropy.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// Marks every aya of the set understood and queues the one op that the sync
/// phase will flush.
///
/// Both halves happen under [opId]: a second call with the same id is the same
/// press or the same replay, and counts once. That is the property the whole
/// sync design rests on — a double-counted prayer is permanent, and in the one
/// number the app exists to show.
Future<void> markSetUnderstood(
  Database db,
  String opId,
  List<int> ayahIds,
) => db.transaction((txn) async {
  final seen = await txn.query(
    'outbox',
    where: 'client_op_id = ?',
    whereArgs: [opId],
    limit: 1,
  );
  if (seen.isNotEmpty) return;
  final at = DateTime.now().toIso8601String();
  for (final ayahId in ayahIds) {
    await txn.insert(
      'ayah_understood',
      {'ayah_id': ayahId, 'understood_at': at},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }
  await enqueue(
    txn,
    opId: opId,
    kind: 'ayah_understood',
    // The instant belongs in the op: without it the server would record the
    // reader's understanding at whatever time the flush happened to reach it,
    // which for a set marked on a plane is days late.
    body: {'ayah_ids': ayahIds, 'understood_at': wireTime(at)},
  );
});

/// Records that this set was recited in a prayer.
///
/// Screen 1b writes nothing — it runs inside the prayer, where a database
/// write has no safe moment: `dispose()` cannot await, and the back-swipe and
/// the Android back button are not the Exit button. So screen 1a calls this
/// when it gets the reader back.
///
/// One op, not two. The set travels with the prayer that names it, so there is
/// no second op to sort ahead of it and no set whose refusal takes the prayer
/// down with it. The set row is upserted because the id is derived: praying
/// the same range again is the same set, on this device and on any other.
Future<void> recordSetPrayed(Database db, StudySet set) =>
    db.transaction((txn) async {
      final at = DateTime.now().toIso8601String();
      final prayerId = newOpId();
      final body = {
        'id': prayerId,
        'set_id': set.id,
        'start_ayah_id': set.ayas.first.id,
        'end_ayah_id': set.ayas.last.id,
        'reading_order': set.order.name,
        'prayed_at': wireTime(at),
      };
      await txn.insert('sets', {
        'id': set.id,
        'start_ayah_id': set.ayas.first.id,
        'end_ayah_id': set.ayas.last.id,
        'reading_order': set.order.name,
        'created_at': at,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      await txn.insert('set_prayers', {
        'id': prayerId,
        'set_id': set.id,
        'prayed_at': at,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      await enqueue(txn, opId: prayerId, kind: 'set_prayed', body: body);
    });

/// How many prayers this set has already carried, which is what lets a screen
/// say "the fourth prayer on this set".
Future<int> prayersOnSet(Database db, String setId) async =>
    Sqflite.firstIntValue(
      await db.rawQuery(
        'SELECT COUNT(*) FROM set_prayers WHERE set_id = ?',
        [setId],
      ),
    )!;

Future<ReadingOrder> readingOrder(Database db) async {
  final rows = await db.query('user_prefs', columns: ['reading_order']);
  final stored = rows.isEmpty ? null : rows.first['reading_order'];
  return ReadingOrder.values.firstWhere(
    (o) => o.name == stored,
    orElse: () => ReadingOrder.nuzul,
  );
}

Future<void> setReadingOrder(Database db, ReadingOrder order) =>
    db.transaction((txn) async {
      final at = DateTime.now().toIso8601String();
      await txn.insert('user_prefs', {
        'id': 1,
        'reading_order': order.name,
        'updated_at': at,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await enqueue(
        txn,
        opId: newOpId(),
        kind: 'prefs_set',
        body: {'reading_order': order.name, 'updated_at': wireTime(at)},
      );
    });

/// A word that shares the root, with the gloss it was given and the aya it is
/// first met in.
typedef Kin = ({String text, String? gloss, int ayahId});

class RootDetail {
  const RootDetail({
    required this.display,
    required this.translit,
    required this.occurrences,
    required this.sources,
    required this.kin,
  });

  /// The three radicals spaced apart, the way a lexicon prints them.
  final String display;
  final String translit;
  final int occurrences;
  final List<String> sources;
  final List<Kin> kin;
}

/// What screen 1a's root panel says about the root of the word just tapped.
///
/// [rootReading] is authoritative about what a kin is, and the panel takes its
/// four from there rather than running a second query of its own. It used to
/// group the raw `text_ar`, which keeps the pause mark the corpus stores on the
/// word it follows — so one derivative counted as two, and the panel and the
/// root screen disagreed about the same root while both looked right.
///
/// A kin's aya is where that form is **first met in the muṣḥaf**, not the
/// nearest occurrence to the reader. A form that occurs eighty times has no one
/// aya, and the first is the only one that can be named without inventing a
/// rule the reader cannot see.
Future<RootDetail?> rootDetail(Database db, String letters) async {
  final reading = await rootReading(db, letters);
  if (reading == null) return null;
  return RootDetail(
    display: reading.display,
    translit: reading.translit,
    occurrences: reading.occurrences,
    sources: reading.sources,
    // ponytail: four kin, the number the study panel has room for. The root
    // screen's dial raises this to eight, and the spine layout is what reads
    // all 103 derivatives of a big root.
    kin: [
      for (final d in reading.derivatives.take(4))
        (text: d.text, gloss: d.gloss, ayahId: d.ayahId),
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
