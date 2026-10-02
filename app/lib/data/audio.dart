import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:sqflite/sqflite.dart';

import 'sets.dart';

/// RUNTIME FETCH ONLY. No recitation of the Qur'an was found that Wird may
/// redistribute: every complete per-aya recording is personal-use-only, silent
/// on terms, or tagged by somebody who does not hold the master. So the device
/// asks a third party for a public URL, the way a browser loads an image, and
/// Wird neither bundles the audio nor serves it from an origin of its own.
///
/// A future mirror is the thing this constrains. Copying these files onto
/// Wird's own host is redistribution, and nobody has granted it — under the
/// one set of terms actually written down, Quran Foundation's, it is named and
/// forbidden. See the audio rows in data/SOURCES.md before moving this.
///
/// `ayah_audio.rel_path` is a bare file name on purpose, the same in every
/// reciter's folder: the host and the folder are config here, so the files can
/// move to another host without a corpus rebuild — an App Store release, since
/// the corpus is bundled.
const defaultAudioOrigin = 'https://everyayah.com/data/';

/// The reciter a fresh install hears, and the one a stored choice falls back to
/// when a later corpus no longer carries it.
const defaultReciter = 'husary-muallim';

/// Each reciter's folder on [defaultAudioOrigin]. Each is the exact recording
/// cpfair/quran-align measured, so the bundled word timings belong to these
/// files and not to a re-encode of them: Husary and Abdul Basit are the 64 kbps
/// folders because those are the ones aligned. A corpus slug missing here has
/// no files to play, and a test holds the two lists together.
const reciterFolders = {
  'husary-muallim': 'Husary_Muallim_128kbps',
  'husary': 'Husary_64kbps',
  'alafasy': 'Alafasy_128kbps',
  'abdul-basit-murattal': 'Abdul_Basit_Murattal_64kbps',
  'shaatree': 'Abu_Bakr_Ash-Shaatree_128kbps',
  'hani-rifai': 'Hani_Rifai_192kbps',
};

/// The aya a reciter is heard by before the reader picks them, 1:1: the
/// basmala, short, and the same words in every voice so the voices are what
/// differ. Named the way `ayah_audio.rel_path` names it in every folder.
const sampleFile = '001001.mp3';

/// Where a word spoken on its own is fetched from: quran.com's word-by-word
/// recordings, one voice for every word, at the path `words.wbw_path` names.
/// Fetched at playback and held in the same capped cache as the recitation,
/// never bundled; ADR 0023 records the terms this sits under.
const wordAudioOrigin = 'https://audio.qurancdn.com/';

/// The whole recitation is 2.75 GB at ~442 KB an aya, so this cap holds about
/// 450 ayas and evicts on nearly every set. The set being studied is pinned,
/// so the file the reader is about to hear is never the one thrown away.
///
/// The cap is also what keeps this a cache. A fetch-at-playback design stays
/// honest while the files on disk are a performance artifact of playing them;
/// an unbounded one is a copy of the recitation assembled on the user's disk,
/// which is the act no licence here permits.
const audioCacheBytes = 200 * 1024 * 1024;

/// An MP3 frame is about 26 ms and a seek lands on a frame boundary, so a
/// short word starts a fraction late and loses its first consonant. Open the
/// clip one frame early instead.
///
/// ponytail: one figure for both platforms, taken from the frame size rather
/// than from a device. Split it per `Platform` the first time an iPhone and a
/// Pixel disagree on the same recording.
const seekCalibration = Duration(milliseconds: 26);

/// Screen 1a must highlight the word being recited within ~80 ms of the
/// audio, so the position is sampled at half of that.
const highlightPeriod = Duration(milliseconds: 40);

/// Where one word falls inside its aya's file.
typedef WordSpan = ({int wordId, int startMs, int endMs});

/// One aya of the recitation: the file it lives in, and the words inside it.
class AyaTrack {
  const AyaTrack({
    required this.ayahId,
    required this.relPath,
    required this.segments,
    this.wordFiles = const {},
  });

  final int ayahId;
  final String relPath;
  final List<WordSpan> segments;

  /// Each word's own recording, spoken alone, by word id. A word missing here
  /// has none and is cut out of [relPath] instead.
  final Map<int, String> wordFiles;
}

