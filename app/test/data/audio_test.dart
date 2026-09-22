import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wird/data/audio.dart';

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

    // A cap of eight files against five pinned ones and twenty stale ones.
    await AudioCache(
      dir,
      capBytes: 8 * 1024,
      fetch: FakeCdn().call,
    ).prefetch(paths);

    for (final path in paths) {
      expect(AudioCache(dir).cached(path), isNotNull);
    }
    expect(dir.listSync().length, lessThanOrEqualTo(8));
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
