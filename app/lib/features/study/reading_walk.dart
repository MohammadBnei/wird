import '../../data/root_repo.dart' show ayahOfWord;
import '../../data/sets.dart';

/// Where a step lands: the aya, by its place in the sūra, and the word in it.
/// [wordId] is null when that aya's words have not been read yet; the caller
/// reads them and steps again.
typedef WalkStep = ({int ayaIndex, int? wordId});

/// The word [by] along from [fromWordId], through the whole of [ayas].
///
/// Found by aya rather than by a place in one flat list of the words read so
/// far. That list has gaps wherever a chunk was never read, so on a sūra
/// opened at 2:255 a step past the chunk landed back near 2:1, and a step
/// backwards stopped at the top of the first chunk. Here a step past the end
/// of an aya goes to the next aya, read or not.
///
/// Null at either end of the sūra, and when [fromWordId] is not in [words].
WalkStep? stepFrom(
  List<StudyAya> ayas,
  Map<int, List<StudyWord>> words,
  int fromWordId,
  int by,
) {
  final ayaIndex = ayas.indexWhere((a) => a.id == ayahOfWord(fromWordId));
  if (ayaIndex < 0) return null;
  final here = words[ayas[ayaIndex].id];
  final at = here?.indexWhere((w) => w.id == fromWordId) ?? -1;
  if (here == null || at < 0) return null;
  final to = at + by;
  if (to >= 0 && to < here.length) {
    return (ayaIndex: ayaIndex, wordId: here[to].id);
  }
  final next = ayaIndex + (to < 0 ? -1 : 1);
  if (next < 0 || next >= ayas.length) return null;
  final there = words[ayas[next].id];
  if (there == null || there.isEmpty) return (ayaIndex: next, wordId: null);
  return (ayaIndex: next, wordId: to < 0 ? there.last.id : there.first.id);
}
