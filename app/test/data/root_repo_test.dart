import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:wird/data/kept_repo.dart';
import 'package:wird/data/root_repo.dart';

import '../corpus.dart';

/// How many derivatives the corpus gives a root, counted the way the screen
/// counts them.
Future<int> forms(Database db, String letters) async =>
    (await rootReading(db, letters))!.derivatives.length;

void main() {
  late Database db;

  setUp(() async => db = await testCorpus());

  test('the same word is listed twice as two different derivatives because a '
      'pause mark rides along on one of them', () async {
    final reading = (await rootReading(db, 'فلح'))!;
    final spellings = reading.derivatives.map((d) => d.text).toList();
    expect(spellings.toSet().length, spellings.length);
    // ٱلْمُفْلِحُونَ, تُفْلِحُونَ, يُفْلِحُ, أَفْلَحَ, يُفْلِحُونَ, تُفْلِحُوٓا۟
    // and ٱلْمُفْلِحِينَ. The corpus stores تُفْلِحُونَ twice, once carrying a
    // sajda mark, which is the same word read in the same form.
    expect(spellings.length, 7);
  });

  test('a root the ring cannot hold is still handed to the dial, so the '
      'reader gets derivatives stacked on top of each other', () async {
    expect(await forms(db, 'جحم'), 6);
    expect(await forms(db, 'فلح'), 7);
    expect(await forms(db, 'عسي'), 8);
    expect(await forms(db, 'هزأ'), 9);
    for (final letters in ['جحم', 'فلح', 'عسي']) {
      expect(
        (await rootReading(db, letters))!.readsAsSpine,
        isFalse,
        reason: '$letters fits on the ring',
      );
    }
    expect((await rootReading(db, 'هزأ'))!.readsAsSpine, isTrue);
    expect((await rootReading(db, 'صبر'))!.readsAsSpine, isTrue);
  });

  test('a derivative points at the wrong aya because the word id was printed '
      'as a reference instead of the aya inside it', () async {
    // Read the spelling out of the corpus rather than typing it here, so the
    // test cannot pass against a word the screen never shows.
    final rows = await db.query('words', where: 'id = ?', whereArgs: [2153010]);
    final spelling = rows.single['text_ar']! as String;
    final reading = (await rootReading(db, 'صبر'))!;
    final patient = reading.derivatives.firstWhere((d) => d.text == spelling);
    expect(ayahRef(patient.ayahId), '2:153');
  });

  test('the most-read derivative is buried below rarer ones, so the dial '
      'opens on a word the reader will almost never meet', () async {
    final reading = (await rootReading(db, 'صبر'))!;
    final counts = reading.derivatives.map((d) => d.occurrences).toList();
    expect(counts, orderedEquals(List.of(counts)..sort((a, b) => b - a)));
    expect(reading.derivatives.first.text, 'صَبَرُوا۟');
  });

  test('the root screen crashes on a word whose root the corpus does not '
      'carry', () async {
    expect(await rootReading(db, 'زززز'), isNull);
  });

  test('a root kept twice reaches the kept list as two entries', () async {
    await keepRoot(db, '\u0635\u0628\u0631');
    await keepRoot(db, '\u0635\u0628\u0631');

    final kept = await keptItems(db, kind: KeptKind.root);
    expect(kept.map((item) => item.rootLetters), ['\u0635\u0628\u0631']);
    expect(await rootKept(db, '\u0635\u0628\u0631'), isTrue);
    expect(await rootKept(db, '\u0639\u0642\u0644'), isFalse);
  });
}
