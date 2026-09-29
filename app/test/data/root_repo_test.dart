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

  test('the bundle ships a sense a correction can never reach', () async {
    final reading = (await rootReading(db, 'صبر'))!;
    // Not a gap. A sense is Wird's own sentence and the reader's thumb corrects
    // it, so shipping it inside the binary put every correction behind a store
    // release. The server owns them and senses.dart fetches them (ADR 0010).
    expect(reading.coreSense, isNull);
    expect(reading.senseSource, isNull);
    expect(reading.senseBasis, isNull);
    expect(reading.senseEvidence, isEmpty);
    // And the device says which of the two absences this is, because "nobody
    // wrote a sense for this root" and "nothing has been downloaded" are
    // different sentences to a reader.
    expect(reading.sensesFetched, isFalse);
  });

  test('a fetched sense still carries the words it was read from, so the '
      'screen can put the gloss beside each one', () async {
    // It does not, and that is a real loss rather than an oversight. The
    // bundled 523 each carried five to twelve evidence words; a served draft
    // carries none, because it was not read off a word list. So senseEvidence
    // is empty for every root a reader can reach, RootReading.spelled has
    // nothing to match, and SenseEvidence draws no word list.
    //
    // This test pins the consequence rather than asserting the old behaviour,
    // because the old behaviour is what is gone. The affordance comes back the
    // day the served body grows an evidence field; until then, anything
    // reading senseEvidence is reading an empty list.
    //
    // ponytail: RootReading.spelled and _evidenceWords are kept rather than
    // deleted. Dead-code removal is its own commit in a later phase, and the
    // evidence field is a live design question, not a decision already taken.
    final reading = (await rootReading(db, 'صبر'))!;
    expect(reading.senseEvidence, isEmpty);
  });

  test('a root kept twice reaches the kept list as two entries', () async {
    await keepRoot(db, '\u0635\u0628\u0631');
    await keepRoot(db, '\u0635\u0628\u0631');

    final kept = await keptItems(db, kind: KeptKind.root);
    expect(kept.map((item) => item.rootLetters), ['\u0635\u0628\u0631']);
    expect(await rootKept(db, '\u0635\u0628\u0631'), kept.single.id);
    expect(await rootKept(db, '\u0639\u0642\u0644'), isNull);
  });

  test('an aya kept twice reaches the kept list as two entries, because only '
      'the root path deduped', () async {
    // The screen's own `_keptId` cannot answer this: it is read when the screen
    // opens, so a row kept on screen 1e — or arriving from a sync — while the
    // deep dive sits open is invisible to the button.
    const aya = 112004;
    Future<int> live() async => (await keptItems(db, kind: KeptKind.aya))
        .where((item) => item.ayahId == aya)
        .length;

    expect(await keepAya(db, aya), await keepAya(db, aya));
    expect(await live(), 1);
    expect(await ayaKept(db, aya), isNotNull);
  });

  test('a root taken back off the list is still on it, because the undo '
      'tombstoned one of the rows holding it there', () async {
    // Two live rows for one root is reachable: the server keys kept_items on
    // its id alone and kept_items_live is not unique, so two devices \u2014 one of
    // them offline \u2014 each mint one. Undoing has to clear all of them.
    const root = '\u062c\u0645\u0639';
    Future<int> live() async => (await keptItems(db, kind: KeptKind.root))
        .where((item) => item.rootLetters == root)
        .length;

    await keep(db, kind: KeptKind.root, rootLetters: root);
    await keep(db, kind: KeptKind.root, rootLetters: root);
    expect(await live(), 2);

    await forgetRoot(db, root);

    expect(await rootKept(db, root), isNull);
    expect(await live(), 0);
  });

  // The failure: a reader switches the app to French, opens a root, and reads
  // the English sense — which is what shipped before the language setting, when
  // note_fr was a column nothing drew.
  test('a root read in French carries the French sense', () async {
    await db.insert('root_notes', {
      'root_letters': 'فلح',
      'word_id': null,
      'note': 'to succeed, to prosper',
      'note_fr': 'réussir, prospérer',
    });

    expect(
      (await rootReading(db, 'فلح', inFrench: true))!.coreSense,
      'réussir, prospérer',
    );
    expect((await rootReading(db, 'فلح'))!.coreSense, 'to succeed, to prosper');
  });

  // The failure: a root whose French never arrived draws nothing at all in
  // French, so a reader is told no sense is written when one is.
  test('a root with no French falls back to the sense that exists', () async {
    await db.insert('root_notes', {
      'root_letters': 'فلح',
      'word_id': null,
      'note': 'to succeed, to prosper',
      'note_fr': null,
    });

    expect(
      (await rootReading(db, 'فلح', inFrench: true))!.coreSense,
      'to succeed, to prosper',
    );
  });
}