/// Reads the audio the set needs in [reciter]'s voice: one file per aya, and
/// the word timings that drive the highlight. Empty for a reciter this build
/// has no folder for, and on a corpus from before there was a choice of
/// reciter — kept when its upgrade failed — whose tables this cannot read.
Future<List<AyaTrack>> tracksFor(
  Database db,
  List<int> ayahIds, {
  String reciter = defaultReciter,
}) async {
  final folder = reciterFolders[reciter];
  if (ayahIds.isEmpty || folder == null) return const [];
  final marks = List.filled(ayahIds.length, '?').join(',');
  final files = await db.rawQuery(
    'SELECT ayah_id, rel_path FROM ayah_audio WHERE ayah_id IN ($marks)',
    ayahIds,
  );
  final paths = {
    for (final f in files)
      f['ayah_id']! as int: '$folder/${f['rel_path']! as String}',
  };
  final List<Map<String, Object?>> spans, alone;
  try {
    spans = await db.rawQuery(
      '''SELECT w.ayah_id, s.word_id, s.start_ms, s.end_ms
         FROM word_segments s
         JOIN recitations r ON r.id = s.recitation_id
         JOIN words w ON w.id = s.word_id
        WHERE r.slug = ? AND w.ayah_id IN ($marks)
        ORDER BY w.ayah_id, s.start_ms''',
      [reciter, ...ayahIds],
    );
    alone = await db.rawQuery('''SELECT ayah_id, id, wbw_path FROM words
        WHERE wbw_path IS NOT NULL AND ayah_id IN ($marks)''', ayahIds);
  } on DatabaseException {
    return const [];
  }
  final wordFiles = <int, Map<int, String>>{};
  for (final w in alone) {
    (wordFiles[w['ayah_id']! as int] ??= {})[w['id']! as int] =
        w['wbw_path']! as String;
  }
  final byAya = <int, List<WordSpan>>{};
  for (final s in spans) {
    (byAya[s['ayah_id']! as int] ??= []).add((
      wordId: s['word_id']! as int,
      startMs: s['start_ms']! as int,
      endMs: s['end_ms']! as int,
    ));
  }
  return [
    for (final id in ayahIds)
      if (paths[id] case final rel?)
        AyaTrack(
          ayahId: id,
          relPath: rel,
          segments: byAya[id] ?? const [],
          wordFiles: wordFiles[id] ?? const {},
        ),
  ];
}

/// The recitation files screen 1a keeps on disk: the set being studied and,
/// while the reader is [onTheWalk], the set after it. Pinning only the current
/// set leaves the cap free to evict the very set the reader is about to be
/// handed. With [wordByWord], each word's own recording too, so a tapped word
/// sounds offline in the voice the reader chose for it.
Future<List<String>> pathsToKeep(
  Database db,
  ReadingOrder order,
  StudySet current, {
  bool onTheWalk = true,
  String reciter = defaultReciter,
  bool wordByWord = false,
}) async {
  final currentIds = [for (final aya in current.ayas) aya.id];
  // An aya the reader asked for has no set after it. [nextSet] does not know
  // the reader went to it and would answer with the WALK's next set, so every
  // jump would download a set nobody is looking at — and unpin the aya that is
  // on screen to make room for it.
  final ahead = onTheWalk
      ? await nextSet(db, order, alsoUnderstood: currentIds.toSet())
      : null;
  final tracks = await tracksFor(db, [
    ...currentIds,
    if (ahead != null)
      for (final aya in ahead.ayas) aya.id,
  ], reciter: reciter);
  return [
    for (final track in tracks) track.relPath,
    if (wordByWord)
      for (final track in tracks) ...track.wordFiles.values,
  ];
}

/// The word sounding at [ms] in the track at [index].
///
/// Between two words the previous one stays lit rather than blinking off, and
/// an aya whose segments overlap — 141 of them do — never hands the highlight
/// backwards.
int? wordAt(List<AyaTrack> tracks, int index, int ms) {
  if (index < 0 || index >= tracks.length) return null;
  int? held;
  for (final span in tracks[index].segments) {
    if (span.startMs > ms) break;
    held = span.wordId;
  }
  return held;
}

/// The file a word is spoken in, and where inside it.
({AyaTrack track, WordSpan span})? locate(List<AyaTrack> tracks, int wordId) {
  for (final track in tracks) {
    for (final span in track.segments) {
      if (span.wordId == wordId) return (track: track, span: span);
    }
  }
  return null;
}

/// Where a word's clip opens: one MP3 frame before the word starts, and never
/// before the file does.
Duration clipStart(int startMs) {
  final start = Duration(milliseconds: startMs) - seekCalibration;
  return start.isNegative ? Duration.zero : start;
}

/// Downloads one file, or throws. Screen tests hand in a closure that
/// refuses, so "plays with the radio off" cannot pass on a machine that still
/// has one.
typedef FetchBytes = Future<List<int>> Function(String url);

final _dio = Dio();

