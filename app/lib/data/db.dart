import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';

import 'audio.dart';
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
  // path_provider. Move to the app support directory if the corpus showing up
  // in a device backup ever becomes a complaint.
  final path = '${await getDatabasesPath()}/$_fileName';
  final file = File(path);
  final kept = File('$path.bak');
  // A launch killed between the two renames of an upgrade leaves the reader's
  // file under its backup name and nothing at the real one.
  if (!file.existsSync() && kept.existsSync()) await kept.rename(path);
  if (!file.existsSync()) {
    await installCorpus(file, await _bundledCorpus());
  } else if (await installedCorpusVersion(path) < bundledCorpusVersion) {
    try {
      await upgradeCorpus(file, await _bundledCorpus());
    } catch (e) {
      // The old corpus still opens and still holds every row the reader wrote;
      // the next launch tries again.
      debugPrint('corpus upgrade failed, keeping the installed one: $e');
    }
  }
  final db = await openWirdAt(path);
  if (kept.existsSync()) await kept.delete();
  return db;
}

/// The `corpus_meta.corpus_version` of `assets/corpus.db`. A constant rather
/// than read from the asset, so a launch need not copy the whole corpus out of
/// the bundle to learn it; a test holds the two equal.
const bundledCorpusVersion = 7;

Future<Uint8List> _bundledCorpus() async {
  final asset = await rootBundle.load(_corpusAsset);
  return asset.buffer.asUint8List(asset.offsetInBytes, asset.lengthInBytes);
}

/// The corpus version of the file at [path], or 0 when it has none.
Future<int> installedCorpusVersion(String path) async {
  final db = await openDatabase(path, readOnly: true, singleInstance: false);
  try {
    final rows = await db.rawQuery('SELECT corpus_version FROM corpus_meta');
    return rows.isEmpty ? 0 : rows.first['corpus_version']! as int;
  } on DatabaseException {
    return 0;
  } finally {
    await db.close();
  }
}

/// Replaces the corpus at [target] with [bytes] and carries the reader's own
/// rows across: every table the new corpus does not ship, and the senses this
/// device fetched into `root_notes`.
///
/// Before this, a corpus was installed only when no file was there, so no
/// install ever received a newer one (corpus 5's French never reached a phone
/// that had 4). The reader's tables share the file with the corpus, so the
/// file cannot simply be overwritten.
///
/// Nothing is lost at any point. The new corpus is filled in `wird.db.next`;
/// the reader's file becomes `wird.db.bak` only once that is whole, and
/// `openWird` puts it back if the second rename never happened. A failure
/// before the renames deletes `.next` and leaves the old file untouched.
Future<void> upgradeCorpus(File target, Uint8List bytes) async {
  final next = File('${target.path}.next');
  await installCorpus(next, bytes);
  try {
    final old = await openDatabase(
      target.path,
      readOnly: true,
      singleInstance: false,
    );
    final fresh = await openDatabase(next.path, singleInstance: false);
    try {
      await _carryReaderRows(old, fresh);
    } finally {
      await old.close();
      await fresh.close();
    }
  } catch (_) {
    if (next.existsSync()) await next.delete();
    rethrow;
  }
  await target.rename('${target.path}.bak');
  await next.rename(target.path);
}

Future<void> _carryReaderRows(Database old, Database fresh) async {
  final shipped = {
    for (final r in await fresh.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    ))
      r['name']! as String,
  };
  final schema = await old.rawQuery(
    "SELECT type, name, tbl_name, sql FROM sqlite_master "
    "WHERE sql IS NOT NULL AND name NOT LIKE 'sqlite_%' "
    "ORDER BY type = 'index'",
  );
  final ours = [
    for (final r in schema)
      if (r['type'] == 'table' && !shipped.contains(r['name']))
        r['name']! as String,
  ];
  await fresh.transaction((txn) async {
    for (final r in schema) {
      if (ours.contains(r['tbl_name'])) await txn.execute(r['sql']! as String);
    }
    for (final table in ours) {
      await _copyRows(old, txn, table);
    }
    if (shipped.contains('root_notes')) await _copyRows(old, txn, 'root_notes');
  });
}

