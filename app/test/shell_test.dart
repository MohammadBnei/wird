import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wird/app.dart';
import 'package:wird/data/audio.dart';
import 'package:wird/data/db.dart';
import 'package:wird/data/sets.dart';
import 'package:wird/features/dashboard/dashboard_screen.dart';
import 'package:wird/features/index/index_screen.dart';
import 'package:wird/features/progress/progress_screen.dart';
import 'package:wird/features/settings/settings_screen.dart';
import 'package:wird/nav.dart';
import 'package:wird/features/study/study_screen.dart';
import 'package:wird/shell/wird_shell.dart';

import 'corpus.dart';
import 'fonts.dart';
import 'offline.dart';
import 'player.dart';
import 'wird.dart';

/// Al-ʿAlaq 1–5: the first set a new reader is handed.
const firstSet = [96001, 96002, 96003, 96004, 96005];

void main() {
  late Database db;
  late FakePlayers players;

  /// The recitation of the first set, already downloaded and unable to fetch
  /// any more. Built here rather than in a test body: making the directory and
  /// writing the files is real file work, which never completes inside the
  /// fake-async zone a widget test body runs in.
  late Recitation downloaded;

  /// A phone that has never been online, for the tests that are not about
  /// audio at all. Built in setUp for the same reason.
  late AudioCache silent;

  setUpAll(loadBundledFonts);
  setUp(() async {
    db = await testCorpus();
    players = FakePlayers();
    JustAudioPlatform.instance = players;
    final dir = await tempAudioDir();
    final tracks = await tracksFor(db, firstSet);
    await AudioCache(
      dir,
      fetch: FakeCdn().call,
    ).prefetch([for (final t in tracks) t.relPath]);
    downloaded = Recitation(cache: AudioCache(dir, fetch: RadioOff().call));
    silent = await emptyCache();
  });

  Future<void> openTheSet(WidgetTester tester, Recitation recitation) async {
    await pumpPhone(tester, await wholeApp(db, recitation: recitation));
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(WirdDrawer),
        matching: find.text('The set'),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Frames, not a settle: while the set is being recited the player samples
  /// its own position every 40 ms, and a widget test that waits for the tree
  /// to go quiet waits forever.
  Future<void> beats(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump(const Duration(milliseconds: 60));
  }

  testWidgets('a word sounding and the whole set sounding look the same, so '
      'the reader cannot tell which one they started', (tester) async {
    final recitation = downloaded;
    await openTheSet(tester, recitation);

    unawaitedToggle(recitation);
    await beats(tester);
    expect(find.text('RECITING THE SET'), findsOneWidget);
    expect(find.textContaining("Al-'Alaq 1"), findsWidgets);

    await recitation.stop();
    await beats(tester);
    expect(find.text('RECITING THE SET'), findsNothing);

    final word =
        (await db.query(
              'words',
              where: 'id = ?',
              whereArgs: [96001001],
            )).single['text_ar']!
            as String;
    unawaitedWord(recitation, 96001001);
    await beats(tester);
    expect(find.text('SOUNDING ONE WORD'), findsOneWidget);
    expect(
      find.descendant(of: find.byType(SoundingNow), matching: find.text(word)),
      findsOneWidget,
    );
  });

  testWidgets('the only way to silence a recitation is a bare glyph, drawn as '
      'a 12px mark with nothing around it to read as a control', (
    tester,
  ) async {
    final recitation = downloaded;
    await openTheSet(tester, recitation);
    unawaitedToggle(recitation);
    await beats(tester);

    final stop = find.byKey(const Key('stop sounding'));
    expect(
      find.descendant(of: stop, matching: find.text('Stop')),
      findsOneWidget,
    );
    // A box the width of a word, not of a glyph.
    expect(tester.getSize(stop).width, greaterThan(40));
  });

  testWidgets('the sounding word is drawn at the size the set label uses, '
      'where a fully vowelled Arabic word is a smudge', (tester) async {
    final recitation = downloaded;
    await openTheSet(tester, recitation);
    final word =
        (await db.query(
              'words',
              where: 'id = ?',
              whereArgs: [96001001],
            )).single['text_ar']!
            as String;
    unawaitedWord(recitation, 96001001);
    await beats(tester);

    final drawn = tester.widget<Text>(
      find.descendant(of: find.byType(SoundingNow), matching: find.text(word)),
    );
    expect(drawn.style!.fontSize, greaterThanOrEqualTo(20));
  });

  testWidgets('a word plays to its end wherever the reader goes, because the '
      'only way to stop it is on the screen that started it', (tester) async {
    final recitation = downloaded;
    await openTheSet(tester, recitation);
    unawaitedWord(recitation, 96001001);
    await tester.pumpAndSettle();

    await goTo(tester, 'Sūra index');
    expect(find.byType(IndexScreen), findsOneWidget);
    expect(
      find.text('SOUNDING ONE WORD'),
      findsOneWidget,
      reason: 'the reader walked away and the word is still sounding',
    );

    await tester.tap(find.byKey(const Key('stop sounding')));
    await tester.pumpAndSettle();

    expect(
      find.text('SOUNDING ONE WORD'),
      findsNothing,
      reason: 'the reader pressed stop and the word is still named as playing',
    );
  });

  testWidgets('the sign that a recitation is running scrolls away with the '
      'words, so a reader who has scrolled sees nothing', (tester) async {
    final recitation = downloaded;
    await openTheSet(tester, recitation);
    unawaitedToggle(recitation);
    await beats(tester);

    await tester.drag(find.byType(StudyScreen), const Offset(0, -400));
    await beats(tester);

    expect(find.text('RECITING THE SET'), findsOneWidget);
    expect(find.byKey(const Key('stop sounding')), findsOneWidget);
  });

  testWidgets('the app opens on the set, with nothing saying which portion is '
      'waiting or whether it has been prayed', (tester) async {
    await pumpPhone(tester, await wholeApp(db, cache: silent));

    expect(find.byType(DashboardScreen), findsOneWidget);
    final waiting = await whatIsWaiting(db, ReadingOrder.nuzul);
    expect(find.text(waiting.set!.title), findsOneWidget);
    expect(find.text('SET ${waiting.number} · WAITING'), findsOneWidget);
    expect(find.textContaining('no prayer on it yet'), findsOneWidget);
  });

  testWidgets('home prints a set number and a prayer count that no query '
      'behind it produced', (tester) async {
    await markSetUnderstood(db, newOpId(), firstSet);
    final second = (await nextSet(db, ReadingOrder.nuzul))!;
    await recordSetPrayed(db, second);
    await recordSetPrayed(db, second);

    await pumpPhone(tester, await wholeApp(db, cache: silent));

    expect(find.text(second.title), findsOneWidget);
    expect(
      find.text('SET 2 · WAITING'),
      findsOneWidget,
      reason: 'one set understood, so the set waiting is the second',
    );
    expect(find.textContaining('prayed twice'), findsOneWidget);
  });

  testWidgets('the reader who changes the Arabic size finds it back where it '
      'was the next time they open the set', (tester) async {
    await pumpPhone(tester, await wholeApp(db, cache: silent));
    await goTo(tester, 'Settings');
    await tester.drag(find.byType(Slider), const Offset(-200, 0));
    await tester.pumpAndSettle();
    final chosen = (await displayPrefs(db)).arabicSize;
    expect(chosen, isNot(defaultArabicSize));

    // A fresh launch over the same database: the size is the reader's, not
    // the screen's, so it has to survive the screen being gone.
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpPhone(tester, await wholeApp(db, cache: silent));
    await goTo(tester, 'The set');

    final arabic = tester.widget<Text>(
      find
          .descendant(
            of: find.byKey(const ValueKey(96001001)),
            matching: find.byType(Text),
          )
          .first,
    );
    expect(arabic.style!.fontSize, chosen);
  });

  testWidgets('settings still mixes the preferences with the way out of the '
      'screen and the way into a prayer', (tester) async {
    await pumpPhone(tester, await wholeApp(db, cache: silent));
    await goTo(tester, 'Settings');
    expect(find.byType(SettingsScreen), findsOneWidget);

    for (final elsewhere in const [
      'Pray this set',
      'Your passage',
      'Kept',
      'Sūra index',
      'Sources and licences',
    ]) {
      expect(
        find.text(elsewhere),
        findsNothing,
        reason: '"$elsewhere" is not a preference',
      );
    }
    expect(find.text('Allow microphone'), findsOneWidget);
    expect(find.text('Gloss'), findsOneWidget);
  });

  testWidgets('a destination draws its own way back under the shell\'s burger, '
      'so the reader meets two navigation controls stacked in the corner', (
    tester,
  ) async {
    await pumpPhone(tester, await wholeApp(db, cache: silent));

    for (final destination in destinations) {
      await goTo(tester, destination.label);
      expect(
        find.byIcon(Icons.menu),
        findsOneWidget,
        reason: '${destination.label}: the drawer is how a destination is left',
      );
      for (final back in const [Icons.arrow_back_ios_new, Icons.arrow_back]) {
        expect(
          find.byIcon(back),
          findsNothing,
          reason: '${destination.label}: a second control in the same corner',
        );
      }
    }
  });

  testWidgets('the index opened from "All 114" offers the drawer rather than '
      'the way back to the passage the reader was reading', (tester) async {
    await pumpPhone(tester, await wholeApp(db, cache: silent));
    await goTo(tester, 'Your passage');
    await tester.tap(find.text('All 114'));
    await tester.pumpAndSettle();
    expect(find.byType(IndexScreen), findsOneWidget);

    expect(find.byIcon(Icons.menu), findsNothing);
    final back = find.byIcon(Icons.arrow_back_ios_new);
    expect(back, findsOneWidget);
    await tester.tap(back);
    await tester.pumpAndSettle();
    expect(
      find.byType(ProgressScreen),
      findsOneWidget,
      reason: 'the step back lands on the screen the step was taken from',
    );
  });

  testWidgets('the prayer is started from a preferences panel rather than '
      'from the screen the app opens on', (tester) async {
    await pumpPhone(tester, await wholeApp(db, cache: silent));

    final pray = find.byKey(const Key('pray the set'));
    expect(pray, findsOneWidget);
    await tester.tap(pray);
    await tester.pumpAndSettle();

    expect(find.text('Exit'), findsOneWidget);
  });
}

/// The recitation is started without waiting for it: `play()` answers when the
/// clip ends, and what these tests watch is the screen while it is still
/// running.
void unawaitedToggle(Recitation recitation) => recitation.toggle();

void unawaitedWord(Recitation recitation, int wordId) =>
    recitation.playWord(wordId);
