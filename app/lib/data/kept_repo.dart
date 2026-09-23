import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'db.dart';

/// What the reader kept. The three kinds are the three the design filters by.
enum KeptKind { aya, root, note }

/// One thing the reader kept, with the corpus rows it points at already read.
class KeptItem {
  const KeptItem({
    required this.id,
    required this.kind,
    required this.body,
    required this.tags,
    required this.createdAt,
    this.ayahId,
    this.arabic,
    this.rootLetters,
  });

  final String id;
  final KeptKind kind;

  /// The reader's own words. Empty for a bookmark kept without a note.
  final String body;
  final List<String> tags;
  final DateTime createdAt;

  final int? ayahId;

  /// The aya as the corpus writes it, read at load time so the card can draw
  /// it without a second trip.
  final String? arabic;
  final String? rootLetters;

  int? get surahId => ayahId == null ? null : ayahId! ~/ 1000;
  int? get ayahNumber => ayahId == null ? null : ayahId! % 1000;

  /// The design flags an aya to come back to; it is a tag rather than a
  /// column, so a second flag costs no migration.
  bool get flagged => tags.contains('revisit');
}

/// Creates the table the kept list lives in, if this database has not got it.
///
/// The columns are the plan's, tombstone included, so the sync phase can take
/// this table over without a migration. As in db.dart there is no user_id: the
/// column arrives with the sign-in that needs it.
Future<void> ensureKeptTable(Database db) => db.execute('''
  CREATE TABLE IF NOT EXISTS kept_items (
    id           TEXT PRIMARY KEY,
    kind         TEXT NOT NULL,
    ayah_id      INTEGER REFERENCES ayahs(id),
    root_letters TEXT,
    body         TEXT NOT NULL DEFAULT '',
    tags         TEXT NOT NULL DEFAULT '[]',
    created_at   TEXT NOT NULL,
    updated_at   TEXT NOT NULL,
    deleted_at   TEXT
  )''');

/// Keeps one aya, root or note, and answers with the id it was minted under.
///
/// The id is minted here rather than by a server, so an item kept on a plane
/// already carries the identity the sync will deduplicate it by.
Future<String> keep(
  Database db, {
  required KeptKind kind,
  int? ayahId,
  String? rootLetters,
  String body = '',
  List<String> tags = const [],
  String? id,
}) async {
  await ensureKeptTable(db);
  final now = DateTime.now().toIso8601String();
  final minted = id ?? newOpId();
  await db.insert('kept_items', {
    'id': minted,
    'kind': kind.name,
    'ayah_id': ayahId,
    'root_letters': rootLetters,
    'body': body,
    'tags': jsonEncode(tags),
    'created_at': now,
    'updated_at': now,
  }, conflictAlgorithm: ConflictAlgorithm.ignore);
  return minted;
}

/// Drops an item from the list without dropping the row: the tombstone is
/// what stops the other device from handing the item straight back on the
/// next sync.
Future<void> forget(Database db, String id) async {
  await ensureKeptTable(db);
  final now = DateTime.now().toIso8601String();
  await db.update(
    'kept_items',
    {'deleted_at': now, 'updated_at': now},
    where: 'id = ? AND deleted_at IS NULL',
    whereArgs: [id],
  );
}

/// The kept list, newest first: one [kind] when the reader has picked a
/// segment, and only the items whose text matches [search].
Future<List<KeptItem>> keptItems(
  Database db, {
  KeptKind? kind,
  String search = '',
}) async {
  await ensureKeptTable(db);
  final rows = await db.rawQuery(
    '''
    SELECT k.id, k.kind, k.ayah_id, k.root_letters, k.body, k.tags,
           k.created_at, a.text_uthmani
      FROM kept_items k
      LEFT JOIN ayahs a ON a.id = k.ayah_id
     WHERE k.deleted_at IS NULL
       ${kind == null ? '' : 'AND k.kind = ?'}
     ORDER BY k.created_at DESC''',
    [if (kind != null) kind.name],
  );

  final items = [
    for (final row in rows)
      KeptItem(
        id: row['id']! as String,
        kind: KeptKind.values.byName(row['kind']! as String),
        body: row['body'] as String? ?? '',
        tags: (jsonDecode(row['tags']! as String) as List).cast<String>(),
        createdAt: DateTime.parse(row['created_at']! as String),
        ayahId: row['ayah_id'] as int?,
        arabic: row['text_uthmani'] as String?,
        rootLetters: row['root_letters'] as String?,
      ),
  ];
  final needle = foldArabic(search);
  if (needle.isEmpty) return items;
  return [
    for (final item in items)
      if (_haystack(item).contains(needle)) item,
  ];
}

String _haystack(KeptItem item) => foldArabic(
  [
    item.body,
    item.arabic ?? '',
    item.rootLetters ?? '',
    item.tags.join(' '),
    if (item.ayahId != null) '${item.surahId}:${item.ayahNumber}',
  ].join(' '),
);

final _marks = RegExp('[\u0610-\u061a\u064b-\u065f\u0670\u06d6-\u06ed\u0640]');

/// Folds a string to what a reader types: the corpus writes the Qur'an fully
/// vowelled, and nobody searching for a root types the marks inside it.
String foldArabic(String text) => text
    .replaceAll(_marks, '')
    .replaceAll(RegExp('[\u0622\u0623\u0625\u0671]'), '\u0627')
    .replaceAll('\u0649', '\u064a')
    .replaceAll('\u0629', '\u0647')
    .toLowerCase()
    .trim();
