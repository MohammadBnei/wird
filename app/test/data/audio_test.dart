import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wird/data/audio.dart';
import 'package:wird/data/sets.dart';

import '../corpus.dart';
import '../offline.dart';

/// Al-ʿAlaq 1–5: the first set a new reader is handed, and the one the
/// offline journey prays.
const firstSet = [96001, 96002, 96003, 96004, 96005];

void main() {
  late Database db;

  setUp(() async => db = await testCorpus());

  test('the set was downloaded before takeoff and plays nothing once the '
      'radio is off', () async {
    final dir = await tempAudioDir();
    final tracks = await tracksFor(db, firstSet);
    final paths = [for (final t in tracks) t.relPath];

    final cdn = FakeCdn();
    await AudioCache(dir, fetch: cdn.call).prefetch(paths);
    expect(cdn.served, hasLength(firstSet.length));

    final radio = RadioOff();
    final offline = AudioCache(dir, fetch: radio.call);
    await offline.prefetch(paths);

    expect(
      radio.attempts,
      isEmpty,
      reason: 'a cached set must not reach for the network again',
    );
    expect(SetAudio(cache: offline, tracks: tracks).ready, isTrue);
    for (final path in paths) {
      expect(offline.cached(path)!.lengthSync(), greaterThan(0));
    }
  });

  test('the set the reader is about to pray is evicted to make room for ayas '
      'they already heard', () async {
    final dir = await tempAudioDir();
    final tracks = await tracksFor(db, firstSet);
    final paths = [for (final t in tracks) t.relPath];

    final old = DateTime.now().subtract(const Duration(days: 1));
    for (var i = 0; i < 20; i++) {
      File('${dir.path}/old$i.mp3')
        ..writeAsBytesSync(List.filled(1024, 0))
        ..setLastModifiedSync(old);
    }

    // Three files' worth of cap against twenty stale files and five pinned
    // ones: throwing away every stale file still leaves the cache over the
    // cap, so eviction reaches the set about to be prayed and has to refuse
    // it. A roomier cap would pass with or without the pin.
    await AudioCache(
      dir,
      capBytes: 3 * 1024,
      fetch: FakeCdn().call,
    ).prefetch(paths);

    for (final path in paths) {
      expect(
        AudioCache(dir).cached(path),
        isNotNull,
        reason: '$path was evicted while the reader was about to pray it',
      );
    }
    expect(
      dir.listSync().map((f) => f.uri.pathSegments.last).toSet(),
      {for (final path in paths) path.split('/').last},
      reason: 'the stale files are gone, so the cache really did evict',
    );
  });

  test('the set the reader will be handed next is evicted before they are '
      'ever served it', () async {
    final dir = await tempAudioDir();
    final current = await nextSet(db, ReadingOrder.nuzul);
    final ahead = await nextSet(
      db,
      ReadingOrder.nuzul,
      alsoUnderstood: {for (final aya in current!.ayas) aya.id},
    );
    final aheadPaths = [
      for (final t in await tracksFor(db, [for (final a in ahead!.ayas) a.id]))
        t.relPath,
    ];

    final old = DateTime.now().subtract(const Duration(days: 1));
    for (var i = 0; i < 20; i++) {
      File('${dir.path}/old$i.mp3')
        ..writeAsBytesSync(List.filled(1024, 0))
        ..setLastModifiedSync(old);
    }

    // What screen 1a downloads when it opens the set, against a cap that
    // cannot hold it: everything unpinned goes.
    await AudioCache(dir, capBytes: 3 * 1024, fetch: FakeCdn().call)
        .prefetch(await pathsToKeep(db, ReadingOrder.nuzul, current));

    expect(aheadPaths, hasLength(ahead.ayas.length));
    for (final path in aheadPaths) {
      expect(
        AudioCache(dir).cached(path),
        isNotNull,
        reason: '$path is the next set, gone before the reader reached it',
      );
    }
  });

  test('the highlight lags the recitation by more than the 80 ms a reader can '
      'feel', () async {
    final tracks = await tracksFor(db, firstSet);
    final tick = highlightPeriod.inMilliseconds;

    for (final (index, track) in tracks.indexed) {
      for (final span in track.segments) {
        // The first sample taken at or after the word starts sounding.
        final sampled = (span.startMs + tick - 1) ~/ tick * tick;
        expect(
          sampled - span.startMs,
          lessThan(80),
          reason: 'word ${span.wordId} lights up $sampled ms into the aya',
        );
        expect(wordAt(tracks, index, sampled), span.wordId);
      }
    }
  });

  test('the second aya of the set highlights a word out of the first, '
      'because the two files are read as one timeline', () async {
    final tracks = await tracksFor(db, firstSet);
    final second = tracks[1];

    final lit = wordAt(tracks, 1, second.segments.first.startMs + 10);

    expect(lit, second.segments.first.wordId);
    expect(lit! ~/ 1000, 96002, reason: 'the word belongs to aya 96:2');
  });

  test('a long press seeks into the wrong aya, because the word was looked up '
      'in the file before it', () async {
    final tracks = await tracksFor(db, firstSet);

    final found = locate(tracks, 96003002)!;

    expect(found.track.ayahId, 96003);
    expect(found.track.relPath, contains('096003'));
    expect(found.span.startMs, lessThan(found.span.endMs));
  });

  test('a short word opens on the next MP3 frame and loses its first '
      'consonant', () {
    expect(clipStart(830), const Duration(milliseconds: 830) - seekCalibration);
    expect(
      clipStart(10),
      Duration.zero,
      reason: 'the pad may not seek behind the start of the file',
    );
  });
}
