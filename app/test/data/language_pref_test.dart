import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:wird/data/db.dart';

import '../corpus.dart';

void main() {
  late Database db;

  setUp(() async => db = await testCorpus());

  // The failure: a reader who has never opened the language setting is not in
  // "English", they are in "whatever this phone is", and only an absent row
  // says that. A stored default would pin an English phone's reader to English
  // the day they set their phone to French.
  test('a reader who has chosen nothing follows their phone', () async {
    expect(await languagePref(db), isNull);
  });

  test('the choice is kept, and going back to the phone forgets it', () async {
    await setLanguagePref(db, 'fr');
    expect(await languagePref(db), 'fr');

    await setLanguagePref(db, 'en');
    expect(await languagePref(db), 'en');

    await setLanguagePref(db, null);
    expect(
      await languagePref(db),
      isNull,
      reason: 'the row is gone, so this reader is where they started rather '
          'than pinned to the last language they happened to pick',
    );
  });

  // The failure: the row is written with REPLACE on a fixed id, and a second
  // write that inserted instead would leave two rows with the first one won by
  // the `limit: 1` read — a reader switching language once and then back
  // reading in the language they left.
  test('switching twice leaves one row', () async {
    await setLanguagePref(db, 'fr');
    await setLanguagePref(db, 'en');
    final rows = await db.query('language_pref');
    expect(rows.length, 1);
  });
}
