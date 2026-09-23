import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wird/data/audio.dart';
import 'package:wird/data/db.dart';
import 'package:wird/shell/wird_shell.dart';

import 'corpus.dart';
import 'fonts.dart';
import 'offline.dart';
import 'wird.dart';

void main() {
  late Database db;
  late AudioCache silent;

  setUpAll(loadBundledFonts);
  setUp(() async {
    db = await testCorpus();
    silent = await emptyCache();
  });

  testWidgets('screen 1d drifts away from the design in a way no behaviour '
      'test can see: the ring, the tiles, the sūra rows, or the chrome the '
      'shell draws above them', (tester) async {
    // The reader the design draws: a sūra finished, one well into, and a set
    // part-read — so the ring has full, partial and untouched arcs on it.
    await markSetUnderstood(db, newOpId(), [
      for (var n = 1; n <= 7; n++) 1000 + n,
      for (var n = 1; n <= 171; n++) 2000 + n,
      103001,
      103002,
    ]);

    // Opened the way a reader opens it. A golden of the screen on its own
    // was green for a round while the shell above it drew a burger and the
    // screen drew a back arrow under it, one above the other.
    await pumpPhone(tester, await wholeApp(db, cache: silent));
    await goTo(tester, 'Your passage');

    await expectLater(
      find.byType(WirdShell),
      matchesGoldenFile('goldens/progress.png'),
    );
  });
}
