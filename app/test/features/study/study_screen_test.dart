import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:wird/features/study/word_row.dart';
import 'package:record/record.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wird/data/audio.dart';
import 'package:wird/data/sets.dart';
import 'package:wird/data/mic.dart';
import 'package:wird/features/deepdive/deep_dive_screen.dart';
import 'package:wird/features/prayer/prepare_screen.dart';
import 'package:wird/features/settings/settings_screen.dart';
import 'package:wird/features/root/root_lookup.dart';
import 'package:wird/features/study/root_sheet.dart';
import 'package:wird/features/study/study_screen.dart';
import 'package:wird/nav.dart';
import 'package:wird/theme/nocturne.dart';

import '../../corpus.dart';
import '../../fonts.dart';
import '../../microphone.dart';
import '../../offline.dart';
import '../../player.dart';
import '../../wird.dart';

/// The word as the corpus spells it, harakat and all. Read from the database
/// rather than typed here, so the test cannot pass against a text the screen
/// never shows.
Future<String> word(Database db, int id) async {
  final rows = await db.query('words', where: 'id = ?', whereArgs: [id]);
  return rows.single['text_ar']! as String;
}

/// A word by its corpus id. Al-ʿAlaq repeats ٱقْرَأْ and ٱلَّذِى inside one
/// set, so a finder on the text alone matches the wrong tile.
Finder tile(int wordId) => find.byKey(WordKey(wordId));

/// Lets the player answer. Its platform calls finish outside the fake clock a
/// widget test runs on, so real time and frames are let run in turns.
Future<void> settlePlayer(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump();
  }
}

/// Whether a word's tile has been built at all.
///
/// The reading is a lazy sliver list. The transport left that list for the
/// pinned footer, so the pane is one transport shorter than it was and the
/// set's last aya is no longer built on the first frame. A row that was never
/// built paints nothing, so it can carry no claim either way — these tests ask
/// their question of the rows the reader is actually looking at.
bool drawn(int wordId) => tile(wordId).evaluate().isNotEmpty;

/// The Arabic of a word: the first thing painted in its tile, above the
/// transliteration and the gloss.
Finder arabic(int wordId) =>
    find.descendant(of: tile(wordId), matching: find.byType(Text)).first;

Text arabicOf(WidgetTester tester, int wordId) =>
    tester.widget<Text>(arabic(wordId));

/// A root as the sheet names it, over the word open. The ring further down
/// the sheet prints the same letters at its centre.
Finder rootNamed(String display) => find.descendant(
  of: find.byKey(const ValueKey('open-root')),
  matching: find.text(display),
);

/// The line under a word's Arabic, which says the word has a root.
Color underlineOf(WidgetTester tester, int wordId) {
  final box = tester.widget<Container>(
    find.ancestor(of: arabic(wordId), matching: find.byType(Container)).first,
  );
  return ((box.decoration! as BoxDecoration).border! as Border).bottom.color;
}

/// Whether a word is drawn as the one the reader is looking at: its Arabic
/// glows in the reading tone, which no other word wears.
bool lit(WidgetTester tester, int wordId) {
  final style = arabicOf(tester, wordId).style!;
  return style.color == Nocturne.of(tester.element(tile(wordId))).accent &&
      (style.shadows?.isNotEmpty ?? false);
}

/// The number that closes an aya, which is also how it is marked understood.
Finder mark(int ayahId) =>
    find.byWidgetPredicate((w) => w is AyaMark && w.aya.id == ayahId);

