import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wird/app.dart';
import 'package:wird/data/audio.dart';
import 'package:wird/features/settings/settings_screen.dart';

import '../../corpus.dart';
import '../../fonts.dart';
import '../../offline.dart';
import '../../player.dart';
import '../../wird.dart';

void main() {
  late Database db;
  late AudioCache audio;

  setUpAll(loadBundledFonts);
  setUp(() async {
    db = await testCorpus();
    final dir = await tempAudioDir();
    // Alafasy's basmala is already on the phone, so the sample plays with
    // the radio off.
    await AudioCache(
      dir,
      fetch: FakeCdn().call,
    ).fetchOne('Alafasy_128kbps/$sampleFile');
    audio = AudioCache(dir, fetch: RadioOff().call);
  });

  tearDown(() => db.delete('audio_pref'));

  testWidgets('a reciter is chosen by name alone, with no way to hear them '
      'first, and the sample keeps playing after the reader leaves', (
    tester,
  ) async {
    JustAudioPlatform.instance = FakePlayers();
    final recitation = Recitation(cache: audio);
    await pumpPhone(
      tester,
      await wirdAround(
        db,
        const SettingsScreen(),
        cache: audio,
        recitation: recitation,
      ),
    );
    final hear = find.byKey(const Key('sample alafasy'));
    await tester.scrollUntilVisible(hear, 200);
    await tester.tap(hear);
    await tester.pump();
    expect(recitation.sampling.value, 'alafasy');
    expect(
      find.descendant(of: hear, matching: find.byIcon(Icons.stop)),
      findsOneWidget,
    );
    expect(
      Wird.of(tester.element(hear)).prefs.reciter,
      defaultReciter,
      reason: 'hearing a reciter is not choosing them',
    );

    await tester.pumpWidget(const SizedBox());
    expect(recitation.sampling.value, isNull);
  });

  testWidgets('the two Husary recitations read as the same choice twice', (
    tester,
  ) async {
    await pumpPhone(
      tester,
      await wirdAround(db, const SettingsScreen(), cache: audio),
    );
    expect(
      find.text('Muʿallim · slow and clear, for learning'),
      findsOneWidget,
    );
    expect(find.text('Murattal'), findsNWidgets(5));
  });
}
