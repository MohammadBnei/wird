import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:wird/data/db.dart';

import '../corpus.dart';

void main() {
  late Database db;

  setUp(() async => db = await testCorpus());

  // The failure: a reader who has never opened the language setting gets
  // pinned to English, so setting their phone to French later changes nothing.
  // Only an absent row can mean "whatever this phone is".
  test('nothing is stored until the reader chooses, so an English phone is '
      'not a choice', () async {
    expect(await languagePref(db), isNull);
  });

  // The failure: a reader picks French, comes back tomorrow, and reads English
  // — or goes back to following their phone and stays pinned to the last
  // language they happened to tap.
  test('a language picked is still picked next launch, and going back to the '
      'phone forgets it', () async {
    await setLanguagePref(db, 'fr');
    expect(await languagePref(db), 'fr');

    await setLanguagePref(db, 'en');
    expect(await languagePref(db), 'en');

    await setLanguagePref(db, null);
    expect(await languagePref(db), isNull);
  });
}
