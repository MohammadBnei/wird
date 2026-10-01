import 'package:flutter_test/flutter_test.dart';
import 'package:wird/data/sets.dart';
import 'package:wird/features/study/reading_walk.dart';

StudyAya _aya(int id) => StudyAya(
  id: id,
  surahId: id ~/ 1000,
  number: id % 1000,
  surahNameEn: '',
  surahNameAr: '',
  revelationOrder: 0,
  revelationPlace: '',
  understood: false,
  words: const [],
  wordCount: 3,
);

List<StudyWord> _words(int ayaId) => [
  for (var p = 1; p <= 3; p++)
    StudyWord(id: ayaId * 1000 + p, text: '$ayaId:$p'),
];

void main() {
  // Al-Baqarah, with only the chunk around 2:255 read.
  final ayas = [for (var a = 1; a <= 286; a++) _aya(2000 + a)];
  final read = {
    for (final a in [2254, 2255]) a: _words(a),
  };

  test('a step past the read chunk from 2:255 lands near 2:1 instead of on '
      "2:256's first word", () {
    expect(stepFrom(ayas, read, 2255003, 1), (ayaIndex: 255, wordId: null));
    final withNext = {...read, 2256: _words(2256)};
    expect(stepFrom(ayas, withNext, 2255003, 1), (
      ayaIndex: 255,
      wordId: 2256001,
    ));
  });

  test('a step back from the first word of an aya stops instead of reaching '
      'the last word of the aya before', () {
    expect(stepFrom(ayas, read, 2255001, -1), (ayaIndex: 253, wordId: 2254003));
  });

  test('the walk runs past the ends of the sūra', () {
    final ends = {2001: _words(2001), 2286: _words(2286)};
    expect(stepFrom(ayas, ends, 2001001, -1), isNull);
    expect(stepFrom(ayas, ends, 2286003, 1), isNull);
  });
}
