import 'package:flutter_test/flutter_test.dart';
import 'package:wird/features/index/index_screen.dart';
import 'package:wird/features/prayer/alignment.dart';
import 'package:wird/features/prayer/prayer_plan.dart';

import '../../corpus.dart';
import 'sets.dart';

void main() {
  late List<SuraEntry> suras;

  setUpAll(() async => suras = await suraIndex(await testCorpus()));

  List<int> found(String q) => [for (final s in searchSuras(suras, q)) s.id];

  test('typing a sūra the way the design spells it finds nothing', () {
    expect(found('Al-Fātiḥa'), [1]);
    expect(found('fatiha'), [1]);
    expect(found('ikhlas'), contains(112));
    expect(found('Ikhlāṣ'), contains(112));
    expect(found('rahman'), contains(55));
  });

  test('typing the Arabic name without harakāt finds nothing', () {
    expect(found('الكوثر'), [108]);
    expect(found('الْكَوْثَر'), [108]);
  });

  test('typing a sūra number lists every sūra with that digit in it', () {
    expect(found('2'), [2]);
    expect(found('114'), [114]);
    expect(found('115'), isEmpty);
  });

  test('a reference to an aya the sūra does not have is offered anyway', () {
    expect(parseRef('2:255', suras), 2255);
    expect(parseRef(' 2 . 255 ', suras), 2255);
    expect(parseRef('2:287', suras), isNull);
    expect(parseRef('115:1', suras), isNull);
    expect(parseRef('1:0', suras), isNull);
    expect(parseRef('al-baqara', suras), isNull);
  });

  test("the second rakʿah loses the first one's passage when set to the "
      'same, and the third gets a passage at all', () async {
    final db = await testCorpus();
    final asr = await alAsr(db);
    final kawthar = await setOf(db, [108001, 108002, 108003]);
    final same = PrayerPlan(rakahs: 3, first: asr);
    expect(same.passageFor(1), asr);
    expect(same.passageFor(2), asr);
    expect(same.passageFor(3), isNull);
    final own = PrayerPlan(
      rakahs: 2,
      first: asr,
      second: kawthar,
      sameAsFirst: false,
    );
    expect(own.passageFor(2), kawthar);
  });

  test('a basmala said before the passage drags the reciter back to the top '
      'of Al-Fātiḥa', () async {
    final db = await testCorpus();
    final fatiha = (await setOf(db, [
      for (var a = 1; a <= 7; a++) 1000 + a,
    ])).ayas;
    final rakah = rakahOf(fatiha, await alAsr(db));
    // Al-Fātiḥa is 29 words; the basmala goes in after it, unseen.
    expect(rakah.basmalaAt, 29);
    expect(rakah.ayas.length, 10);
    // The opening of the basmala, as a window catches it before the reciter
    // reaches the end of it. Without the inserted copy it names the second
    // word of the prayer, surely enough to light it.
    const begun = 'بسم الله';
    final unseen = [...rakah.heard]..removeRange(29, 33);
    expect(locate(Recitation(unseen), begun)?.word, 1);
    expect(locate(Recitation(rakah.heard), begun), isNull);
    // And the passage is still found past it: word 33 heard is the first word
    // of Al-ʿAṣr.
    expect(locate(Recitation(rakah.heard), 'الرحيم والعصر')?.word, 33);
  });

  test('At-Tawba is heard with a basmala it is never recited with', () async {
    final db = await testCorpus();
    final fatiha = (await setOf(db, [
      for (var a = 1; a <= 7; a++) 1000 + a,
    ])).ayas;
    expect(rakahOf(fatiha, await setOf(db, [9001])).basmalaAt, -1);
    expect(rakahOf(fatiha, null).basmalaAt, -1);
  });

  test('a passage estimate reads as a timer to the second', () {
    expect(recitingTime(1, 40), const Duration(seconds: 5));
    expect(recitingTime(20, 40), const Duration(seconds: 30));
    expect(recitingTime(100, 40), const Duration(minutes: 3));
  });
}
