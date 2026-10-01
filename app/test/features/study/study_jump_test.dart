import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wird/data/audio.dart';
import 'package:wird/data/root_repo.dart';
import 'package:wird/data/sets.dart';
import 'package:wird/features/study/study_screen.dart';
import 'package:wird/features/study/word_row.dart';
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

  /// The first of the other ayas the root sheet lists for the word the
  /// reader opens on, 96:1's first.
  Future<RootAya> firstOtherAya() async =>
      (await rootAyas(db, 'قرأ', lang: 'en', except: 96001)).first;

  /// The number that closes an aya, which is also how it is marked.
  Finder mark(int ayahId) =>
      find.byWidgetPredicate((w) => w is AyaMark && w.aya.id == ayahId);

  testWidgets('an aya the root sheet lists leads nowhere, so the aya it names '
      'cannot be read', (tester) async {
    final other = await firstOtherAya();

    await openStudy(tester);
    await tester.tap(find.byKey(const Key('more row')));
    await tester.pumpAndSettle();

    final row = find.byKey(Key('other aya ${other.ayahId}'));
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await tester.tap(row);
    await tester.pumpAndSettle();

    // The sheet opened full height, so the aya is on the strip above it.
    expect(find.text(other.text), findsWidgets);
    expect(find.text(ayahRef(other.ayahId)), findsWidgets);

    // And it can be read in full, with the way back to where the reader was.
    await tester.tap(find.byKey(const Key('sheet handle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('back to reading')), findsOneWidget);
    expect(find.byKey(const Key('read from here')), findsOneWidget);
  });

  testWidgets('an aya the reader asked for drags the set the walk would have '
      'served next onto the phone with it', (tester) async {
    // A phone with nothing downloaded, opened straight on an aya. What is
    // fetched is the ayas around it, the reading width wide; the walk's own
    // next set, Al-ʿAlaq 1–5, is not among them.
    await openStudy(tester, target: 4082);
    await settleDownloads(tester);

    expect(
      [for (final url in cdn.served) url.split('/').last],
      [
        for (final aya in [4082, 4083, 4084, 4085, 4086])
          await recitationOf(aya),
      ],
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

    // An aya whose recitation, and that of the four after it, is on the
    // phone already.
    await openStudy(tester, target: 96006);
    await settleDownloads(tester);

    expect(dir.listSync().map((f) => f.uri.pathSegments.last).toSet(), {
      for (final path in walked) path.split('/').last,
    }, reason: 'nothing was downloaded, so nothing may be thrown away');
  });

  testWidgets('the aya the reader marks after jumping to it is recorded as '
      'somewhere else, and the walk resumes in the wrong place', (
    tester,
  ) async {
    await openStudy(tester, target: 96007);
    expect(
      tester.widget<Text>(find.byKey(const Key('position'))).data,
      startsWith('96:7 '),
    );

    await tester.ensureVisible(mark(96007));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: mark(96007), matching: find.byType(Text)),
    );
    await tester.pumpAndSettle();

    expect((await db.query('ayah_understood')).map((r) => r['ayah_id']), [
      96007,
    ]);
    // The walk is derived, so it resumes where it always did — at the first
    // aya not yet understood — and stops before the hole the visit left.
    final walk = (await nextSet(db, ReadingOrder.nuzul))!;
    expect(
      [for (final aya in walk.ayas) aya.id],
      [96001, 96002, 96003, 96004, 96005],
    );
    // And the reader stays on the aya they marked.
    expect(
      tester.widget<Text>(find.byKey(const Key('position'))).data,
      startsWith('96:7 '),
    );
  });
}
