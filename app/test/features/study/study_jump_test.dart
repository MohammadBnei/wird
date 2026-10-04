import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wird/app.dart';
import 'package:wird/data/audio.dart';
import 'package:wird/data/db.dart';
import 'package:wird/data/root_repo.dart';
import 'package:wird/data/sets.dart';
import 'package:wird/features/study/root_sheet.dart';
import 'package:wird/features/study/study_screen.dart';
import 'package:wird/features/study/word_row.dart';
import 'package:wird/nav.dart';

import '../../corpus.dart';
import '../../fonts.dart';
import '../../offline.dart';
import '../../player.dart';
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
    JustAudioPlatform.instance = FakePlayers();
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
    final rootWord = other.words.firstWhere((w) => w.lit).text;
    expect(find.textContaining(rootWord, findRichText: true), findsWidgets);
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
    // fetched is the ayas from it on, [aheadAyas] of them; the walk's own
    // next set, Al-ʿAlaq 1–5, is not among them.
    await openStudy(tester, target: 4082);
    // Until the window has landed, not a fixed number of turns: a fixed
    // number fetched it on a Mac and only eight of ten on the CI runner.
    for (var i = 0; i < 500 && cdn.served.length < aheadAyas; i++) {
      await settleDownloads(tester, files: 1);
    }

    expect(cdn.served, [
      for (var aya = 4082; aya < 4082 + aheadAyas; aya++)
        '$defaultAudioOrigin${(await tracksFor(db, [aya])).single.relPath}',
    ]);
  });

  testWidgets('opening an aya the phone already holds sweeps the cache and '
      'throws away the set the reader was walking', (tester) async {
    // The phone after a walk: the set and the one after it, downloaded by the
    // cache a previous reading of screen 1a held.
    // The ayas kept from 96:6 on are on the phone too, from an earlier
    // reading of them.
    final walking = (await nextSet(db, ReadingOrder.nuzul))!;
    final alAlaq = await tracksFor(db, [
      for (var n = 1; n <= 19; n++) 96000 + n,
    ]);
    final walked = {
      for (final t in await tracksFor(db, [
        for (final aya in walking.ayas) aya.id,
      ]))
        t.relPath,
      ...windowPaths(alAlaq, 96006),
    }.toList();
    // Downloading is real file work, which only runs outside the fake-async
    // zone the test body is in. No cap here: the phone came by these files
    // over several readings.
    await tester.runAsync(
      () => AudioCache(dir, fetch: cdn.call).prefetch(walked),
    );
    expect(dir.listSync(), hasLength(walked.length));

    // An aya whose recitation, and that of the ayas kept after it, is on the
    // phone already.
    await openStudy(tester, target: 96006);
    await settleDownloads(tester);

    expect(dir.listSync().map((f) => f.uri.pathSegments.last).toSet(), {
      for (final path in walked)
        AudioCache(dir).fileFor(path).uri.pathSegments.last,
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

  Recitation recitation(WidgetTester tester) =>
      Wird.of(tester.element(find.byType(StudyScreen))).recitation;

  /// Lets the player answer until [done]: its platform calls finish outside
  /// the fake clock, and a word or an aya plays until the fake player is told
  /// to end.
  Future<void> settlePlayer(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 200 && !done(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 10));
    }
  }

  /// Silence, and the frames that let the player's timers wind down.
  Future<void> quiet(WidgetTester tester) async {
    unawaited(recitation(tester).stop());
    await settlePlayer(tester, () => false);
  }

  for (final alone in [false, true]) {
    testWidgets('a word pressed past the ayas around the open one is silent '
        '${alone ? 'in its own voice' : "in the reciter's"}', (tester) async {
      if (alone) {
        await setAudioPref(db, reciter: defaultReciter, wordByWord: true);
      }
      await openStudy(tester, target: 96001);
      await settleDownloads(tester);

      // 96:15 is well past the five ayas a prayer takes from 96:1, and its
      // recitation is not on the phone.
      final word = find.byWidgetPredicate(
        (w) => w is WordTile && w.face.word.id == 96015001,
      );
      await tester.dragUntilVisible(
        word,
        find.byType(CustomScrollView),
        const Offset(0, -200),
      );
      await tester.ensureVisible(word);
      await tester.pumpAndSettle();
      await tester.longPress(word);
      await settlePlayer(
        tester,
        () => recitation(tester).currentWordId.value == 96015001,
      );
      expect(tester.widget<WordTile>(word).voice, WordVoice.sounding);
      await quiet(tester);
    });
  }

  /// Presses play and waits for the sūra to be playing.
  Future<void> play(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.play_arrow));
    await settlePlayer(tester, () => recitation(tester).playing.value);
  }

  /// The recitation gets to [wordId], as its player reports it.
  Future<void> reciteTo(WidgetTester tester, int wordId) async {
    final tracks = recitation(tester).tracks;
    final index = tracks.indexWhere((t) => t.ayahId == ayahOfWord(wordId));
    final span = tracks[index].segments.firstWhere((s) => s.wordId == wordId);
    (JustAudioPlatform.instance as FakePlayers).players
        .firstWhere((p) => p.sounding)
        .reach(Duration(milliseconds: span.startMs + 40), index: index);
    await settlePlayer(
      tester,
      () => recitation(tester).currentWordId.value == wordId,
    );
    await tester.pumpAndSettle();
  }

  Finder theList() => find.byType(CustomScrollView);

  /// The lowest word the sūra list has built, wherever that is.
  int lowestBuilt(WidgetTester tester) => tester
      .widgetList<WordTile>(find.byType(WordTile))
      .map((w) => w.face.word.id)
      .reduce(
        (a, b) =>
            tester.getRect(find.byKey(WordKey(a))).top >=
                tester.getRect(find.byKey(WordKey(b))).top
            ? a
            : b,
      );

  /// Whether [wordId] is on the page a reader reading along reads: in view,
  /// and not yet past two thirds of the way down.
  bool onThePage(WidgetTester tester, int wordId) {
    final seen = tester.getRect(theList());
    final at = tester.getRect(find.byKey(WordKey(wordId)));
    return at.top >= seen.top && at.center.dy <= seen.top + seen.height * 2 / 3;
  }

  testWidgets('a recitation walks on down the screen while the list stays '
      'where it was', (tester) async {
    await openStudy(tester, target: 96001);
    await settleDownloads(tester);
    await play(tester);

    final word = lowestBuilt(tester);
    expect(onThePage(tester, word), isFalse, reason: 'nothing to follow');
    await reciteTo(tester, word);

    expect(onThePage(tester, word), isTrue);
    await quiet(tester);
  });

  testWidgets('a reader who scrolled away during the recitation is pulled back '
      'to it by the next word', (tester) async {
    await openStudy(tester, target: 96001);
    await settleDownloads(tester);
    await play(tester);
    await reciteTo(tester, 96001002);

    await tester.drag(theList(), const Offset(0, -150));
    await tester.pumpAndSettle();
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
    final scrolledTo = position.pixels;
    await reciteTo(tester, lowestBuilt(tester));

    expect(position.pixels, scrolledTo);
    expect(find.byKey(const Key('back to recitation')), findsOneWidget);
    await quiet(tester);
  });

  testWidgets('the way back leaves a reader who scrolled far from the '
      'recitation where they are', (tester) async {
    await openStudy(tester, target: 96001);
    await settleDownloads(tester);
    await play(tester);
    await reciteTo(tester, 96002001);

    // Far enough that 96:2 is no longer built.
    await tester.drag(theList(), const Offset(0, -3000));
    await tester.pumpAndSettle();
    expect(find.byKey(const WordKey(96002001)), findsNothing);
    await tester.tap(find.byKey(const Key('back to recitation')));
    await tester.pumpAndSettle();

    expect(find.byKey(const WordKey(96002001)), findsOneWidget);
    final seen = tester.getRect(theList());
    final at = tester.getRect(find.byKey(const WordKey(96002001)));
    expect(at.top >= seen.top && at.bottom <= seen.bottom, isTrue);
    expect(find.byKey(const Key('back to recitation')), findsNothing);
    await quiet(tester);
  });

  testWidgets('an aya held to hear it plays while the list stays where it '
      'was, as if the reader had scrolled away', (tester) async {
    await openStudy(tester, target: 96001);
    await settleDownloads(tester);

    await tester.longPress(mark(96002));
    await settlePlayer(tester, () => recitation(tester).playing.value);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('back to recitation')), findsNothing);
    await quiet(tester);
  });

  testWidgets('an aya can be heard alone only from the open word\'s aya', (
    tester,
  ) async {
    await openStudy(tester, target: 96001);
    await settleDownloads(tester);

    // Below the link to the next sūra, so not built until scrolled to.
    await tester.dragUntilVisible(
      mark(96003),
      find.byType(CustomScrollView),
      const Offset(0, -100),
    );
    await tester.ensureVisible(mark(96003));
    await tester.pumpAndSettle();
    await tester.longPress(mark(96003));
    await settlePlayer(tester, () => recitation(tester).playing.value);
    expect(recitation(tester).sounding.value?.label, '96:3');
    expect(
      (await db.query('ayah_understood')).map((r) => r['ayah_id']),
      isEmpty,
      reason: 'a hold plays the aya; only a tap marks it',
    );
    await quiet(tester);
  });

  testWidgets('a reader who only wants to read cannot fold the root away, and '
      'finds it open again on the next visit', (tester) async {
    await openStudy(tester, target: 96001);
    await settleDownloads(tester);

    await tester.drag(
      find.byKey(const Key('sheet handle')),
      const Offset(0, 300),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<RootSheet>(find.byType(RootSheet)).hidden, isTrue);
    expect(find.byKey(const Key('more row')), findsNothing);

    // The next visit to the reader.
    await openStudy(tester, target: 96001);
    await settleDownloads(tester);
    expect(tester.widget<RootSheet>(find.byType(RootSheet)).hidden, isTrue);

    await tester.drag(
      find.byKey(const Key('sheet handle')),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<RootSheet>(find.byType(RootSheet)).hidden, isFalse);
  });

  testWidgets(
    'the arrow keys stop walking the words once the sheet is folded',
    (tester) async {
      await openStudy(tester, target: 96001);
      await settleDownloads(tester);
      await tester.drag(
        find.byKey(const Key('sheet handle')),
        const Offset(0, 300),
      );
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await settleDownloads(tester, files: 8);
      expect(
        tester.widget<Text>(find.byKey(const Key('position'))).data,
        contains('word 2/'),
      );
    },
  );

  // The failure: a sūra opened on an aya hangs that aya from the list's top
  // edge, and a reader opening at 96:6 sees nothing of 96:5 above it.
  testWidgets('a sūra opened at an aya leaves its word at the top edge, with '
      'the aya before it out of sight', (tester) async {
    await openStudy(tester, target: 96006);

    final list = tester.getRect(
      find
          .ancestor(
            of: find.byKey(const WordKey(96006001)),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    final word = tester.getRect(find.byKey(const WordKey(96006001)));
    expect(
      (word.center.dy - list.center.dy).abs(),
      lessThan(list.height / 4),
      reason: 'the opened word is not in the middle of the sūra list',
    );
  });
}
