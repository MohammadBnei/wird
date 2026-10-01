import 'package:flutter_test/flutter_test.dart';
import 'package:wird/data/db.dart';

import '../corpus.dart';
import '../features/prayer/sets.dart';

void main() {
  test('a prayer prepared once is prepared from scratch the next time', () async {
    final db = await testCorpus();
    expect(await prayerPrefs(db), defaultPrayerPrefs);
    const mine = (
      preset: null,
      rakahs: 2,
      voice: false,
      pace: true,
      wpm: 25,
      gloss: false,
      around: false,
      arabicSize: 64.0,
    );
    await setPrayerPrefs(db, mine);
    expect(await prayerPrefs(db), mine);
  });

  test('the chooser offers the same passage twice, or the oldest first', () async {
    final db = await testCorpus();
    await notePassageRecited(db, await alAsr(db));
    await notePassageRecited(db, await setOf(db, [108001, 108002, 108003]));
    await notePassageRecited(db, await alAsr(db));
    expect(await recentPassages(db), [
      (start: 103001, end: 103003),
      (start: 108001, end: 108003),
    ]);
  });

  test('a recited passage is sent to the server', () async {
    final db = await testCorpus();
    await notePassageRecited(db, await alAsr(db));
    expect(await db.query('outbox'), isEmpty);
  });
}
