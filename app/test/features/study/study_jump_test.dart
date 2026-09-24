import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wird/data/audio.dart';
import 'package:wird/data/db.dart';
import 'package:wird/data/sets.dart';
import 'package:wird/features/study/study_screen.dart';
import 'package:wird/nav.dart';

import '../../corpus.dart';
import '../../fonts.dart';
import '../../offline.dart';
import '../../wird.dart';

/// One file of the recitation, in bytes the cap can be written against.
const _fileBytes = 1024;

/// Room for six of them. Screen 1a opens the walk's set and the set after it,
/// which is ten, so the cache is over the cap from the first load and a sweep
/// always has something it could throw away.
const _cap = 6 * _fileBytes;

/// Lets the recitation actually arrive. Real file work never completes inside
/// the fake-async zone a widget test body runs in, so each awaited file needs
/// a turn of the real event loop and a pump to carry its continuation back.
Future<void> settleDownloads(WidgetTester tester, {int files = 48}) async {
  for (var i = 0; i < files; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1)),
    );
    await tester.pumpAndSettle();
  }
}

void main() {
  late Database db;
  late Directory dir;
  late FakeCdn cdn;

  setUpAll(loadBundledFonts);
  // The corpus copy and the cache directory are real file work, which only
  // completes out here.
  setUp(() async {
    db = await testCorpus();
    dir = await tempAudioDir();
    cdn = FakeCdn(bytes: _fileBytes);
  });

  Future<void> openStudy(WidgetTester tester, {int? target}) async {
    await pumpPhone(
      tester,
      await wirdAround(
        db,
        StudyScreen(db: db, target: target),
        route: Routes.study,
        cache: AudioCache(dir, fetch: cdn.call, capBytes: _cap),
      ),
    );
  }

  /// The file name the recitation of an aya is downloaded as.
  Future<String> recitationOf(int ayahId) async =>
      (await tracksFor(db, [ayahId])).single.relPath.split('/').last;

  /// The kin the root panel offers first, and the aya it leads to.
  Future<Kin> firstKin() async =>
      (await rootDetail(db, (await nextSet(db, ReadingOrder.nuzul))!
          .ayas.first.words.first.root!))!.kin.first;

  testWidgets('a kin printed in the root panel leads nowhere, so the aya it '
      'names cannot be read', (tester) async {
    final kin = await firstKin();
    final surah = (await db.query(
      'surahs',
      columns: ['name_en'],
      where: 'id = ?',
      whereArgs: [kin.ayahId ~/ 1000],
    )).single['name_en']! as String;

    await openStudy(tester);
    expect(find.textContaining("Al-'Alaq 1"), findsOneWidget);

    await tester.tap(find.byKey(ValueKey('kin-${kin.text}-${kin.ayahId}')));
    await tester.pumpAndSettle();

    expect(find.textContaining('$surah ${kin.ayahId % 1000}'), findsOneWidget);
    expect(find.textContaining('VISITING'), findsOneWidget);
  });

  testWidgets('an aya the reader asked for drags the set the walk would have '
      'served next onto the phone with it', (tester) async {
    // A phone with nothing downloaded, opened straight on an aya. On the walk
    // the set after this one is fetched too; there is no set after an aya the
    // reader asked for, and the walk's own next set is not it.
    await openStudy(tester, target: 4082);
    await settleDownloads(tester);

    expect(
      [for (final url in cdn.served) url.split('/').last],
      [await recitationOf(4082)],
    );
  });

  testWidgets('opening an aya the phone already holds sweeps the cache and '
      'throws away the set the reader was walking', (tester) async {
    // The phone after a walk: the set and the one after it, downloaded by the
    // cache a previous reading of screen 1a held.
    final walking = (await nextSet(db, ReadingOrder.nuzul))!;
    final walked = await pathsToKeep(db, ReadingOrder.nuzul, walking);
    // Downloading is real file work, which only runs outside the fake-async
    // zone the test body is in.
    await tester.runAsync(
      () => AudioCache(dir, fetch: cdn.call, capBytes: _cap).prefetch(walked),
    );
    expect(dir.listSync(), hasLength(walked.length));

    // An aya out of the set after this one, which is on the phone already.
    await openStudy(tester, target: 96007);
    await settleDownloads(tester);

    expect(
      dir.listSync().map((f) => f.uri.pathSegments.last).toSet(),
      {for (final path in walked) path.split('/').last},
      reason: 'nothing was downloaded, so nothing may be thrown away',
    );
  });

  testWidgets('the aya the reader marks after jumping to it is recorded as '
      'somewhere else, and the walk resumes in the wrong place', (tester) async {
    await openStudy(tester, target: 96007);
    expect(find.textContaining("Al-'Alaq 7"), findsOneWidget);

    await tester.tap(find.text('Mark set understood'));
    await tester.pumpAndSettle();

    expect(
      (await db.query('ayah_understood')).map((r) => r['ayah_id']),
      [96007],
    );
    // The walk is derived, so it resumes where it always did — at the first
    // aya not yet understood — and stops before the hole the visit left.
    final walk = (await nextSet(db, ReadingOrder.nuzul))!;
    expect([for (final aya in walk.ayas) aya.id], [
      96001,
      96002,
      96003,
      96004,
      96005,
    ]);

    await tester.tap(find.text('Next set'));
    await tester.pumpAndSettle();
    expect(find.textContaining("Al-'Alaq 1–5"), findsOneWidget);
    expect(find.textContaining('VISITING'), findsNothing);
  });
}
