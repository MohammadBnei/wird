import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wird/app.dart';
import 'package:wird/data/audio.dart';
import 'package:wird/features/study/study_screen.dart';
import 'package:wird/nav.dart';
import 'package:wird/shell/wird_shell.dart';

import '../../corpus.dart';
import '../../fonts.dart';
import '../../offline.dart';
import '../../player.dart';
import '../../wird.dart';

void main() {
  late Database db;
  late Directory dir;
  late FakeCdn cdn;
  late FakePlayers players;

  setUpAll(loadBundledFonts);
  setUp(() async {
    db = await testCorpus();
    dir = await tempAudioDir();
    cdn = FakeCdn();
  });
  tearDown(() => db.delete('audio_pref'));

  /// The reading screen's play button, whichever face it is showing.
  Finder playButton() => find.byWidgetPredicate(
    (w) =>
        w is IconButton &&
        w.key == null &&
        w.icon is Icon &&
        {Icons.play_arrow, Icons.pause}.contains((w.icon as Icon).icon),
  );

  IconData face(WidgetTester tester, Finder button) =>
      (tester.widget<IconButton>(button).icon as Icon).icon!;

  /// A press, and the player's platform calls it starts, which only finish
  /// outside the fake-async zone the test body runs in. The fake player's
  /// "ready" is a timer on the test's clock and the file work behind a load
  /// is real I/O, so both are let run in turns until the reading screen's
  /// button changes face — a fixed number of turns passed on a Mac and not on
  /// a slower CI runner.
  Future<void> press(WidgetTester tester, Finder button) async {
    IconData? faceNow() =>
        playButton().evaluate().isEmpty ? null : face(tester, playButton());
    final before = faceNow();
    await tester.tap(button);
    for (var i = 0; i < 100; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 10));
      if (i >= 4 && faceNow() != before) break;
    }
  }

  /// Runs real and fake time in turns until the reading screen's set is on
  /// the phone in [folder]'s voice. A fixed number of turns downloaded the
  /// set on a Mac and not on the slower CI runner, where the play button was
  /// still dark when the test pressed it.
  Future<void> untilReady(WidgetTester tester, String folder) async {
    for (var i = 0; i < 300; i++) {
      final recitation = Wird.of(tester.element(playButton())).recitation;
      // The button, not only the player: the screen redraws it when the
      // download it awaited lands, and a press before that is a dark button.
      final first = recitation.tracks.firstOrNull?.relPath ?? '';
      if (first.startsWith(folder) &&
          AudioCache(dir).cached(first) != null &&
          tester.widget<IconButton>(playButton()).onPressed != null) {
        return;
      }
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pumpAndSettle();
    }
    fail('the set never arrived in $folder');
  }

  Future<void> openStudy(WidgetTester tester) async {
    players = FakePlayers();
    JustAudioPlatform.instance = players;
    await pumpPhone(
      tester,
      await wirdAround(
        db,
        WirdShell(
          route: Routes.study,
          child: StudyScreen(db: db, target: 96001),
        ),
        route: Routes.study,
        cache: AudioCache(dir, fetch: cdn.call),
      ),
    );
    await untilReady(tester, 'Husary_Muallim_128kbps');
  }

  testWidgets('a reciter picked after pausing the set is never downloaded, so '
      'the play button keeps the old voice', (tester) async {
    await openStudy(tester);
    await press(tester, playButton());
    await press(tester, playButton());

    await Wird.of(tester.element(playButton())).prefs.setReciter('alafasy');
    await untilReady(tester, 'Alafasy_128kbps');

    expect(
      cdn.served,
      contains('${defaultAudioOrigin}Alafasy_128kbps/096001.mp3'),
    );
    await press(tester, playButton());
    expect(players.players.last.loaded.join(), contains('Alafasy_128kbps'));
    await press(tester, find.byKey(const Key('stop sounding')));
  });

  testWidgets('pausing the set stops it, and the next press starts it again '
      'from its first aya', (tester) async {
    await openStudy(tester);
    await press(tester, playButton());
    expect(face(tester, playButton()), Icons.pause);
    final loads = players.only.loaded.length;

    await press(tester, playButton());
    expect(face(tester, playButton()), Icons.play_arrow);
    expect(
      find.byKey(const Key('stop sounding')),
      findsOneWidget,
      reason: 'a paused set keeps its bar, to carry on or stop from anywhere',
    );

    await press(tester, find.byKey(const Key('pause sounding')));
    expect(face(tester, playButton()), Icons.pause);
    expect(
      players.only.loaded.length,
      loads,
      reason:
          'resuming carries on in the loaded set rather than loading it '
          'again from its start',
    );

    await press(tester, find.byKey(const Key('stop sounding')));
    expect(find.byKey(const Key('stop sounding')), findsNothing);
  });
}
