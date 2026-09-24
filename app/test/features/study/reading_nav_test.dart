import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wird/app.dart';
import 'package:wird/data/audio.dart';
import 'package:wird/features/index/index_screen.dart';
import 'package:wird/features/study/study_screen.dart';
import 'package:wird/nav.dart';
import 'package:wird/shell/wird_shell.dart';

import '../../corpus.dart';
import '../../fonts.dart';
import '../../offline.dart';
import '../../player.dart';
import '../../wird.dart';

/// The foot of screen 1a: what is sounding, and where the reader can go. A
/// reader who can read a whole sūra needs a way around it that is not
/// scrolling, and a way out of it that is not the drawer — and the hand that
/// does both is the hand that stops a recitation.
///
/// What the arrows move is the set — the ayas that go to the prayer — at the
/// width the reader takes at once. The width is the walk's, wherever they
/// stand, so it is one grain rather than one per way of arriving, and each
/// arrow prints the ayas it will hand over rather than leaving that to be
/// remembered.
void main() {
  late Database db;
  late AudioCache audio;

  /// The first set already on the phone, with nothing more fetchable. Built in
  /// setUp because writing the files is real file work, which never completes
  /// inside the fake-async zone a widget test body runs in.
  late Recitation downloaded;

  setUpAll(loadBundledFonts);
  setUp(() async {
    db = await testCorpus();
    audio = await emptyCache();
    JustAudioPlatform.instance = FakePlayers();
    final dir = await tempAudioDir();
    final tracks = await tracksFor(db, [96001, 96002, 96003, 96004, 96005]);
    await AudioCache(
      dir,
      fetch: FakeCdn().call,
    ).prefetch([for (final t in tracks) t.relPath]);
    downloaded = Recitation(cache: AudioCache(dir, fetch: RadioOff().call));
  });

  Future<void> openStudy(
    WidgetTester tester, {
    int? target,
    Recitation? recitation,
  }) async => pumpPhone(
    tester,
    await wirdAround(
      db,
      StudyScreen(db: db, target: target),
      route: Routes.study,
      cache: audio,
      recitation: recitation,
    ),
  );

  Future<void> step(WidgetTester tester, String which) async {
    await tester.tap(find.byKey(Key(which)));
    await tester.pumpAndSettle();
  }

  /// What a step prints on its face: the ayas it hands over, and their sūra
  /// too when the step leaves the one being read.
  String? stepSays(WidgetTester tester, String which) {
    final label = find.descendant(
      of: find.byKey(Key(which)),
      matching: find.byType(Text),
    );
    return label.evaluate().isEmpty ? null : tester.widget<Text>(label).data;
  }

  /// Frames, not a settle: while the set is being recited the player samples
  /// its own position every 40 ms, and a test that waits for the tree to go
  /// quiet waits forever.
  Future<void> beats(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump(const Duration(milliseconds: 60));
  }

  testWidgets('the footer steps one aya while the screen is about a set, so a '
      'reader who takes five at once is moved by four less than that', (
    tester,
  ) async {
    await openStudy(tester);
    expect(find.textContaining("Al-'Alaq 1–5"), findsOneWidget);

    expect(stepSays(tester, 'next set'), '6–10');
    await step(tester, 'next set');

    expect(find.textContaining("Al-'Alaq 6–10"), findsOneWidget);
    expect(await db.query('ayah_understood'), isEmpty);
  });

  testWidgets('the set the footer offers is reached by pressing the arrow, '
      'not by marking the one on screen understood first', (tester) async {
    await openStudy(tester);

    await step(tester, 'next set');

    expect(await db.query('ayah_understood'), isEmpty);
  });

  testWidgets('a sūra read from the index is stepped through one aya at a '
      'time, forgetting how much the reader takes at once', (tester) async {
    await openStudy(tester, target: 2255);

    expect(stepSays(tester, 'next set'), '256–260');
    await step(tester, 'next set');

    expect(find.textContaining('Al-Baqarah 256–260'), findsOneWidget);
  });

  testWidgets('the set above the one being read is out of reach, so a sūra '
      'can only be read forwards', (tester) async {
    await openStudy(tester, target: 2255);

    expect(stepSays(tester, 'previous set'), '250–254');
    await step(tester, 'previous set');

    expect(find.textContaining('Al-Baqarah 250–254'), findsOneWidget);
  });

  testWidgets('a step up near the start of a sūra reaches back past its first '
      'aya, into a sūra the reader did not ask for', (tester) async {
    await openStudy(tester, target: 2003);

    expect(stepSays(tester, 'previous set'), '1–2');
  });

  testWidgets('a step down promises more ayas than the sūra it lands in has, '
      'so the reader is offered a set that runs off the end of the text', (
    tester,
  ) async {
    await openStudy(tester, target: 107007);

    expect(stepSays(tester, 'next set'), '108:1–3');
    await step(tester, 'next set');

    expect(find.textContaining('Al-Kawthar 1–3'), findsOneWidget);
  });

  testWidgets('a step into a short sūra shrinks the reader’s grain to what '
      'fitted there, so every step after it is narrower', (tester) async {
    await openStudy(tester, target: 107007);

    await step(tester, 'next set');

    expect(stepSays(tester, 'next set'), '109:1–5');
  });

  testWidgets('a sūra opens at its first aya, where the step up is dark, so '
      'the first press a reader makes on the footer does nothing', (
    tester,
  ) async {
    await openStudy(tester, target: 2001);

    await step(tester, 'previous set');

    expect(find.textContaining('Al-Fatihah 3–7'), findsOneWidget);
  });

  testWidgets('a step out of the sūra prints only the aya numbers, so 2:1 '
      'offers "3–7" and lands the reader somewhere else entirely', (
    tester,
  ) async {
    await openStudy(tester, target: 2001);

    expect(stepSays(tester, 'previous set'), '1:3–7');
    expect(stepSays(tester, 'next set'), '2–6');
  });

  testWidgets('the first aya of the Qur’an offers a step above it, onto ayas '
      'the corpus cannot serve', (tester) async {
    await openStudy(tester, target: 1001);

    expect(stepSays(tester, 'previous set'), isNull);
    await step(tester, 'previous set');

    expect(find.textContaining('Al-Fatihah 1'), findsOneWidget);
  });

  testWidgets('the last aya of the Qur’an offers a step below it, onto ayas '
      'the corpus cannot serve', (tester) async {
    await openStudy(tester, target: 114006);

    expect(stepSays(tester, 'next set'), isNull);
    await step(tester, 'next set');

    expect(find.textContaining('An-Nas 6'), findsOneWidget);
  });

  testWidgets('the middle of the footer names what the index answers with '
      'rather than the move it makes, so the reader asks what it is', (
    tester,
  ) async {
    await openStudy(tester);

    expect(find.text('Go to…'), findsOneWidget);
    expect(find.textContaining('Sūra or aya'), findsNothing);
  });

  testWidgets('the footer cannot reach the sūra index, so changing sūra means '
      'leaving the reading by the drawer', (tester) async {
    await openStudy(tester);

    await tester.tap(find.byKey(const Key('open the index')));
    await tester.pumpAndSettle();

    expect(find.byType(IndexScreen), findsOneWidget);
    expect(
      find.byIcon(Icons.menu),
      findsNothing,
      reason: 'the index opened from the reading is a step, not a destination',
    );
  });

  testWidgets('the aya picked in the index leaves the reader on the index, or '
      'on a second reader stacked over the first', (tester) async {
    await openStudy(tester);

    await tester.tap(find.byKey(const Key('open the index')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sura-1')));
    await tester.pumpAndSettle();

    expect(find.byType(IndexScreen), findsNothing);
    expect(find.byType(StudyScreen), findsOneWidget);
    expect(find.textContaining('Al-Fatihah 1'), findsOneWidget);
  });

  testWidgets('a sūra chosen from the index opens on a set of five, marking '
      'and praying four ayas the reader only asked to read', (tester) async {
    await openStudy(tester);

    await tester.tap(find.byKey(const Key('open the index')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sura-1')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Al-Fatihah 1–'), findsNothing);
  });

  testWidgets('the transport is a screen away from the controls the reader is '
      'already holding, so stopping a recitation is a second reach', (
    tester,
  ) async {
    await openStudy(tester, recitation: downloaded);
    downloaded.toggle();
    await beats(tester);

    expect(find.text('RECITING THE SET'), findsOneWidget);
    expect(
      tester.getRect(find.byType(SoundingNow)).top,
      greaterThan(tester.getRect(find.byType(CustomScrollView)).center.dy),
      reason: 'the transport is drawn above the set rather than under it',
    );
  });

  testWidgets('the footer jumps under the reader’s thumb when a '
      'recitation starts', (tester) async {
    await openStudy(tester, recitation: downloaded);
    final before = tester.getRect(find.byKey(const Key('open the index'))).top;

    downloaded.toggle();
    await beats(tester);

    expect(find.text('RECITING THE SET'), findsOneWidget);
    expect(
      tester.getRect(find.byKey(const Key('open the index'))).top,
      moreOrLessEquals(before),
      reason: 'the reading gives up the height, not the row under the thumb',
    );
  });
}
