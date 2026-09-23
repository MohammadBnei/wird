import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wird/data/audio.dart';
import 'package:wird/data/sets.dart';

import '../corpus.dart';
import '../offline.dart';

/// Serves the recitation, holding the first file back until the test lets it
/// go: a download in flight while the reader moves on.
class HeldCdn {
  final served = <String>[];
  final reached = Completer<void>();
  final _gate = Completer<void>();

  void release() => _gate.complete();

  Future<List<int>> call(String url) async {
    served.add(url.split('/').last);
    if (!reached.isCompleted) {
      reached.complete();
      await _gate.future;
    }
    return List.filled(1024, 0);
  }
}

void main() {
  late Database db;

  setUp(() async => db = await testCorpus());

  test('the set the reader jumped away from goes on downloading behind them, '
      'over the aya they asked for', () async {
    final dir = await tempAudioDir();
    final walking = (await nextSet(db, ReadingOrder.nuzul))!;
    final walk = await pathsToKeep(db, ReadingOrder.nuzul, walking);
    final visited = (await pathsToKeep(
      db,
      ReadingOrder.nuzul,
      (await ayaSet(db, ReadingOrder.nuzul, 4082))!,
      onTheWalk: false,
    )).single;

    final cdn = HeldCdn();
    final cache = AudioCache(dir, fetch: cdn.call);
    final leaving = cache.prefetch(walk);
    await cdn.reached.future;
    await cache.prefetch([visited]);
    cdn.release();
    await leaving;

    expect(walk, hasLength(10));
    expect(cdn.served, [
      walk.first.split('/').last,
      visited.split('/').last,
    ]);
  });

  test('the aya the reader asked for drags the set the walk would have served '
      'next onto the phone with it', () async {
    final visited = (await ayaSet(db, ReadingOrder.nuzul, 4082))!;

    final keep = await pathsToKeep(
      db,
      ReadingOrder.nuzul,
      visited,
      onTheWalk: false,
    );

    expect(keep, hasLength(1));
    expect(keep.single, contains('004082'));
  });
}
