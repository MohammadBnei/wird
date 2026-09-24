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

  /// What a step prints on its face: the aya it lands on, and its sūra too
  /// when the step leaves the one being read.
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

  testWidgets('the aya after the set can only be reached by marking the set '
      'understood first', (tester) async {
    await openStudy(tester);
    expect(find.textContaining("Al-'Alaq 1–5"), findsOneWidget);

    await step(tester, 'next aya');

    expect(find.textContaining("Al-'Alaq 6"), findsOneWidget);
    expect(await db.query('ayah_understood'), isEmpty);
  });

  testWidgets('the aya before the one the reader is visiting is out of reach, '
      'so a sūra can only be read forwards', (tester) async {
    await openStudy(tester, target: 2255);

    await step(tester, 'previous aya');

    expect(find.textContaining('Al-Baqarah 254'), findsOneWidget);
  });

  testWidgets('a sūra opens at its first aya, where the step up is dark, so '
      'the first press a reader makes on the footer does nothing', (
    tester,
  ) async {
    await openStudy(tester, target: 2001);

    await step(tester, 'previous aya');

    expect(find.textContaining('Al-Fatihah 7'), findsOneWidget);
  });

  testWidgets('the reading stops dead at the foot of a sūra, so 96:19 offers '
      'no way on into the sūra after it', (tester) async {
    await openStudy(tester, target: 96019);

    await step(tester, 'next aya');

    expect(find.textContaining('Al-Qadr 1'), findsOneWidget);
  });

  testWidgets('a step out of the sūra prints only the aya number, so 2:1 '
      'offers "7" and lands the reader somewhere else entirely', (
    tester,
  ) async {
    await openStudy(tester, target: 2001);

    expect(stepSays(tester, 'previous aya'), '1:7');
    expect(stepSays(tester, 'next aya'), '2');
  });

  testWidgets('the first aya of the Qur’an offers a step above it, onto an '
      'aya the corpus cannot serve', (tester) async {
    await openStudy(tester, target: 1001);

    expect(stepSays(tester, 'previous aya'), isNull);
    await step(tester, 'previous aya');

    expect(find.textContaining('Al-Fatihah 1'), findsOneWidget);
  });

  testWidgets('the last aya of the Qur’an offers a step below it, onto an '
      'aya the corpus cannot serve', (tester) async {
    await openStudy(tester, target: 114006);

    expect(stepSays(tester, 'next aya'), isNull);
    await step(tester, 'next aya');

    expect(find.textContaining('An-Nas 6'), findsOneWidget);
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