Future<List<int>> _download(String url) async {
  final response = await _dio.get<List<int>>(
    url,
    options: Options(responseType: ResponseType.bytes),
  );
  return response.data ?? const [];
}

/// The downloaded recitation files, capped and pinned.
class AudioCache {
  AudioCache(
    this.dir, {
    this.origin = defaultAudioOrigin,
    this.capBytes = audioCacheBytes,
    FetchBytes? fetch,
  }) : _fetch = fetch ?? _download;

  /// ponytail: the audio sits beside the database rather than behind
  /// path_provider, which is not in the stack table. On iOS that directory is
  /// the documents directory already.
  static Future<AudioCache> beside(
    String databasesPath, {
    String? origin,
  }) async {
    final dir = Directory('$databasesPath/audio');
    await dir.create(recursive: true);
    _dropUnnamedReciter(dir);
    return AudioCache(dir, origin: origin ?? defaultAudioOrigin);
  }

  /// Files cached before there was a choice of reciter are named by aya alone,
  /// `001001.mp3`, and nothing asks for that name any more. They would hold
  /// their share of the cap until evicted; this frees it at once instead.
  static void _dropUnnamedReciter(Directory dir) {
    final bare = RegExp(r'^\d{6}\.mp3$');
    for (final file in dir.listSync().whereType<File>()) {
      if (bare.hasMatch(file.uri.pathSegments.last)) file.deleteSync();
    }
  }

  final Directory dir;
  final String origin;
  final int capBytes;
  final FetchBytes _fetch;
  final _pinned = <String>{};

  /// Which prefetch owns the pins. A download outlives the screen state that
  /// asked for it — a reader who jumps to an aya and moves on again leaves one
  /// in flight — and the pins it set are no longer what is on screen.
  int _request = 0;

  /// Changes whenever a file arrives in the cache or leaves it, so a screen
  /// can hold an answer about what is downloaded instead of asking the
  /// filesystem once per word per frame. The directory's own timestamp rather
  /// than a counter, because the answer has to follow the disk however the
  /// file got there.
  DateTime get revision =>
      dir.existsSync() ? dir.statSync().modified : DateTime.utc(0);

  /// One flat directory, the reciter's folder folded into the name: two
  /// reciters' copies of one aya never share a file, and the sweep, the pins
  /// and [revision] all see every file without walking a tree.
  String _name(String relPath) => relPath.replaceAll('/', '_');

  File fileFor(String relPath) => File('${dir.path}/${_name(relPath)}');

  /// A word's own recording lives on its own host; everything else is a
  /// reciter's folder on [origin].
  String urlFor(String relPath) => relPath.startsWith('wbw/')
      ? '$wordAudioOrigin$relPath'
      : '$origin$relPath';

  /// The file if it is already on disk, and never a request. A long press has
  /// to answer at once or not at all.
  File? cached(String relPath) {
    final file = fileFor(relPath);
    return file.existsSync() ? file : null;
  }

  /// One file, from disk or else fetched, without touching the pins: a sample
  /// heard in the settings must not unpin the set the reader is about to
  /// pray. Null offline. Not swept here; the next [prefetch] sweeps it like
  /// anything else unpinned.
  Future<File?> fetchOne(String relPath) async {
    final file = fileFor(relPath);
    if (file.existsSync()) return file;
    try {
      final body = await _fetch(urlFor(relPath));
      if (body.isEmpty) return null;
      await dir.create(recursive: true);
      await file.writeAsBytes(body, flush: true);
      return file;
    } on Exception {
      return null;
    }
  }

  /// Downloads what the set needs, pins it against eviction, then trims the
  /// cache back under the cap. Going offline mid-set leaves the rest of the
  /// set unplayable; it never throws into the screen.
  Future<void> prefetch(Iterable<String> relPaths) async {
    final request = ++_request;
    _pinned
      ..clear()
      ..addAll(relPaths.map(_name));
    await dir.create(recursive: true);
    final now = DateTime.now();
    var written = false;
    for (final rel in relPaths) {
      // A later prefetch has taken the pins, which means the screen is showing
      // something else now. Finishing this one would download what nobody is
      // reading and then sweep away what they are.
      if (_request != request) return;
      final file = fileFor(rel);
      if (file.existsSync()) {
        file.setLastModifiedSync(now);
        continue;
      }
      try {
        final body = await _fetch(urlFor(rel));
        if (body.isEmpty) continue;
        await file.writeAsBytes(body, flush: true);
        written = true;
      } on Exception {
        continue;
      }
    }
    // Nothing was written, so the cache cannot have passed its cap and there is
    // nothing to sweep. The sweep is synchronous file I/O over every file on
    // disk, and screen 1a prefetches on every aya the reader jumps to: without
    // this, a jump to an aya already downloaded would stat hundreds of files
    // and then delete the set the reader was walking, since only the jumped-to
    // aya is pinned by the time it runs.
    if (written && _request == request) _evict();
  }