/// Copies [table]'s rows by the columns both sides have, so a corpus table
/// whose shape moved between versions still takes what it can hold.
Future<void> _copyRows(Database from, Transaction to, String table) async {
  Future<Set<String>> columns(DatabaseExecutor db) async => {
    for (final c in await db.rawQuery('PRAGMA table_info($table)'))
      c['name']! as String,
  };
  final shared = (await columns(from)).intersection(await columns(to));
  if (shared.isEmpty) return;
  final names = shared.join(', ');
  for (final row in await from.rawQuery('SELECT $names FROM $table')) {
    await to.insert(table, row, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}

/// Puts the corpus at [target] in one step, or leaves nothing there.
///
/// Writing the corpus straight to the destination takes long enough on a phone to
/// be interrupted — the reader backgrounds the app, the system reclaims it,
/// the battery goes. What that left behind was a truncated file at the
/// destination, and `openWird` asks only whether the destination exists, so
/// the half-written corpus was never replaced: every later launch opened it
/// and got `database disk image is malformed`. Nothing short of clearing the
/// app's data recovered it, and a reader has no reason to think of that.
///
/// A rename inside one directory is atomic, so the destination only ever
/// holds a whole corpus. An interrupted copy leaves `wird.db.part`, which
/// nothing looks at and the next launch overwrites.
Future<void> installCorpus(File target, Uint8List bytes) async {
  await target.parent.create(recursive: true);
  final partial = File('${target.path}.part');
  await partial.writeAsBytes(bytes, flush: true);
  await partial.rename(target.path);
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
  // What the reader set for themselves on this device: how a word is annotated
  // and how large the Arabic is drawn. Device-local and outside the outbox —
  // the size that suits a phone held at arm's length is not the size that
  // suits a tablet, so this is not a preference a sync should carry across.
  await db.execute('''
    CREATE TABLE IF NOT EXISTS display_prefs (
      id          INTEGER PRIMARY KEY CHECK (id = 1),
      display     INTEGER NOT NULL,
      arabic_size REAL NOT NULL,
      header_open INTEGER NOT NULL DEFAULT 0,
      root_open   INTEGER NOT NULL DEFAULT 1
    )''');
  await ensureChromeColumns(db);
  await _ensureFrenchGlossColumn(db);
  // The language the reader chose, when they chose one. Its own table and not
  // a column on `display_prefs`, because that row is written whole: a column
  // added there would be reset by the next change of Arabic size. Absent means
  // no choice has been made, which is not the same as English — it is the
  // phone's own language, and it follows the phone when that changes.
  await db.execute('''
    CREATE TABLE IF NOT EXISTS language_pref (
      id     INTEGER PRIMARY KEY CHECK (id = 1),
      locale TEXT NOT NULL
    )''');
  // Whose voice the recitation is in. Its own table for the reason the
  // language is: `display_prefs` is written whole. Absent means the default
  // reciter, and the row is a device's choice — a reader's second phone may
  // well want another voice.
  await db.execute('''
    CREATE TABLE IF NOT EXISTS audio_pref (
      id           INTEGER PRIMARY KEY CHECK (id = 1),
      reciter      TEXT NOT NULL,
      word_by_word INTEGER NOT NULL DEFAULT 0
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
  // Which pack of senses this device fetched. The senses themselves go into
  // `root_notes`, which the corpus already ships; this is the one row that says
  // which version those rows are — and, by existing at all, that a fetch has
  // happened, which is a different thing from a root having no sense written.
  await db.execute('''
    CREATE TABLE IF NOT EXISTS sense_pack (
      id         INTEGER PRIMARY KEY CHECK (id = 1),
      version    TEXT NOT NULL,
      fetched_at TEXT NOT NULL
    )''');
  // Where the reader stands in each sūra: the word the reading screen last
  // stood on. Synced, last write wins on updated_at. Not progress — what the
  // reader understood is ayah_understood (ADR 0015).
  await db.execute('''
    CREATE TABLE IF NOT EXISTS reading_positions (
      surah_id   INTEGER PRIMARY KEY,
      word_id    INTEGER NOT NULL,
      updated_at TEXT NOT NULL
    )''');
  // How the reader last prepared a prayer, so the next one starts there. Its
  // own table and device-local, for the reason `display_prefs` is: the Arabic
  // size that suits a phone on the floor is not the one for a tablet on a
  // stand. Not a column on that row, which is written whole by screen 1a.
  await db.execute('''
    CREATE TABLE IF NOT EXISTS prayer_prefs (
      id          INTEGER PRIMARY KEY CHECK (id = 1),
      preset      TEXT,
      rakahs      INTEGER NOT NULL,
      voice       INTEGER NOT NULL,
      pace        INTEGER NOT NULL,
      wpm         INTEGER NOT NULL,
      gloss       INTEGER NOT NULL,
      around      INTEGER NOT NULL,
      arabic_size REAL NOT NULL
    )''');
  // The passages recited in prayers, for the chooser's "recently recited".
  // Device-local: what a prayer answers for is `set_prayers`, and this is only
  // a memory of what was said.
  await db.execute('''
    CREATE TABLE IF NOT EXISTS prayer_history (
      start_ayah_id INTEGER NOT NULL,
      end_ayah_id   INTEGER NOT NULL,
      recited_at    TEXT NOT NULL
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
    await txn.insert('ayah_understood', {
      'ayah_id': ayahId,
      'understood_at': at,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
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
/// the Android back button are not the Exit button. So the prayer's
/// preparation calls this when it gets the reader back.
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
      await db.rawQuery('SELECT COUNT(*) FROM set_prayers WHERE set_id = ?', [
        setId,
      ]),
    )!;

Future<ReadingOrder> readingOrder(Database db) async {
  final rows = await db.query('user_prefs', columns: ['reading_order']);
  final stored = rows.isEmpty ? null : rows.first['reading_order'];
  return ReadingOrder.values.firstWhere(
    (o) => o.name == stored,
    orElse: () => ReadingOrder.nuzul,
  );
}

/// The language the reader picked, or null to follow the phone.
///
/// Device-local and outside the outbox, like the display settings and unlike
/// the reading order: a reader who signs in on a second phone set to another
/// language has not asked for this one's choice to follow them there.
Future<String?> languagePref(Database db) async {
  final rows = await db.query('language_pref', columns: ['locale'], limit: 1);
  return rows.isEmpty ? null : rows.first['locale'] as String?;
}

/// Writes the choice, or deletes it when [locale] is null. Deleting rather
/// than storing a word for "the phone's own" keeps the absent row meaning one
/// thing, so a reader who goes back to following their phone is in the state
/// they were in before they ever opened this setting.
///
/// ponytail: no screen reaches the null. The control offers two languages and
/// always writes one, deliberately — there is no "follow my phone" option to
/// choose, because the phone's is what is already selected on arrival. The
/// branch is three lines and it is what makes the absent row mean one thing,
/// so it stays as the way back if that option is ever added.
Future<void> setLanguagePref(Database db, String? locale) async {
  if (locale == null) {
    await db.delete('language_pref');
    return;
  }
  await db.insert('language_pref', {
    'id': 1,
    'locale': locale,
  }, conflictAlgorithm: ConflictAlgorithm.replace);
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

/// Records that the reader stands on [wordId], and queues it for their other
/// devices, in one transaction.
///
/// ponytail: one op per call and no coalescing in the outbox. The reading
/// screen calls this once the reader has settled on a word, not per swipe, so
/// a sitting sends a handful. Drop older unsent moves of the same sūra if the
/// queue ever grows with them.
Future<void> movePosition(Database db, int wordId, {DateTime? at}) =>
    db.transaction((txn) async {
      final when = (at ?? DateTime.now()).toIso8601String();
      final surah = surahOfWord(wordId);
      await txn.insert('reading_positions', {
        'surah_id': surah,
        'word_id': wordId,
        'updated_at': when,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await enqueue(
        txn,
        opId: newOpId(),
        kind: 'position_moved',
        body: {
          'surah_id': surah,
          'word_id': wordId,
          'updated_at': wireTime(when),
        },
      );
    });

/// Keeps the reader's position: written once they have settled on a word,
/// not on every step, so a sitting sends a handful of moves to their other
/// devices; and written at once by [flush] when the screen goes away.
///
/// Nobody waits for the write. A database closed under it (a reader signing
/// out, a test tearing down) leaves nothing to write to and is not an error;
/// any other failure still surfaces.
class PositionKeeper {
  PositionKeeper(this.db, {this.settle = const Duration(seconds: 2)});

  final Database db;
  final Duration settle;
  Timer? _timer;
  int? _wordId;

  void move(int wordId) {
    _timer?.cancel();
    _wordId = wordId;
    _timer = Timer(settle, flush);
  }

  void flush() {
    final wordId = _wordId;
    _timer?.cancel();
    _wordId = null;
    if (wordId == null) return;
    unawaited(
      movePosition(db, wordId).catchError(
        (_) {},
        test: (e) => e is DatabaseException && e.isDatabaseClosedError(),
      ),
    );
  }
}

/// Where the reader stands in each sūra they have opened, the most recent
/// first.
Future<List<({int surah, int wordId})>> readingPositions(
  Database db, {
  int? limit,
}) async => [
  for (final r in await db.query(
    'reading_positions',
    orderBy: 'updated_at DESC',
    limit: limit,
  ))
    (surah: r['surah_id']! as int, wordId: r['word_id']! as int),
];

/// The default annotation is the gloss, and the design draws the Arabic at
/// 31px.
const defaultDisplay = 0;
const defaultArabicSize = 31.0;

/// The header arrives folded and the root panel open. On a 402x874 phone the
/// two ends of screen 1a took 40% of it between them; the header is
/// orientation, which a reader wants once, and the panel is the study, which
/// is what a word tap fills.
const defaultHeaderOpen = false;
const defaultRootOpen = true;

/// Each aya's translation is shown under it until the reader turns it off.
const defaultAyaTranslation = true;

typedef DisplayPrefs = ({
  int display,
  double arabicSize,
  bool headerOpen,
  bool rootOpen,
  bool ayaTranslation,
});

/// Adds the columns a `display_prefs` written before either end of screen 1a
/// could be folded away does not have.
Future<void> ensureChromeColumns(Database db) async {
  final columns = await db.rawQuery('PRAGMA table_info(display_prefs)');
  final have = {for (final c in columns) c['name'] as String};
  for (final (column, byDefault) in [
    ('header_open', defaultHeaderOpen),
    ('root_open', defaultRootOpen),
    ('aya_translation', defaultAyaTranslation),
  ]) {
    if (have.contains(column)) continue;
    await db.execute(
      'ALTER TABLE display_prefs ADD COLUMN $column '
      'INTEGER NOT NULL DEFAULT ${byDefault ? 1 : 0}',
    );
  }
}

Future<DisplayPrefs> displayPrefs(Database db) async {
  final rows = await db.query('display_prefs', limit: 1);
  if (rows.isEmpty) {
    return (
      display: defaultDisplay,
      arabicSize: defaultArabicSize,
      headerOpen: defaultHeaderOpen,
      rootOpen: defaultRootOpen,
      ayaTranslation: defaultAyaTranslation,
    );
  }
  return (
    display: rows.first['display']! as int,
    arabicSize: rows.first['arabic_size']! as double,
    headerOpen: rows.first['header_open'] == 1,
    rootOpen: rows.first['root_open'] == 1,
    ayaTranslation: rows.first['aya_translation'] == 1,
  );
}

/// Writes the whole row. The caller holds all four in memory, and a partial
/// write under `REPLACE` would silently reset the ones it left out.
Future<void> setDisplayPrefs(
  Database db, {
  required int display,
  required double arabicSize,
  required bool headerOpen,
  required bool rootOpen,
  required bool ayaTranslation,
}) => db.insert('display_prefs', {
  'id': 1,
  'display': display,
  'arabic_size': arabicSize,
  'header_open': headerOpen ? 1 : 0,
  'root_open': rootOpen ? 1 : 0,
  'aya_translation': ayaTranslation ? 1 : 0,
}, conflictAlgorithm: ConflictAlgorithm.replace);

/// How a prayer is prepared until the reader changes it: Maghrib, voice and
/// pace both on, forty words a minute, and the Arabic large enough to read
/// from the floor.
typedef PrayerPrefs = ({
  String? preset,
  int rakahs,
  bool voice,
  bool pace,
  int wpm,
  bool gloss,
  bool around,
  double arabicSize,
});

const defaultPrayerPrefs = (
  preset: 'maghrib',
  rakahs: 3,
  voice: true,
  pace: true,
  wpm: 40,
  gloss: true,
  around: true,
  arabicSize: 52.0,
);

Future<PrayerPrefs> prayerPrefs(Database db) async {
  final rows = await db.query('prayer_prefs', limit: 1);
  if (rows.isEmpty) return defaultPrayerPrefs;
  final r = rows.first;
  return (
    preset: r['preset'] as String?,
    rakahs: r['rakahs']! as int,
    voice: r['voice'] == 1,
    pace: r['pace'] == 1,
    wpm: r['wpm']! as int,
    gloss: r['gloss'] == 1,
    around: r['around'] == 1,
    arabicSize: r['arabic_size']! as double,
  );
}

/// Writes the whole row, as [setDisplayPrefs] does and for the same reason.
Future<void> setPrayerPrefs(Database db, PrayerPrefs p) =>
    db.insert('prayer_prefs', {
      'id': 1,
      'preset': p.preset,
      'rakahs': p.rakahs,
      'voice': p.voice ? 1 : 0,
      'pace': p.pace ? 1 : 0,
      'wpm': p.wpm,
      'gloss': p.gloss ? 1 : 0,
      'around': p.around ? 1 : 0,
      'arabic_size': p.arabicSize,
    }, conflictAlgorithm: ConflictAlgorithm.replace);

/// Remembers that [set] was recited in a prayer.
///
/// ponytail: one row per recital and never pruned. A reader praying five
/// times a day adds a few thousand short rows a year; trim to the last
/// hundred here if that ever shows.
Future<void> notePassageRecited(Database db, StudySet set) =>
    db.insert('prayer_history', {
      'start_ayah_id': set.ayas.first.id,
      'end_ayah_id': set.ayas.last.id,
      'recited_at': DateTime.now().toIso8601String(),
    });

/// The passages most recently recited, each once, the latest first.
Future<List<({int start, int end})>> recentPassages(
  Database db, {
  int limit = 3,
}) async => [
  for (final r in await db.rawQuery(
    '''SELECT start_ayah_id, end_ayah_id, MAX(recited_at) AS last
         FROM prayer_history
        GROUP BY start_ayah_id, end_ayah_id
        ORDER BY last DESC
        LIMIT ?''',
    [limit],
  ))
    (start: r['start_ayah_id']! as int, end: r['end_ayah_id']! as int),
];

/// A root's family, as screen 1a's root panel reads it.
///
/// There is one family and one member: [RootReading] and [Derivative]. The
/// panel used to have a second pair of its own, built by a second query that
/// grouped the raw `text_ar` — which keeps the pause mark the corpus stores on
/// the word it follows, so one derivative counted as two and the panel and the
/// root screen disagreed about the same root while both looked right. These
/// names are what the panel calls them.
typedef Kin = Derivative;
typedef RootDetail = RootReading;

/// One reciter the corpus carries timings for, as a reader picks them.
typedef Reciter = ({String slug, String label});

/// The reciters the reader can choose between: those the corpus times and this
/// build knows the folder of, the default first.
Future<List<Reciter>> reciters(Database db) async {
  final rows = await db.query('recitations', orderBy: 'id');
  return [
    for (final row in rows)
      if (reciterFolders.containsKey(row['slug']))
        (
          slug: row['slug']! as String,
          label: switch (row['style'] as String?) {
            null => row['reciter_name']! as String,
            final style => '${row['reciter_name']} · $style',
          },
        ),
  ];
}

/// What the reader chose to hear: the reciter, or [defaultReciter], and
/// whether a tapped word plays its own recording.
///
/// A reciter the corpus no longer carries — a later corpus dropped them, or
/// this build has no folder for them — falls back to the default, so the
/// reader hears someone rather than nothing and the settings screen shows who
/// plays. The row is rewritten with the default, keeping the word choice.
Future<({String reciter, bool wordByWord})> audioPref(Database db) async {
  final rows = await db.query('audio_pref', limit: 1);
  if (rows.isEmpty) return (reciter: defaultReciter, wordByWord: false);
  final chosen = rows.first['reciter']! as String;
  final wordByWord = rows.first['word_by_word'] == 1;
  if ((await reciters(db)).any((r) => r.slug == chosen)) {
    return (reciter: chosen, wordByWord: wordByWord);
  }
  await setAudioPref(db, reciter: defaultReciter, wordByWord: wordByWord);
  return (reciter: defaultReciter, wordByWord: wordByWord);
}

Future<void> setAudioPref(
  Database db, {
  required String reciter,
  required bool wordByWord,
}) => db.insert('audio_pref', {
  'id': 1,
  'reciter': reciter,
  'word_by_word': wordByWord ? 1 : 0,
}, conflictAlgorithm: ConflictAlgorithm.replace);

/// Gives a corpus installed before the French word glosses a `gloss_fr` column,
/// empty, so every query can name it and every word falls back to its English.
///
/// `upgradeCorpus` now brings an older install the French itself; this stays
/// for the launch where that upgrade failed and the old corpus was kept.
Future<void> _ensureFrenchGlossColumn(Database db) async {
  final columns = await db.rawQuery('PRAGMA table_info(words)');
  // No words table is a database the corpus was never copied into, which only
  // a test opens; there is nothing to add a column to.
  if (columns.isEmpty || columns.any((c) => c['name'] == 'gloss_fr')) return;
  await db.execute('ALTER TABLE words ADD COLUMN gloss_fr TEXT');
}
