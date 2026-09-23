import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wird/data/audio.dart';
import 'package:wird/data/kept_repo.dart';
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
    await ensureKeptTable(db);
    await db.delete('kept_items');
  });

  testWidgets('screen 1e drifts away from the design in a way no behaviour '
      'test can see: the search field, the filter, the cards, or the chrome '
      'the shell draws above them', (tester) async {
    // The three kept ayas the design draws, oldest first so the list orders
    // them the way the screen was drawn.
    await keep(
      db,
      kind: KeptKind.aya,
      ayahId: 103002,
      body:
          'Ask: is خُسْر the loss itself, or the state of losing? Ṭabarī '
          'reads it as the ruin one is already inside.',
    );
    await keep(
      db,
      kind: KeptKind.aya,
      ayahId: 2153,
      rootLetters: 'صبر',
      body:
          'Same root, read 209 sets ago. Flagged when the constellation '
          'surfaced it.',
      tags: ['revisit'],
    );
    await keep(
      db,
      kind: KeptKind.aya,
      ayahId: 103003,
      body:
          'The form VI verb makes it mutual — not "be patient" but "bind '
          'each other to patience". Changes who the aya is addressed to.',
      tags: ['grammar'],
    );

    // Opened the way a reader opens it: a golden of the screen alone could
    // not see that the shell's burger and the screen's own back arrow were
    // stacked in the same corner.
    await pumpPhone(tester, await wholeApp(db, cache: silent));
    await goTo(tester, 'Kept');

    await expectLater(
      find.byType(WirdShell),
      matchesGoldenFile('goldens/kept.png'),
    );
  });
}
