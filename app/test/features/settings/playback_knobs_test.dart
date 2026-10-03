import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wird/data/audio.dart';
import 'package:wird/data/db.dart';
import 'package:wird/features/settings/settings_screen.dart';

import '../../corpus.dart';
import '../../fonts.dart';
import '../../wird.dart';

void main() {
  late Database db;

  setUpAll(loadBundledFonts);
  setUp(() async => db = await testCorpus());
  tearDown(() => db.delete('playback_pref'));

  testWidgets('a reader who stops the recitation by holding a word down is '
      'told to keep it, and the choice is gone on the next launch', (
    tester,
  ) async {
    await pumpPhone(tester, await wirdAround(db, const SettingsScreen()));
    final cut = find.text('Stop it');
    await tester.scrollUntilVisible(cut, 200);
    await tester.tap(cut);
    await tester.pumpAndSettle();

    expect((await playbackPref(db)).hear, HearWhileReciting.cut);
    expect(
      (await playbackPref(db)).open,
      buildTuning.open,
      reason: 'the knob the reader did not touch is still the default',
    );
  });
}