  void _evict() {
    if (!dir.existsSync()) return;
    final files = dir.listSync().whereType<File>().toList()
      ..sort((a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()));
    var total = files.fold(0, (sum, f) => sum + f.lengthSync());
    for (final file in files) {
      if (total <= capBytes) return;
      if (_pinned.contains(file.uri.pathSegments.last)) continue;
      total -= file.lengthSync();
      file.deleteSync();
    }
  }
}

/// The recitation of one set: plays it, says which word is sounding, and
/// speaks a single word on demand.
class SetAudio {
  SetAudio({
    required this.cache,
    required this.tracks,
    this.wordByWord = false,
  });

  final AudioCache cache;
  final List<AyaTrack> tracks;

  /// Whether a tapped word plays its own recording, spoken alone, rather than
  /// the stretch of the reciter's aya it falls in. Set from the reader's
  /// choice and changed in place: the set's own recitation does not depend on
  /// it.
  bool wordByWord;

  final currentWordId = ValueNotifier<int?>(null);
  final playing = ValueNotifier<bool>(false);

  /// The player is built on the first play, so a screen that is only read
  /// never touches an audio platform channel.
  AudioPlayer? _player;
  StreamSubscription<Duration>? _positions;
  var _speakable = <int>{};
  DateTime? _speakableAt;

  /// Which playback owns the transport: every word probe takes a turn, and so
  /// does the set's own play. One player serves both, and neither answers when
  /// it starts — a word clip answers when it ends, and the position stream is
  /// still delivering events from the playback before it — so without a turn
  /// the one that was superseded writes over the one that superseded it.
  var _turn = 0;

  /// The turn the set's own playback took. The position stream lights a word
  /// only while that playback still holds the transport, so a stale event
  /// cannot light a word the reader is not on.
  var _setTurn = -1;

  /// Every aya of the set is on disk, so play will not reach for the network.
  bool get ready =>
      tracks.isNotEmpty && tracks.every((t) => cache.cached(t.relPath) != null);

  /// Whether the set's own playback was paused and can carry on from where it
  /// stopped. A word played since, or the set reaching its end, clears it.
  bool get paused => _paused;
  var _paused = false;

  /// Plays, pauses or resumes the whole set.
  ///
  /// Pausing used to be stopping: the next press loaded the set again and
  /// started it from its first aya, so a reader who paused to look at a word
  /// lost their place in the recitation. A pause now keeps the player where it
  /// is, and the next press carries on.
  ///
  /// Stopping it while the files are still being opened is not an error: the
  /// player throws `Loading interrupted` into whoever started the play, and
  /// that caller is the screen. Nothing in this app may spin or shout, least
  /// of all over a reader who pressed stop, so an interrupted play is silence.
  Future<void> toggle() async {
    final player = _player;
    if (playing.value) {
      playing.value = false;
      _paused = true;
      await player?.pause();
      return;
    }
    // A paused aya resumes even while the rest of the set is downloading.
    if (_paused && _setTurn == _turn && player != null) {
      _paused = false;
      playing.value = true;
      try {
        await player.play();
      } on Exception {
        // As below: silence, never a shout.
      } finally {
        if (_setTurn == _turn && !_paused) {
          playing.value = false;
          currentWordId.value = null;
        }
      }
      return;
    }
    if (!ready) return;
    await _play(0, tracks.length);
  }

  /// Plays one aya of the set alone, from its start to its end, with its
  /// words lit as it goes. False when its file is not on the phone.
  Future<bool> playAya(int ayahId) async {
    final index = tracks.indexWhere((t) => t.ayahId == ayahId);
    if (index < 0 || cache.cached(tracks[index].relPath) == null) return false;
    if (playing.value) await _player?.pause();
    await _play(index, 1);
    return true;
  }

  /// Which track the player's first source is: 0 for the whole set, the aya's
  /// own index when one aya plays alone, so the highlight reads the right
  /// timings.
  var _first = 0;

