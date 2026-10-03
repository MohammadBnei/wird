import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wird/app.dart';
import 'package:wird/data/audio.dart';
import 'package:wird/data/db.dart';

import '../corpus.dart';
import '../offline.dart';
import '../player.dart';

/// Al-ʿAlaq 1–5: the first set a new reader is handed, and the one the
/// offline journey prays.
const firstSet = [96001, 96002, 96003, 96004, 96005];

void main() {
  // The fake audio platform talks over the binary messenger, which a plain
  // test does not bring up on its own.
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;

  setUp(() async => db = await testCorpus());

  /// The set's recitation on disk, under a cache that can fetch no more.
  Future<AudioCache> cacheHolding(List<int> ayahIds) async {
    final dir = await tempAudioDir();
    final tracks = await tracksFor(db, ayahIds);
    await AudioCache(
      dir,
      fetch: FakeCdn().call,
    ).prefetch([for (final t in tracks) t.relPath]);
    return AudioCache(dir, fetch: RadioOff().call);
  }

  test('the word the reader taps second is left dark, because the word before '
      'it clears the highlight when its own clip ends', () async {
    final tracks = await tracksFor(db, firstSet);
    final players = FakePlayers();
    JustAudioPlatform.instance = players;
    final audio = SetAudio(cache: await cacheHolding(firstSet), tracks: tracks);

    final first = audio.playWord(96001001);
    await pumpEventQueue();
    expect(audio.currentWordId.value, 96001001);

    final second = audio.playWord(96001002);
    await pumpEventQueue();
    expect(
      audio.currentWordId.value,
      96001002,
      reason: 'the word under the reader\'s finger is the one lit',
    );

    players.only.finish();
    expect(await first, isTrue);
    expect(await second, isTrue);
    expect(audio.currentWordId.value, isNull);
    expect(audio.playing.value, isFalse);
  });

  test('the word the reader taps lights a word they never touched, because '
      'the set they just played is still moving the highlight', () async {
    final tracks = await tracksFor(db, firstSet);
    JustAudioPlatform.instance = FakePlayers();
    final audio = SetAudio(cache: await cacheHolding(firstSet), tracks: tracks);

    unawaited(audio.toggle());
    await pumpEventQueue();

    unawaited(audio.playWord(96002003));
    await pumpEventQueue();

    expect(
      audio.currentWordId.value,
      96002003,
      reason: 'the word under the reader\'s finger is the one lit',
    );
  });

  test('the word the reader tapped a moment before they pressed play lights '
      'over the recitation they started', () async {
    final tracks = await tracksFor(db, firstSet);
    JustAudioPlatform.instance = FakePlayers();
    final audio = SetAudio(cache: await cacheHolding(firstSet), tracks: tracks);

    unawaited(audio.playWord(96003001));
    unawaited(audio.toggle());
    await pumpEventQueue();

    expect(
      audio.currentWordId.value,
      isNot(96003001),
      reason: 'the set owns the highlight once the reader has pressed play',
    );
  });

  test('an audio platform that refuses a word throws out of the tap instead '
      'of leaving the word silent', () async {
    final tracks = await tracksFor(db, firstSet);
    JustAudioPlatform.instance = FakePlayers(refuses: true);
    final audio = SetAudio(cache: await cacheHolding(firstSet), tracks: tracks);

    expect(await audio.playWord(96001001), isFalse);
    expect(audio.playing.value, isFalse);
    expect(audio.currentWordId.value, isNull);
  });

  test('a word of an aya not downloaded yet is left dark, though the player '
      'fetches it as it plays', () async {
    final tracks = await tracksFor(db, firstSet);
    final audio = SetAudio(
      cache: AudioCache(await tempAudioDir(), fetch: RadioOff().call),
      tracks: tracks,
    );

    expect(audio.speakable, {
      for (final track in tracks)
        for (final span in track.segments) span.wordId,
    });
  });

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
    expect(dir.listSync().map((f) => f.uri.pathSegments.last).toSet(), {
      for (final path in paths)
        AudioCache(dir).fileFor(path).uri.pathSegments.last,
    }, reason: 'the stale files are gone, so the cache really did evict');
  });

  test('the stretch ahead of the open aya is evicted before the reader '
      'reaches it', () async {
    final dir = await tempAudioDir();
    final tracks = await tracksFor(db, [
      for (var n = 1; n <= 19; n++) 96000 + n,
    ]);
    final keep = windowPaths(tracks, 96001);

    final old = DateTime.now().subtract(const Duration(days: 1));
    for (var i = 0; i < 20; i++) {
      File('${dir.path}/old$i.mp3')
        ..writeAsBytesSync(List.filled(1024, 0))
        ..setLastModifiedSync(old);
    }

    // What screen 1a downloads when it opens 96:1, against a cap that cannot
    // hold it: everything unpinned goes.
    await AudioCache(
      dir,
      capBytes: 3 * 1024,
      fetch: FakeCdn().call,
    ).prefetch(keep);

    expect(keep, hasLength(aheadAyas));
    for (final path in keep) {
      expect(
        AudioCache(dir).cached(path),
        isNotNull,
        reason: '$path is ahead of the reader, gone before they reached it',
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

  test('a reciter the corpus times has no folder to fetch from, so picking '
      'them plays nothing', () async {
    final slugs = [
      for (final row in await db.query('recitations')) row['slug']! as String,
    ];
    expect(slugs, isNotEmpty);
    expect(slugs, contains(defaultReciter));
    expect(
      {for (final r in await reciters(db)) r.slug},
      slugs.toSet(),
      reason: 'every slug in the corpus needs its folder in reciterFolders',
    );
  });

  test('two reciters download the same aya into one file, and one plays in '
      'the other\'s voice', () async {
    final dir = await tempAudioDir();
    final cdn = FakeCdn();
    final husary = (await tracksFor(db, [96001])).single;
    final alafasy = (await tracksFor(db, [96001], reciter: 'alafasy')).single;
    final cache = AudioCache(dir, fetch: cdn.call);
    await cache.prefetch([husary.relPath, alafasy.relPath]);

    expect(
      cache.fileFor(husary.relPath).path,
      isNot(cache.fileFor(alafasy.relPath).path),
    );
    expect(dir.listSync().whereType<File>(), hasLength(2));
    expect(cdn.served, [
      'https://everyayah.com/data/Husary_Muallim_128kbps/096001.mp3',
      'https://everyayah.com/data/Alafasy_128kbps/096001.mp3',
    ]);
  });

  test(
    'a second reciter highlights with the first reciter\'s timings',
    () async {
      final husary = (await tracksFor(db, [96001])).single;
      final alafasy = (await tracksFor(db, [96001], reciter: 'alafasy')).single;

      expect(
        [for (final s in alafasy.segments) s.wordId],
        [for (final s in husary.segments) s.wordId],
        reason: 'the same words, each once',
      );
      expect(
        [for (final s in alafasy.segments) s.startMs],
        isNot([for (final s in husary.segments) s.startMs]),
        reason: 'two recordings do not pause in the same places',
      );
    },
  );

  test('a second reciter\'s files escape the cap because they sit somewhere '
      'the sweep does not look', () async {
    final dir = await tempAudioDir();
    final paths = [
      for (final t in await tracksFor(db, firstSet, reciter: 'alafasy'))
        t.relPath,
    ];
    final cache = AudioCache(dir, capBytes: 3 * 1024, fetch: FakeCdn().call);
    await cache.prefetch(paths);
    // The next set pins nothing of this one, so the sweep must bring it back
    // under the cap.
    await cache.prefetch([
      for (final t in await tracksFor(db, [96006], reciter: 'alafasy'))
        t.relPath,
    ]);
    final held = dir.listSync(recursive: true).whereType<File>();
    expect(
      held.fold(0, (sum, f) => sum + f.lengthSync()),
      lessThanOrEqualTo(3 * 1024),
    );
  });

  test('a reciter a later corpus dropped leaves the reader with no recitation '
      'at all', () async {
    await setAudioPref(
      db,
      reciter: 'a-reciter-no-corpus-carries',
      wordByWord: true,
    );
    expect(await audioPref(db), (reciter: defaultReciter, wordByWord: true));
    expect(
      (await db.query('audio_pref')).single['reciter'],
      defaultReciter,
      reason: 'the stale choice is replaced rather than kept and ignored',
    );

    await setAudioPref(db, reciter: 'alafasy', wordByWord: false);
    expect(await audioPref(db), (reciter: 'alafasy', wordByWord: false));
    await db.delete('audio_pref');
  });

  test('files cached before there was a choice of reciter hold the cap '
      'forever, because nothing asks for their names', () async {
    final root = await tempAudioDir();
    final dir = Directory('${root.path}/audio')..createSync();
    File('${dir.path}/096001.mp3').writeAsBytesSync([0]);
    File('${dir.path}/Alafasy_128kbps_096001.mp3').writeAsBytesSync([0]);

    await AudioCache.beside(root.path);

    expect(
      [for (final f in dir.listSync()) f.uri.pathSegments.last],
      ['Alafasy_128kbps_096001.mp3'],
    );
  });

  test('a word after a pause mark is spoken by the word beside it, or not at '
      'all, because its path counted the mark as a word', () async {
    // The host numbers its files by word (ADR 0029). 2:2 has seven words and
    // seven files, with a mark after its fourth and fifth words; the path the
    // API gives its last word is a ninth file that does not exist.
    final track = (await tracksFor(db, [2002])).single;
    expect(track.wordFiles[2002005], 'wbw/002_002_005.mp3');
    expect(track.wordFiles[2002007], 'wbw/002_002_007.mp3');
    // 12:1 opens on alif lam ra, one word and one file.
    final open = (await tracksFor(db, [12001])).single;
    expect(open.wordFiles[12001002], 'wbw/012_001_002.mp3');
  });

  test('the words of the set are not fetched for a reader who asked to hear '
      'each word alone, so a tapped word is silent offline', () async {
    final cdn = FakeCdn();
    await AudioCache(await tempAudioDir(), fetch: cdn.call).prefetch(
      windowPaths(await tracksFor(db, firstSet), 96001, wordByWord: true),
    );
    expect(cdn.served, contains('${wordAudioOrigin}wbw/096_001_001.mp3'));
    expect(
      cdn.served,
      contains('${defaultAudioOrigin}Husary_Muallim_128kbps/096001.mp3'),
      reason: 'the set\'s own recitation still comes with it',
    );
  });

  test('a word the reader asked to hear alone plays a stretch of the '
      'reciter\'s aya instead', () async {
    final tracks = await tracksFor(db, firstSet);
    final dir = await tempAudioDir();
    // Only the word's own file is on the phone, not its aya's.
    await AudioCache(
      dir,
      fetch: FakeCdn().call,
    ).prefetch([tracks.first.wordFiles[96001001]!]);
    final players = FakePlayers();
    JustAudioPlatform.instance = players;
    final audio = SetAudio(
      cache: AudioCache(dir, fetch: RadioOff().call),
      tracks: tracks,
      wordByWord: true,
    );

    expect(audio.speakable, contains(96001001));
    final played = audio.playWord(96001001);
    await pumpEventQueue();
    players.only.finish();
    expect(await played, isTrue);
    expect(players.only.loaded.single, contains('wbw_096_001_001.mp3'));
    expect(
      players.only.loaded.single,
      isNot(contains('clipping')),
      reason: 'the file is the word, start to end',
    );
  });

  test('a word with no recording of its own falls silent instead of playing '
      'its stretch of the aya', () async {
    final tracks = await tracksFor(db, firstSet);
    final players = FakePlayers();
    JustAudioPlatform.instance = players;
    final audio = SetAudio(
      cache: await cacheHolding(firstSet),
      tracks: tracks,
      wordByWord: true,
    );

    final played = audio.playWord(96001001);
    await pumpEventQueue();
    players.only.finish();
    expect(await played, isTrue);
    // setClip reloads the source wrapped in the clip, so the clip is last.
    expect(players.only.loaded.last, contains('clipping'));
  });

  test('a phone whose corpus upgrade failed cannot open the app, because the '
      'corpus it kept has no reciters to choose from', () async {
    await testCorpus(); // sets up the ffi database factory
    final dir = await Directory.systemTemp.createTemp('wird-v6');
    final path = '${dir.path}/wird.db';
    await File('assets/corpus.db').copy(path);
    // The shape corpus 6 shipped: one reciter keyed by slug, timings keyed by
    // slug, and no word-by-word path.
    final old = await openDatabase(path);
    await old.execute('DROP TABLE word_segments');
    await old.execute('DROP TABLE recitations');
    await old.execute(
      'CREATE TABLE recitations (slug TEXT PRIMARY KEY, reciter_name TEXT '
      'NOT NULL, style TEXT)',
    );
    await old.execute(
      'CREATE TABLE word_segments (word_id INTEGER, recitation_slug TEXT, '
      'start_ms INTEGER, end_ms INTEGER)',
    );
    await old.execute('ALTER TABLE words DROP COLUMN wbw_path');
    await old.close();
    final kept = await openWirdAt(path);
    await setAudioPref(kept, reciter: 'alafasy', wordByWord: true);

    final prefs = await Prefs.read(kept);
    expect(prefs.reciter, 'alafasy', reason: 'kept for the upgrade that works');
    expect(await tracksFor(kept, firstSet), isEmpty);
    await kept.close();
  });

  test('hearing a reciter in the settings unpins the set the reader is about '
      'to pray', () async {
    final dir = await tempAudioDir();
    final set = [for (final t in await tracksFor(db, firstSet)) t.relPath];
    final cdn = FakeCdn();
    final cache = AudioCache(dir, capBytes: 5 * 1024, fetch: cdn.call);
    await cache.prefetch(set);

    final sample = await cache.fetchOne('Alafasy_128kbps/$sampleFile');
    expect(sample, isNotNull);
    expect(cdn.served.last, '${defaultAudioOrigin}Alafasy_128kbps/001001.mp3');

    // The next sweep, over a cap the sample pushed the cache past, takes the
    // sample and leaves the set: the pins are still the set's.
    await cache.prefetch([...set, 'Husary_64kbps/096001.mp3']);
    for (final path in set) {
      expect(cache.cached(path), isNotNull, reason: '$path was unpinned');
    }
  });

  test('a reciter sampled in the settings plays over the set the reader '
      'started', () async {
    final players = FakePlayers();
    JustAudioPlatform.instance = players;
    final cache = await cacheHolding(firstSet);
    final recitation = Recitation(cache: cache);
    await recitation.carry(
      await tracksFor(db, firstSet),
      title: 'Al-ʿAlaq 1–5',
    );
    unawaited(recitation.toggle());
    await pumpEventQueue();
    expect(recitation.playing.value, isTrue);

    // Offline, so the sample never arrives: what matters is that the set
    // stopped and nothing is left marked as sampling.
    await recitation.sample('alafasy');
    expect(recitation.playing.value, isFalse);
    expect(recitation.sounding.value, isNull);
    expect(recitation.sampling.value, isNull);
  });

  test('the bar recites a set without saying who recites it', () async {
    JustAudioPlatform.instance = FakePlayers();
    final recitation = Recitation(cache: await cacheHolding(firstSet));
    await recitation.carry(
      await tracksFor(db, firstSet),
      title: 'Al-ʿAlaq 1–5',
      voice: 'Mishary Rashid Alafasy',
    );
    unawaited(recitation.toggle());
    await pumpEventQueue();
    expect(
      recitation.sounding.value?.label,
      'Al-ʿAlaq 1–5 · Mishary Rashid Alafasy',
    );
    await recitation.stop();
  });

  test('the aya the reader asked to hear plays the whole set from its first '
      'aya', () async {
    final tracks = await tracksFor(db, firstSet);
    final players = FakePlayers();
    JustAudioPlatform.instance = players;
    final audio = SetAudio(cache: await cacheHolding(firstSet), tracks: tracks);

    final played = audio.playAya(96003);
    await pumpEventQueue();
    final loaded = players.only.loaded.last;
    expect(loaded, contains('096003'));
    expect(loaded, isNot(contains('096001')));
    expect(loaded, isNot(contains('096004')));
    players.only.finish();
    expect(await played, isTrue);
  });

  Future<Recitation> reciting(FakePlayers players) async {
    JustAudioPlatform.instance = players;
    final recitation = Recitation(cache: await cacheHolding(firstSet));
    await recitation.carry(
      await tracksFor(db, firstSet),
      title: 'Al-ʿAlaq 1–5',
    );
    return recitation;
  }

  test('an aya started while the set recites plays with no bar to pause or '
      'stop it', () async {
    final players = FakePlayers();
    final recitation = await reciting(players);
    unawaited(recitation.toggle());
    await pumpEventQueue();

    unawaited(recitation.playAya(96003, label: '96:3'));
    await pumpEventQueue();
    expect(recitation.sounding.value?.what, Sounded.aya);
    expect(recitation.sounding.value?.label, '96:3');
    await recitation.stop();
  });

  test('the aya tapped again while it plays loses its bar to the first tap '
      'ending', () async {
    final players = FakePlayers();
    final recitation = await reciting(players);
    unawaited(recitation.playAya(96003, label: '96:3'));
    await pumpEventQueue();
    unawaited(recitation.playAya(96003, label: '96:3'));
    await pumpEventQueue();
    expect(recitation.sounding.value?.label, '96:3');
    expect(recitation.playing.value, isTrue);
    await recitation.stop();
  });

  test('a word paused from the play button makes the next press recite the '
      'whole set with no bar', () async {
    final players = FakePlayers();
    final recitation = await reciting(players);
    unawaited(recitation.playWord(96001001, label: 'iqraʾ'));
    await pumpEventQueue();
    await recitation.toggle(); // the header's button, while the word sounds
    await pumpEventQueue();

    unawaited(recitation.toggle());
    await pumpEventQueue();
    expect(recitation.sounding.value?.what, Sounded.set);
    await recitation.stop();
  });

  /// Al-ʿAlaq whole, as the reading screen carries it.
  Future<List<AyaTrack>> alAlaq() =>
      tracksFor(db, [for (var n = 1; n <= 19; n++) 96000 + n]);

  test('an aya past the ones on the phone is silent, though the player can '
      'fetch it as it plays', () async {
    final players = FakePlayers();
    JustAudioPlatform.instance = players;
    final audio = SetAudio(
      cache: await cacheHolding(firstSet),
      tracks: await alAlaq(),
    );

    final played = audio.playAya(96015);
    await pumpEventQueue();
    expect(audio.playing.value, isTrue);
    players.only.finish();
    expect(await played, isTrue);
  });

  test('a word past the ayas on the phone is silent in either voice', () async {
    final tracks = await alAlaq();
    for (final alone in [false, true]) {
      JustAudioPlatform.instance = FakePlayers();
      final audio = SetAudio(
        cache: await cacheHolding(firstSet),
        tracks: tracks,
        wordByWord: alone,
      );
      unawaited(audio.playWord(96015001));
      await pumpEventQueue();
      expect(audio.currentWordId.value, 96015001, reason: 'alone: $alone');
      await audio.stop();
    }
  });

  test('the recitation stops at the ayas around the open word, in the middle '
      'of the sūra', () async {
    final players = FakePlayers();
    JustAudioPlatform.instance = players;
    final audio = SetAudio(
      cache: await cacheHolding(firstSet),
      tracks: await alAlaq(),
    );

    unawaited(audio.playFrom(96003002));
    await pumpEventQueue();
    final loaded = players.only.loaded.last;
    expect(loaded, isNot(contains('096002')));
    expect(loaded, contains('096003'));
    expect(loaded, contains('096019'), reason: 'on to the end of the sūra');
    await audio.stop();
  });

  test('opening a word in another aya stops the recitation it was carried '
      'under', () async {
    JustAudioPlatform.instance = FakePlayers();
    final recitation = Recitation(cache: await cacheHolding(firstSet));
    final tracks = await alAlaq();
    await recitation.carry(tracks, title: 'Al-ʿAlaq');
    unawaited(recitation.playFrom(null));
    await pumpEventQueue();

    // The reading screen carries the sūra again on every word it opens.
    await recitation.carry(await alAlaq(), title: 'Al-ʿAlaq');
    expect(recitation.playing.value, isTrue);
    await recitation.stop();
  });

  test('a file the player holds is evicted from under it, and the recitation '
      'ends when it gets there', () async {
    final dir = await tempAudioDir();
    final cache = AudioCache(dir, fetch: FakeCdn().call, capBytes: 2 * 1024);
    await cache.prefetch(['a/1.mp3']);
    cache.hold(['a/1.mp3']);
    await cache.prefetch(['a/2.mp3', 'a/3.mp3']);
    expect(cache.cached('a/1.mp3'), isNotNull);
  });

  test('a download cut off halfway is played as if it were whole', () async {
    final base = await tempAudioDir();
    final left = File('${base.path}/audio/Husary_096001.mp3.123.part')
      ..createSync(recursive: true)
      ..writeAsBytesSync([0]);

    final cache = await AudioCache.beside(base.path);
    expect(cache.cached('Husary/096001.mp3'), isNull);
    expect(left.existsSync(), isFalse, reason: 'nothing will finish it');
  });

  test('a word with a recording of its own but no timing looks playable in '
      "the reciter's voice, and a press on it is silent", () async {
    // 3:179's seventh word: quran.com has it alone, the aligner never timed it.
    final tracks = await tracksFor(db, [3179]);
    expect(tracks.single.wordFiles, contains(3179007));
    final cache = AudioCache(await tempAudioDir(), fetch: RadioOff().call);

    expect(
      SetAudio(cache: cache, tracks: tracks).speakable,
      isNot(contains(3179007)),
    );
    expect(
      SetAudio(cache: cache, tracks: tracks, wordByWord: true).speakable,
      contains(3179007),
    );
  });

  test('pausing the bar while a streamed aya is still loading starts the sūra '
      'over from its first aya', () async {
    final players = FakePlayers();
    JustAudioPlatform.instance = players;
    final recitation = Recitation(cache: await cacheHolding(firstSet));
    await recitation.carry(await alAlaq(), title: 'Al-ʿAlaq');

    // The bar names the recitation before the player has loaded anything.
    unawaited(recitation.playFrom(96015001));
    // A few microtasks: past the bar being named, short of the load's end.
    for (var i = 0; i < 3; i++) {
      await Future<void>.value();
    }
    expect(recitation.sounding.value, isNotNull);
    expect(recitation.playing.value, isFalse);
    await recitation.toggle();
    await pumpEventQueue();

    expect(recitation.playing.value, isFalse);
    expect(recitation.sounding.value, isNull);
    expect(
      players.players
          .expand((p) => p.loaded)
          .where((l) => l.contains('096001')),
      isEmpty,
      reason: 'nothing was started from the top of the sūra',
    );
  });

  test('a sweep trips over a download still being written', () async {
    final dir = await tempAudioDir();
    final writing = File('${dir.path}/Husary_096019.mp3.1.part')
      ..writeAsBytesSync(List.filled(4096, 0));
    final cache = AudioCache(dir, fetch: FakeCdn().call, capBytes: 1024);

    await cache.prefetch(['a/1.mp3', 'a/2.mp3']);
    expect(writing.existsSync(), isTrue, reason: 'it is no one\'s file yet');
  });
}
