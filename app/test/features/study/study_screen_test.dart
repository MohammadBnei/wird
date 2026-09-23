import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wird/data/audio.dart';
import 'package:wird/data/db.dart';
import 'package:wird/data/sets.dart';
import 'package:wird/data/mic.dart';
import 'package:wird/features/settings/settings_screen.dart';
import 'package:wird/features/study/study_screen.dart';
import 'package:wird/nav.dart';
import 'package:wird/theme/nocturne.dart';
import 'package:wird/widgets/nocturne_button.dart';

import '../../corpus.dart';
import '../../fonts.dart';
import '../../offline.dart';
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
Finder tile(int wordId) => find.byKey(ValueKey(wordId));

/// The Arabic of a word: the first thing painted in its tile, above the
/// transliteration and the gloss.
Finder arabic(int wordId) =>
    find.descendant(of: tile(wordId), matching: find.byType(Text)).first;

Text arabicOf(WidgetTester tester, int wordId) =>
    tester.widget<Text>(arabic(wordId));

/// The line under a word's Arabic, which says the word can be heard.
Color underlineOf(WidgetTester tester, int wordId) {
  final box = tester.widget<Container>(
    find.ancestor(of: arabic(wordId), matching: find.byType(Container)).first,
  );
  return ((box.decoration! as BoxDecoration).border! as Border).bottom.color;
}

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
    await pumpPhone(
      tester,
      await wirdAround(
        db,
        StudyScreen(db: db),
        cache: audio,
        // Screen 1b stands in as a bare page: what is under test is that the
        // prayer is recorded when the reader gets back, whatever 1b did.
        onGenerateRoute: (settings) => MaterialPageRoute<void>(
          builder: (_) => settings.name == Routes.prayer
              ? const Scaffold(body: Text('praying'))
              : screens[settings.name]!(db, settings.arguments),
        ),
      ),
    );
  }

  /// The preferences, which are a screen of their own now rather than a panel
  /// that unfolds over the set.
  Future<void> openSettings(WidgetTester tester) async {
    Navigator.of(tester.element(find.byType(StudyScreen)))
        .pushNamed(Routes.settings);
    await tester.pumpAndSettle();
  }

  /// Back to the set, which is where a change to the display has to be seen.
  Future<void> closeSettings(WidgetTester tester) async {
    Navigator.of(tester.element(find.byType(SettingsScreen))).pop();
    await tester.pumpAndSettle();
  }

  /// Pulls the set's end out one aya at a time, the way the reader does.
  Future<void> widen(WidgetTester tester, int times) async {
    for (var i = 0; i < times; i++) {
      await tester.tap(find.byKey(const Key('widen set')));
      await tester.pumpAndSettle();
    }
  }

  testWidgets('a set that crosses a sūra boundary drops the ayas on the far '
      'side of it', (tester) async {
    await db.execute(
      "INSERT INTO ayah_understood SELECT id, '' FROM ayahs "
      'WHERE surah_id = 96 AND number < 19',
    );

    await openStudy(tester);

    expect(find.text(await word(db, 96019001)), findsOneWidget);
    expect(find.text(await word(db, 68001001)), findsOneWidget);
    expect(find.textContaining('Al-Qalam'), findsOneWidget);
  });

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

  testWidgets('holding a word blanks the aya while the root panel catches up',
      (tester) async {
    await openStudy(tester);
    expect(find.text('ق ر أ'), findsOneWidget);

    await tester.longPress(tile(96002004));
    await tester.pump();
    expect(
      tile(96002004),
      findsOneWidget,
      reason: 'the aya stays on screen while the new root is read',
    );

    await tester.pumpAndSettle();
    expect(find.text('ع ل ق'), findsOneWidget);
    expect(find.text('ق ر أ'), findsNothing);
  });

  testWidgets('holding a word that carries no root throws away the root the '
      'reader was reading', (tester) async {
    await openStudy(tester);

    await tester.longPress(tile(96001004));
    await tester.pumpAndSettle();

    expect(find.text('ق ر أ'), findsOneWidget);
  });

  testWidgets('the screen puts an aya the reader understood out of order back '
      'in front of them', (tester) async {
    await markSetUnderstood(db, newOpId(), [96002]);

    await openStudy(tester);

    expect(tile(96001001), findsOneWidget);
    expect(
      tile(96002004),
      findsNothing,
      reason: 'aya 2 is understood, so the set ends before it',
    );
    expect(find.text('No aya marked understood yet'), findsOneWidget);
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

  testWidgets('the Arabic size setting leaves the aya at the size it was',
      (tester) async {
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

  testWidgets('tapping a word opens a root panel instead of speaking it',
      (tester) async {
    await openStudy(tester);
    final rows = await db.query('words', where: 'id = 96002004');
    final translit = rows.single['translit']! as String;
    expect(find.text('ق ر أ'), findsOneWidget);

    await tester.tap(tile(96002004));
    await tester.pumpAndSettle();

    expect(
      find.descendant(of: tile(96002004), matching: find.text(translit)),
      findsOneWidget,
      reason: 'the tap asked for the word, and nothing is downloaded to play',
    );
    expect(
      find.text('ع ل ق'),
      findsNothing,
      reason: 'the root panel belongs to the long press now',
    );

    await tester.longPress(tile(96002004));
    await tester.pumpAndSettle();
    expect(find.text('ع ل ق'), findsOneWidget);
  });

  testWidgets('a tap on an aya that was never downloaded spins, or shouts one '
      'snackbar per word', (tester) async {
    await openStudy(tester);
    final set = (await nextSet(db, ReadingOrder.nuzul))!;
    final shown = tester.getRect(find.byType(SingleChildScrollView));
    var tapped = 0;

    for (final aya in set.ayas) {
      for (final word in aya.words) {
        // A tile scrolled out of the set's own pane would take the tap on
        // whatever is painted over it, which proves nothing about the word.
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

  testWidgets('a reader cannot tell which words can be heard', (tester) async {
    // The first aya arrived before the radio went off; the rest of the set
    // never did.
    final downloaded = (await tracksFor(db, [96001])).single;
    // Writing the file is real disk work, which only completes outside the
    // fake clock a widget test runs on.
    final dir = (await tester.runAsync(() async {
      final dir = await tempAudioDir();
      await AudioCache(dir, fetch: FakeCdn().call).prefetch([
        downloaded.relPath,
      ]);
      return dir;
    }))!;
    await pumpPhone(
      tester,
      await wirdAround(
        db,
        StudyScreen(db: db),
        cache: AudioCache(dir, fetch: RadioOff().call),
      ),
    );

    final heard = [for (final span in downloaded.segments) span.wordId];
    expect(heard, hasLength(greaterThan(2)));
    for (final id in heard) {
      expect(
        underlineOf(tester, id),
        isNot(Colors.transparent),
        reason: 'word $id is on the phone and the row says nothing',
      );
    }
    for (final span in (await tracksFor(db, [96002])).single.segments) {
      expect(
        underlineOf(tester, span.wordId),
        Colors.transparent,
        reason: 'word ${span.wordId} would play nothing if it were tapped',
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
              find.ancestor(
                of: arabic(id),
                matching: find.byType(Container),
              ).first,
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
    // The mark closes its aya, so the row it rides is the row the aya's last
    // word is on.
    final last = arabic(96001005);
    final painted = tester.widget<Text>(last);
    final baseline = TextPainter(
      text: TextSpan(text: painted.data, style: painted.style),
      textDirection: TextDirection.rtl,
    )..layout();

    expect(
      tester.getCenter(find.text('١')).dy,
      closeTo(
        tester.getRect(last).top +
            baseline.computeDistanceToActualBaseline(TextBaseline.alphabetic),
        4,
      ),
      reason: 'the mark rides the Arabic baseline, not the top of the row',
    );
  });

  testWidgets('the recitation offers to play a set that is not on the phone, '
      'and stalls on a file it cannot fetch', (tester) async {
    await openStudy(tester);

    expect(find.text('Not downloaded'), findsOneWidget);
    final play = tester.widget<NocturneButton>(
      find.ancestor(
        of: find.byIcon(Icons.play_arrow),
        matching: find.byType(NocturneButton),
      ),
    );
    expect(play.onPressed, isNull);
  });

  testWidgets('the reader is stuck in the order they started, with no way to '
      'read the muṣḥaf from its first sūra', (tester) async {
    await openStudy(tester);
    expect(find.textContaining("Al-'Alaq 1"), findsOneWidget);

    await openSettings(tester);
    await tester.tap(find.text('Muṣḥaf'));
    await tester.pumpAndSettle();
    // Reaching settings leaves the set behind — the drawer pops to home
    // first — so the order is seen on the set the reader opens next.
    await tester.pumpWidget(const SizedBox.shrink());
    await openStudy(tester);

    expect(find.textContaining('Al-Fatihah 1'), findsOneWidget);
    expect(await readingOrder(db), ReadingOrder.mushaf);
  });

  testWidgets('the microphone is asked for on the way into the prayer, where '
      'no dialog may appear', (tester) async {
    await openStudy(tester);
    expect(
      await micPermission(db),
      MicPermission.notAsked,
      reason: 'opening the set asks for nothing',
    );

    await openSettings(tester);
    await tester.tap(find.text('Allow microphone'));
    await tester.pumpAndSettle();

    expect(await micPermission(db), isNot(MicPermission.notAsked));
    expect(find.textContaining('advances on a tap'), findsOneWidget);
  });

  testWidgets('the reader is carried off the set the moment they mark it, '
      'before the marks they just made are on screen', (tester) async {
    await openStudy(tester);
    expect(find.textContaining("Al-'Alaq 1"), findsOneWidget);

    await tester.tap(find.text('Mark set understood'));
    await tester.pumpAndSettle();

    expect(find.textContaining("Al-'Alaq 1"), findsOneWidget);
    expect(find.text('Every aya in this set is understood'), findsOneWidget);
    expect((await db.query('outbox')).length, 1);
    expect((await db.query('ayah_understood')).length, 5);

    await tester.tap(find.text('Next set'));
    await tester.pumpAndSettle();
    expect(find.textContaining("Al-'Alaq 6"), findsOneWidget);
  });

  testWidgets('the set the reader pulled wider is five ayas again when they '
      'come back to screen 1a', (tester) async {
    await openStudy(tester);
    await openSettings(tester);
    expect(find.text('5 ayas'), findsOneWidget);

    await widen(tester, 3);

    // Away from 1a and back, which is where an in-memory width is lost.
    await tester.pumpWidget(const SizedBox.shrink());
    await openStudy(tester);

    expect(find.textContaining("Al-'Alaq 1–8"), findsOneWidget);
  });

  testWidgets('the second set the reader marks is thrown away, because it is '
      'queued under the op id the first one already used', (tester) async {
    await openStudy(tester);
    await openSettings(tester);
    await widen(tester, 3);
    await tester.pumpWidget(const SizedBox.shrink());
    await openStudy(tester);

    await tester.tap(find.text('Mark set understood'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next set'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mark set understood'));
    await tester.pumpAndSettle();

    expect(
      (await db.query('ayah_understood')).length,
      13,
      reason: 'eight ayas pulled wide, then the five of the set after them',
    );
    expect((await db.query('outbox')).length, 2);
  });

  testWidgets('a set pulled across an aya the reader already understood marks '
      'it a second time, moving the day they understood it', (tester) async {
    await markSetUnderstood(db, newOpId(), [96003]);
    final before = await db.query('ayah_understood');

    await openStudy(tester);
    await openSettings(tester);
    // The proposal stops before aya 3; the reader pulls the set across it.
    expect(find.text('2 ayas'), findsOneWidget);
    await widen(tester, 3);
    await tester.pumpWidget(const SizedBox.shrink());
    await openStudy(tester);
    expect(find.textContaining("Al-'Alaq 1–5"), findsOneWidget);

    await tester.tap(find.text('Mark set understood'));
    await tester.pumpAndSettle();

    final ops = await db.query('outbox', orderBy: 'created_at, client_op_id');
    expect(
      jsonDecode(ops.last['body']! as String)['ayah_ids'],
      [96001, 96002, 96004, 96005],
      reason: 'the aya the set was pulled across is recited, not re-marked',
    );
    expect(await db.query('ayah_understood', where: 'ayah_id = 96003'), before);
  });

  testWidgets('the prayer is lost when the reader leaves the prayer screen by '
      'the back gesture instead of its Exit button', (tester) async {
    await openStudy(tester);
    final set = (await nextSet(db, ReadingOrder.nuzul))!;

    await tester.tap(find.text('Pray this set'));
    await tester.pumpAndSettle();
    expect(find.text('praying'), findsOneWidget);

    // Not the Exit button: the gesture 1b cannot hear and must not have to.
    Navigator.of(tester.element(find.text('praying'))).pop();
    await tester.pumpAndSettle();

    final prayers = await db.query('set_prayers');
    expect(prayers.single['set_id'], set.id);
    final op = (await db.query('outbox')).single;
    expect(op['kind'], 'set_prayed');
    expect(jsonDecode(op['body']! as String), {
      'id': op['client_op_id'],
      'set_id': set.id,
      'start_ayah_id': 96001,
      'end_ayah_id': 96005,
      'reading_order': 'nuzul',
      'prayed_at': anything,
    });
  });
}