void main() {
  late Database db;
  late AudioCache audio;

  setUpAll(loadBundledFonts);
  // Both the corpus copy and the cache directory are real file work, which
  // never completes inside the fake-async zone a widget test body runs in.
  setUp(() async {
    db = await testCorpus();
    audio = await emptyCache();
  });

  /// The screen on a phone that has never been online: no recitation on disk
  /// and no way to fetch one.
  Future<void> openStudy(WidgetTester tester) async {
    // A phone that has never been online: nothing on disk, and nothing the
    // player can fetch.
    JustAudioPlatform.instance = FakePlayers(offline: true);
    await pumpPhone(
      tester,
      await wirdAround(
        db,
        StudyScreen(db: db),
        route: Routes.study,
        cache: audio,
        onGenerateRoute: (settings) => MaterialPageRoute<void>(
          builder: (_) => screens[settings.name]!(db, settings.arguments),
        ),
      ),
    );
  }

  /// The preferences, in the sheet the drawer opens over the set.
  Future<void> openSettings(WidgetTester tester) async {
    unawaited(showSettings(tester.element(find.byType(StudyScreen))));
    await tester.pumpAndSettle();
  }

  testWidgets('the aya paints left to right, or loses the harakat the corpus '
      'stores', (tester) async {
    await openStudy(tester);

    final painted = arabicOf(tester, 96001001);
    expect(painted.data, await word(db, 96001001));
    expect(
      painted.data,
      contains('ْ'),
      reason: 'the sukūn the corpus stores survives into the painted text',
    );
    expect(painted.textDirection, TextDirection.rtl);
    expect(painted.style!.fontFamily, Nocturne.arabicFamily);
  });

  testWidgets('tapping a word blanks the aya while the root panel catches up', (
    tester,
  ) async {
    await openStudy(tester);
    expect(rootNamed('ق ر أ'), findsOneWidget);

    await tester.tap(tile(96002004));
    await tester.pump();
    expect(
      tile(96002004),
      findsOneWidget,
      reason: 'the aya stays on screen while the new root is read',
    );

    await tester.pumpAndSettle();
    expect(rootNamed('ع ل ق'), findsOneWidget);
    expect(rootNamed('ق ر أ'), findsNothing);
  });

  testWidgets('a word with no root wears the rule that says a root is under '
      'it, now the arrows can walk onto one', (tester) async {
    await openStudy(tester);

    // ٱلَّذِى, the sūra's fourth word and its first particle.
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byKey(const Key('next word')));
      await tester.pumpAndSettle();
    }

    expect(find.text('No root'), findsOneWidget);
    expect(underlineOf(tester, 96001004), Colors.transparent);
  });

  testWidgets('turning the gloss off takes the Arabic with it', (tester) async {
    await openStudy(tester);
    expect(find.text('a clinging substance'), findsOneWidget);

    await openSettings(tester);
    await tester.tap(find.text('Neither'));
    await tester.pumpAndSettle();
    await closeSettings(tester);

    expect(find.text('a clinging substance'), findsNothing);
    expect(find.text(await word(db, 96002004)), findsOneWidget);
  });

  testWidgets('the Arabic size setting leaves the aya at the size it was', (
    tester,
  ) async {
    await openStudy(tester);
    final before = arabicOf(tester, 96001001).style!.fontSize;

    await openSettings(tester);
    await tester.drag(find.byType(Slider), const Offset(-200, 0));
    await tester.pumpAndSettle();
    await closeSettings(tester);

    final after = arabicOf(tester, 96001001).style!.fontSize!;
    expect(after, isNot(before));
    expect(after, inInclusiveRange(24, 44));
  });

  testWidgets('tapping a word sounds it instead of opening the root, which is '
      'the intent the reader reaches for far more often', (tester) async {
    await openStudy(tester);
    final rows = await db.query('words', where: 'id = 96002004');
    final translit = rows.single['translit']! as String;
    expect(rootNamed('ق ر أ'), findsOneWidget);

    await tester.tap(tile(96002004));
    await tester.pumpAndSettle();

    expect(rootNamed('ع ل ق'), findsOneWidget);
    expect(
      find.descendant(of: tile(96002004), matching: find.text(translit)),
      findsNothing,
      reason: 'a tap asked what the word means, not what it sounds like',
    );

    // The press is the one that asks for the sound, and this phone has never
    // been online, so the transliteration stands in for it. The player's
    // refusal arrives over its platform channel, outside the fake clock.
    await tester.longPress(tile(96002004));
    await settlePlayer(tester);
    expect(
      find.descendant(of: tile(96002004), matching: find.text(translit)),
      findsOneWidget,
    );
  });

  testWidgets('a word carrying no root is a dead tile that answers a tap with '
      'nothing at all', (tester) async {
    await openStudy(tester);

    await tester.tap(tile(96001004));
    await tester.pumpAndSettle();

    expect(lit(tester, 96001004), isTrue);
    expect(
      find.descendant(
        of: find.byType(RootSheet),
        matching: find.text('No root'),
      ),
      findsOneWidget,
      reason: 'the sheet opens on the particle and says it has no root',
    );
  });

  testWidgets('nothing on the row says which word the open root belongs to', (
    tester,
  ) async {
    await openStudy(tester);
    final set = (await nextSet(db, ReadingOrder.nuzul))!;
    final ids = [
      for (final aya in set.ayas)
        for (final word in aya.words) word.id,
    ];
    expect(
      [
        for (final id in ids)
          if (drawn(id) && lit(tester, id)) id,
      ],
      [96001001],
      reason: 'the sheet opens on the first word and the page says so',
    );

    await tester.tap(tile(96002004));
    await tester.pumpAndSettle();

    expect(
      [
        for (final id in ids)
          if (drawn(id) && lit(tester, id)) id,
      ],
      [96002004],
      reason: 'one word at a time wears the accent, and it is the one tapped',
    );
  });

  testWidgets('working down a row of words spins, or shouts one snackbar per '
      'word that cannot be heard', (tester) async {
    await openStudy(tester);
    final set = (await nextSet(db, ReadingOrder.nuzul))!;
    final shown = tester.getRect(find.byType(CustomScrollView));
    var tapped = 0;

    for (final aya in set.ayas) {
      for (final word in aya.words) {
        // A tile scrolled out of the set's own pane would take the tap on
        // whatever is painted over it, which proves nothing about the word.
        if (!drawn(word.id)) continue;
        final rect = tester.getRect(tile(word.id));
        if (rect.top < shown.top || rect.bottom > shown.bottom) continue;
        await tester.tap(tile(word.id));
        await tester.pump();
        tapped++;
      }
    }
    await tester.pumpAndSettle();

    expect(tapped, greaterThan(8), reason: 'a row the reader can work down');
    expect(find.byType(SnackBar), findsNothing);
    expect(
      find.byType(CircularProgressIndicator),
      findsNothing,
      reason: 'a word with no audio answers at once, or not at all',
    );
  });

  testWidgets('the rule under a word answers to the recitation, so a phone '
      'holding one aya of the set shows the rest as though nothing in them '
      'could be opened', (tester) async {
    // The first aya arrived before the radio went off; the rest of the set
    // never did.
    final downloaded = (await tracksFor(db, [96001])).single;
    // Writing the file is real disk work, which only completes outside the
    // fake clock a widget test runs on.
    final dir = (await tester.runAsync(() async {
      final dir = await tempAudioDir();
      await AudioCache(
        dir,
        fetch: FakeCdn().call,
      ).prefetch([downloaded.relPath]);
      return dir;
    }))!;
    await pumpPhone(
      tester,
      await wirdAround(
        db,
        StudyScreen(db: db),
        route: Routes.study,
        cache: AudioCache(dir, fetch: RadioOff().call),
      ),
    );

    // Whether a word can be heard is a fact about its aya's file, the same
    // for every word on the line, and the transport says it once for the set.
    // The rule under the Arabic says the other thing — that a tap opens a
    // root — and it has to say it on an aya the radio never reached.
    final set = (await nextSet(db, ReadingOrder.nuzul))!;
    final undownloaded = [
      for (final aya in set.ayas)
        if (aya.id != 96001)
          for (final word in aya.words)
            if (drawn(word.id)) word,
    ];
    expect(
      undownloaded.where((word) => word.root != null),
      hasLength(greaterThan(2)),
    );
    for (final word in undownloaded) {
      expect(
        underlineOf(tester, word.id) == Colors.transparent,
        word.root == null,
        reason:
            'no recitation for ${word.id}, and the rule is not the '
            'recitation\'s to spend',
      );
    }
  });

  testWidgets('a two-line gloss pushes its Arabic out of line', (tester) async {
    await openStudy(tester);
    final aya = (await nextSet(db, ReadingOrder.nuzul))!.ayas[1];
    final ids = [for (final word in aya.words) word.id];

    final tops = {for (final id in ids) tester.getRect(arabic(id)).top};
    final rules = {
      for (final id in ids)
        tester
            .getRect(
              find
                  .ancestor(of: arabic(id), matching: find.byType(Container))
                  .first,
            )
            .bottom,
    };
    final tiles = {for (final id in ids) tester.getRect(tile(id)).height};

    expect(
      tiles,
      hasLength(greaterThan(1)),
      reason: 'a gloss in this aya wraps, or the row cannot break',
    );
    expect(tops, hasLength(1), reason: 'the Arabic of every word is level');
    expect(rules, hasLength(1), reason: 'the underlines still read as a line');
  });

  testWidgets('the aya mark floats off the baseline', (tester) async {
    await openStudy(tester);
    // The mark closes its aya. Al-ʿAlaq 1 fills its row on a phone, so the
    // mark wraps onto a row of its own, and the baseline it has to ride is
    // the one a word would have there: as far below the row's top as the
    // last word's baseline is below the top of its own row.
    final last = arabic(96001005);
    final painted = tester.widget<Text>(last);
    final baseline = TextPainter(
      text: TextSpan(text: painted.data, style: painted.style),
      textDirection: TextDirection.rtl,
    )..layout();
    final drop =
        tester.getRect(last).top -
        tester.getRect(tile(96001005)).top +
        baseline.computeDistanceToActualBaseline(TextBaseline.alphabetic);

    expect(
      tester.getCenter(find.text('١')).dy,
      closeTo(tester.getRect(mark(96001)).top + drop, 4),
      reason: 'the mark rides the Arabic baseline, not the top of the row',
    );
  });

  testWidgets('a recitation that cannot be fetched leaves the bar lit over '
      'silence', (tester) async {
    await openStudy(tester);
    // The play button sits in the reader's own bar, so nothing is scrolled
    // to reach it. Nothing is on the phone, and it still offers to play:
    // online, the player fetches the sūra as it recites.
    final play = find.ancestor(
      of: find.byIcon(Icons.play_arrow),
      matching: find.byType(IconButton),
    );
    expect(tester.widget<IconButton>(play).onPressed, isNotNull);

    await tester.tap(play);
    await settlePlayer(tester);
    expect(find.byIcon(Icons.pause), findsNothing);
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
  });

  testWidgets('the dark play button offers a download of a recitation the '
      'corpus does not carry', (tester) async {
    // A corpus with no ayah_audio rows: nothing to fetch, ever, and the
    // button says so rather than offering to play.
    await db.delete('ayah_audio');
    await openStudy(tester);

    expect(find.byTooltip('No recitation for this sūra'), findsOneWidget);
  });

  testWidgets('the word panel names the root and keeps its sense to itself, so '
      'the one screen the reader studies from is the one screen that will not '
      'say what the root means', (tester) async {
    // Seeded: the bundle carries no senses since ADR 0010, and قرأ is the root
    // the panel opens on for this set's first rooted word.
    await seedSenses(db, {'قرأ': 'a recitation, the quran; to recite'});
    await openStudy(tester);
    final panel = find.byType(RootSheet);

    expect(
      find.descendant(of: panel, matching: find.text('SENSES')),
      findsOneWidget,
    );
    for (final sense in ['a recitation, the quran', 'to recite']) {
      expect(
        find.descendant(of: panel, matching: find.text(sense)),
        findsOneWidget,
      );
    }
    // What the word means in this aya answers a different question, and
    // stays on the word's own row.
    expect(
      find.descendant(
        of: panel,
        matching: find.byKey(const Key('meaning here')),
      ),
      findsOneWidget,
    );

    // ربب was not in the pack. ADR 0014 draws no section it has no data for,
    // so the heading goes with the sense rather than standing over nothing.
    await tester.tap(tile(96001003));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: panel, matching: find.text('SENSES')),
      findsNothing,
    );
  });

  // The failure: the reading screen draws the sense and no way to say it is
  // wrong, so the one signal ADR 0010 corrects senses by stops arriving from
  // the screen where senses are read.
  testWidgets('a reader who finds the sense wrong on the reading screen has no '
      'way to say so', (tester) async {
    await seedSenses(db, {'قرأ': 'a recitation, the quran; to recite'});
    await openStudy(tester);

    await tester.tap(find.bySemanticsLabel('This sense is wrong'));
    await tester.pumpAndSettle();

    final queued = await db.query('outbox', where: "kind = 'report_written'");
    expect(queued, hasLength(1));
    expect(queued.single['body'] as String, contains('قرأ'));
  });

  // The failure: the key that finds the open word for centring moved from
  // tile to tile, so every tap re-created a tile and the aya flashed.
  testWidgets('a tap on a word rebuilds the aya under it from scratch', (
    tester,
  ) async {
    await openStudy(tester);
    final before = tester.element(tile(96002001));

    await tester.tap(tile(96002001));
    await tester.pumpAndSettle();

    expect(tester.element(tile(96002001)), same(before));
  });

  // The failure: the root sheet's ring is the only family left on the
  // reading screen, and the deep dive with the whole family is out of reach.
  testWidgets('the deep dive cannot be reached from the reading screen', (
    tester,
  ) async {
    await openStudy(tester);
    await tester.tap(find.byKey(const Key('more row')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('deep dive')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('deep dive')));
    await tester.pumpAndSettle();

    expect(find.byType(DeepDiveScreen), findsOneWidget);
  });

  /// The sheet's own scroll, under the sūra.
  Finder sheetScroll() => find.descendant(
    of: find.byType(RootSheet),
    matching: find.byType(SingleChildScrollView),
  );

  testWidgets('scrolling the sheet expands it on its own', (tester) async {
    await openStudy(tester);

    await tester.drag(sheetScroll(), const Offset(0, -200));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('open aya')), findsNothing);
  });

  testWidgets("a tap on the sheet's top bar does nothing", (tester) async {
    await openStudy(tester);

    await tester.tap(find.byKey(const Key('sheet handle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('open aya')), findsOneWidget);

    await tester.tap(find.byKey(const Key('sheet handle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('open aya')), findsNothing);
  });

  testWidgets('the thumbs are not on the senses row, and the form is read '
      'before the senses', (tester) async {
    await seedSenses(db, {'قرأ': 'a recitation, the quran; to recite'});
    await openStudy(tester);

    final senses = tester.getCenter(find.text('SENSES')).dy;
    final thumb = tester
        .getCenter(find.bySemanticsLabel('This sense is right'))
        .dy;
    expect((thumb - senses).abs(), lessThan(16));
    expect(
      tester.getTopLeft(find.byKey(const Key('form'))).dy,
      greaterThan(tester.getTopLeft(find.text('to recite')).dy),
    );
  });

  testWidgets("the other ayas show a root's aya with none of its root's words "
      'lit', (tester) async {
    await openStudy(tester);
    await tester.tap(find.byKey(const Key('more row')));
    await tester.pumpAndSettle();
    final row = find
        .byWidgetPredicate(
          (w) =>
              w.key is ValueKey<String> &&
              (w.key! as ValueKey<String>).value.startsWith('other aya '),
        )
        .first;
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();

    var lit = 0;
    for (final text in tester.widgetList<RichText>(
      find.descendant(of: row, matching: find.byType(RichText)),
    )) {
      text.text.visitChildren((span) {
        if (span is TextSpan && (span.style?.shadows?.isNotEmpty ?? false)) {
          lit++;
        }
        return true;
      });
    }
    expect(lit, greaterThan(0));
  });

  /// The sūra list, as the scrollable the words sit in.
  Finder suraList() => find
      .ancestor(of: tile(96001001), matching: find.byType(Scrollable))
      .first;

  testWidgets('a tapped word is left wherever it sat, off the middle of the '
      'list', (tester) async {
    await openStudy(tester);
    // Any word's list, since the first word is unbuilt once scrolled away.
    final list = find
        .ancestor(
          of: find.byWidgetPredicate((w) => w.key is WordKey),
          matching: find.byType(Scrollable),
        )
        .first;
    final word = tile(96005001);
    await tester.dragUntilVisible(word, list, const Offset(0, -40));
    await tester.pumpAndSettle();

    await tester.tap(word);
    await tester.pumpAndSettle();

    final seen = tester.getRect(list);
    expect(
      (tester.getCenter(word).dy - seen.center.dy).abs(),
      lessThan(seen.height / 4),
    );
  });

  testWidgets('a step to a word the reader can see moves the sūra out from '
      'under their thumb', (tester) async {
    await openStudy(tester);
    await tester.tap(tile(96002001));
    await tester.pumpAndSettle();
    // Off the middle, but in view: a step that centred would move it back.
    await tester.drag(suraList(), const Offset(0, 40));
    await tester.pumpAndSettle();
    final position = tester.state<ScrollableState>(suraList()).position;
    final at = position.pixels;

    await tester.tap(find.byKey(const Key('next word')));
    await tester.pumpAndSettle();

    expect(position.pixels, at);
  });

  testWidgets('a root opened under the words cannot be looked up in the '
      'dictionaries, or the way to them strays from the thumbs on the senses\' '
      'row', (tester) async {
    await seedSenses(db, {'قرأ': 'a recitation, the quran; to recite'});
    await openStudy(tester);

    final book = tester.getRect(find.byType(RootLookUp));
    final thumbs = tester.getRect(find.byType(JudgeSense));
    expect(book.center.dy, moreOrLessEquals(thumbs.center.dy, epsilon: 1));
    expect(book.right, moreOrLessEquals(thumbs.left, epsilon: 1));
  });

  testWidgets('a root with no sense written cannot be looked up from the '
      'reading screen, where it needs the dictionaries most', (tester) async {
    await openStudy(tester);

    expect(find.byType(JudgeSense), findsNothing);
    expect(find.text('Source'), findsOneWidget);
  });

  testWidgets('a step that walks the open word out of view leaves it out of '
      'sight', (tester) async {
    await openStudy(tester);
    final seen = tester.getRect(suraList());
    // Just out of view, not out of the list: a word scrolled far enough away
    // is not built at all, and centring reaches only built words.
    while (tester.getRect(tile(96001002)).bottom >= seen.top) {
      await tester.drag(suraList(), const Offset(0, -40));
      await tester.pumpAndSettle();
    }

    await tester.tap(find.byKey(const Key('next word')));
    await tester.pumpAndSettle();

    final open = tester.getRect(tile(96001002));
    expect(open.top, greaterThanOrEqualTo(seen.top));
    expect(open.bottom, lessThanOrEqualTo(seen.bottom));
  });

  // Nothing in app/lib sets a preferred orientation and the manifest handles
  // the configuration change itself, so the app rotates; the system text size
  // is the reader's and goes to 2x. The bar, the sūra and the sheet share the
  // window, and at every one of these shapes something has to give: a bar row
  // that runs off the right, or a sheet whose arrows fall off the bottom, or a
  // sūra squeezed to nothing.
  //
  // 874x402 is the same phone sideways, 320x568 the smallest phone still sold,
  // and 2.0 the top of the system text slider.
  for (final window in const [Size(402, 874), Size(320, 568), Size(874, 402)]) {
    for (final scale in const [1.0, 2.0]) {
      testWidgets('the reader cannot walk the sūra at ${window.width.toInt()}x'
          '${window.height.toInt()} at ${scale}x text: the arrows or the prayer '
          'are off the screen, or the reading is gone from it', (tester) async {
        tester.view.physicalSize = window;
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        unmountAtTearDown(tester);
        await tester.pumpWidget(
          await wirdAround(
            db,
            StudyScreen(db: db),
            route: Routes.study,
            cache: audio,
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull, reason: 'nothing overflows');

        // The arrows are the walk for a reader who cannot drag, and Pray is
        // the act the reading is for.
        for (final control in [
          find.byKey(const Key('next word')),
          find.byKey(const Key('previous word')),
          find.byKey(const Key('pray')),
        ]) {
          final rect = tester.getRect(control);
          expect(
            window.contains(rect.topLeft) && window.contains(rect.bottomRight),
            isTrue,
            reason: '$control is inside the window, at $rect',
          );
        }

        // What the sheet takes is the reading's height, so the reading
        // needs a floor. 75px is one aya tile at the default text size.
        final reading = tester.getRect(find.byType(CustomScrollView));
        expect(reading.height, greaterThanOrEqualTo(75));
        expect(
          reading.overlaps(tester.getRect(tile(96001001))),
          isTrue,
          reason: 'the open word is in the part of the sūra on screen',
        );
      });
    }
  }

  testWidgets('the microphone is asked for on the way into the prayer, where '
      'no dialog may appear', (tester) async {
    RecordPlatform.instance = FakeMic();
    await openStudy(tester);
    expect(
      await micPermission(db),
      MicPermission.notAsked,
      reason: 'opening the set asks for nothing',
    );

    await openSettings(tester);
    await tester.ensureVisible(find.text('Allow microphone'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Allow microphone'));
    await tester.pumpAndSettle();

    expect(await micPermission(db), MicPermission.granted);
    // Allowing the microphone is not turning voice-follow on: the recogniser
    // is a separate, printed, opt-in download.
    expect(find.textContaining('Download recogniser'), findsOneWidget);
  });

  testWidgets('the second aya the reader marks is thrown away, because it is '
      'queued under the op id the first one already used', (tester) async {
    await openStudy(tester);

    for (final aya in [96001, 96002]) {
      await tester.ensureVisible(mark(aya));
      await tester.pumpAndSettle();
      // The number, not the box: the box carries the margin that lets the
      // circle down onto the baseline, and a margin takes no tap.
      await tester.tap(
        find.descendant(of: mark(aya), matching: find.byType(Text)),
      );
      await tester.pumpAndSettle();
    }

    expect(
      (await db.query('ayah_understood')).map((r) => r['ayah_id']),
      unorderedEquals([96001, 96002]),
    );
    final ops = await db.query(
      'outbox',
      where: 'kind = ?',
      whereArgs: ['ayah_understood'],
    );
    expect(ops.map((op) => op['client_op_id']).toSet(), hasLength(2));
  });

  // Settings opens over the set, so the order or width changed there must
  // reach the prayer without the reader leaving the screen first.
  testWidgets('the order and width changed in settings over the set are '
      'ignored, and the prayer records the set worked out before', (
    tester,
  ) async {
    await openStudy(tester);

    await openSettings(tester);
    await tester.ensureVisible(find.byIcon(Icons.add));
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Muṣḥaf'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Muṣḥaf'));
    await tester.pumpAndSettle();
    await closeSettings(tester);

    final width = await readingWidth(db, ReadingOrder.mushaf);
    final set = (await ayaSet(db, ReadingOrder.mushaf, 96001, ayas: width))!;
    await tester.tap(find.byKey(const Key('pray')));
    await tester.pumpAndSettle();

    final prepared = tester.widget<PrepareScreen>(find.byType(PrepareScreen));
    expect(prepared.from!.order, ReadingOrder.mushaf);
    expect(prepared.from!.id, set.id);
  });

  testWidgets('the prayer is lost when the reader leaves the prayer screen by '
      'the back gesture instead of its Exit button', (tester) async {
    await openStudy(tester);
    // The prayer takes the ayas around the open word, the reading width wide.
    final set = (await ayaSet(
      db,
      ReadingOrder.nuzul,
      96001,
      ayas: await readingWidth(db, ReadingOrder.nuzul),
    ))!;

    await tester.tap(find.byKey(const Key('pray')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('begin')));
    await tester.pumpAndSettle();
    expect(find.text('Exit'), findsOneWidget);

    // Not the Exit button: the gesture 1b cannot hear and must not have to.
    Navigator.of(tester.element(find.text('Exit'))).pop();
    await tester.pumpAndSettle();

    final prayers = await db.query('set_prayers');
    expect(prayers.single['set_id'], set.id);
    final op = (await db.query(
      'outbox',
      where: 'kind = ?',
      whereArgs: ['set_prayed'],
    )).single;
    expect(jsonDecode(op['body']! as String), {
      'id': op['client_op_id'],
      'set_id': set.id,
      'start_ayah_id': 96001,
      'end_ayah_id': 96005,
      'reading_order': 'nuzul',
      'prayed_at': anything,
    });
  });

  testWidgets('the set draws a bookmark that keeps nothing, and the kept list '
      'sends the reader to it', (tester) async {
    await openStudy(tester);

    expect(find.byIcon(Icons.bookmark_border), findsNothing);
  });
}