  Future<void> _play(int first, int count) async {
    _paused = false;
    _first = first;
    final turn = _setTurn = ++_turn;
    try {
      final player = _player ??= AudioPlayer();
      await player.setAudioSources([
        for (final track in tracks.skip(first).take(count))
          AudioSource.file(cache.fileFor(track.relPath).path),
      ]);
      _listen(player);
      if (turn != _turn) return;
      playing.value = true;
      await player.play();
    } on Exception {
      // A platform that will not take the set, or a load the reader cut
      // short. The bar goes back to dark and the screen says nothing.
    } finally {
      // A pause also ends play()'s wait; it keeps the word lit and the place.
      if (turn == _turn && !_paused) {
        playing.value = false;
        currentWordId.value = null;
      }
    }
  }

  /// Ends a paused set, so the next press starts it again from its start.
  Future<void> stop() async {
    _paused = false;
    playing.value = false;
    currentWordId.value = null;
    await _player?.stop();
  }

  /// The words that would sound if the reader tapped them: every word of an
  /// aya whose file is on disk. Held against the cache's revision rather than
  /// recomputed, because `cached` is an `existsSync` and the word row rebuilds
  /// every 40 ms while the set plays.
  Set<int> get speakable {
    if (_speakableAt != cache.revision || _speakableAlone != wordByWord) {
      _speakableAt = cache.revision;
      _speakableAlone = wordByWord;
      _speakable = {
        for (final track in tracks) ...[
          if (cache.cached(track.relPath) != null)
            for (final span in track.segments) span.wordId,
          if (wordByWord)
            for (final MapEntry(key: word, value: path)
                in track.wordFiles.entries)
              if (cache.cached(path) != null) word,
        ],
      };
    }
    return _speakable;
  }

  bool? _speakableAlone;

  /// The word's own recording if the reader asked for those and it is on
  /// disk, else null.
  File? _alone(int wordId) {
    if (!wordByWord) return null;
    for (final track in tracks) {
      if (track.wordFiles[wordId] case final path?) return cache.cached(path);
    }
    return null;
  }

  /// Plays one word: its own recording when the reader chose those and it is
  /// on disk, else its stretch of its aya's file. False means neither was
  /// downloaded, or the platform refused it: the caller shows the
  /// transliteration, and nothing spins.
  ///
  /// A tap is the gesture now, so the reader's next word arrives while this
  /// one is still sounding — `play()` answers when the clip ENDS, not when it
  /// starts. The word already sounding is stopped first, so its future is
  /// settled before the next word takes the highlight, and taking the turn
  /// keeps a superseded word, and the set's own position stream, from writing
  /// over the word that superseded them.
  Future<bool> playWord(int wordId) async {
    final alone = _alone(wordId);
    final found = alone == null ? locate(tracks, wordId) : null;
    final file =
        alone ?? (found == null ? null : cache.cached(found.track.relPath));
    if (file == null) return false;
    final token = ++_turn;
    // The word replaces the set's files in the player, so there is nothing
    // left to resume.
    _paused = false;
    try {
      final player = _player ??= AudioPlayer();
      await player.pause();
      await player.setAudioSource(AudioSource.file(file.path));
      // A word's own file is the word, start to end; only a stretch of the
      // reciter's aya needs cutting out.
      if (found != null) {
        await player.setClip(
          start: clipStart(found.span.startMs),
          end: Duration(milliseconds: found.span.endMs),
        );
      }
      if (token != _turn) return true;
      currentWordId.value = wordId;
      playing.value = true;
      await player.play();
    } on Exception {
      // A platform that refuses the clip is the silent case, not a crash
      // under the reader's finger.
      return false;
    } finally {
      if (token == _turn) {
        playing.value = false;
        currentWordId.value = null;
      }
    }
    return true;
  }

  void _listen(AudioPlayer player) {
    _positions ??= player
        .createPositionStream(
          minPeriod: highlightPeriod,
          maxPeriod: highlightPeriod,
        )
        .listen((position) {
          if (_setTurn != _turn) return;
          currentWordId.value = wordAt(
            tracks,
            _first + (player.currentIndex ?? 0),
            position.inMilliseconds,
          );
        });
  }

  /// ponytail: the two notifiers are left alive. A screen swapping one set's
  /// audio for the next still has builders listening to the old pair for the
  /// rest of the frame, and two dead ValueNotifiers cost nothing.
  ///
  /// Disposing a player that was paused mid-set throws from inside just_audio
  /// (`You cannot close the subject while items are being added from
  /// addStream`). The player is being thrown away either way, and the throw
  /// used to escape into the reading screen's carry and stop it before it
  /// fetched the new reciter's files, so the set stayed in the old voice.
  Future<void> dispose() async {
    try {
      await _positions?.cancel();
      await _player?.dispose();
    } catch (_) {
      // ponytail: swallows any throw from a player being discarded; narrow
      // it to just_audio's StateError if a real failure ever hides here.
    }
  }
}
