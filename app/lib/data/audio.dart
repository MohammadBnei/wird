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
/// `ayah_audio.rel_path` is relative on purpose: the reciter's files can move
/// to another host without an App Store release. This is the bundled default,
/// which server config overrides. everyayah.com's `Husary_Muallim_128kbps` is
/// the same recording cpfair/quran-align measured, so the bundled word timings
/// belong to these files and not to a re-encode of them.
const defaultAudioOrigin = 'https://everyayah.com/data/Husary_Muallim_128kbps/';

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
  });

  final int ayahId;
  final String relPath;
  final List<WordSpan> segments;
}

/// Reads the audio the set needs: one file per aya, and the word timings that
/// drive the highlight.
Future<List<AyaTrack>> tracksFor(Database db, List<int> ayahIds) async {
  if (ayahIds.isEmpty) return const [];
  final marks = List.filled(ayahIds.length, '?').join(',');
  final files = await db.rawQuery(
    'SELECT ayah_id, rel_path FROM ayah_audio WHERE ayah_id IN ($marks)',
    ayahIds,
  );
  final paths = {
    for (final f in files) f['ayah_id']! as int: f['rel_path']! as String,
  };
  final spans = await db.rawQuery(
    '''SELECT w.ayah_id, s.word_id, s.start_ms, s.end_ms
         FROM word_segments s
         JOIN words w ON w.id = s.word_id
        WHERE w.ayah_id IN ($marks)
        ORDER BY w.ayah_id, s.start_ms''',
    ayahIds,
  );
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
        AyaTrack(ayahId: id, relPath: rel, segments: byAya[id] ?? const []),
  ];
}

/// The recitation files screen 1a keeps on disk: the set being studied and,
/// while the reader is [onTheWalk], the set after it. Pinning only the current
/// set leaves the cap free to evict the very set the reader is about to be
/// handed.
Future<List<String>> pathsToKeep(
  Database db,
  ReadingOrder order,
  StudySet current, {
  bool onTheWalk = true,
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
  ]);
  return [for (final track in tracks) track.relPath];
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
    return AudioCache(dir, origin: origin ?? defaultAudioOrigin);
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

  /// The origin names the reciter's own directory and the corpus path carries
  /// the reciter as a folder, so only the file name joins the two.
  String _name(String relPath) => relPath.split('/').last;

  File fileFor(String relPath) => File('${dir.path}/${_name(relPath)}');

  /// The file if it is already on disk, and never a request. A long press has
  /// to answer at once or not at all.
  File? cached(String relPath) {
    final file = fileFor(relPath);
    return file.existsSync() ? file : null;
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
        final body = await _fetch('$origin${_name(rel)}');
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
  SetAudio({required this.cache, required this.tracks});

  final AudioCache cache;
  final List<AyaTrack> tracks;

  final currentWordId = ValueNotifier<int?>(null);
  final playing = ValueNotifier<bool>(false);

  /// The player is built on the first play, so a screen that is only read
  /// never touches an audio platform channel.
  AudioPlayer? _player;
  StreamSubscription<Duration>? _positions;
  var _speakable = <int>{};
  DateTime? _speakableAt;
  var _speaking = 0;

  /// Every aya of the set is on disk, so play will not reach for the network.
  bool get ready =>
      tracks.isNotEmpty && tracks.every((t) => cache.cached(t.relPath) != null);

  Future<void> toggle() async {
    if (playing.value) {
      playing.value = false;
      await _player?.pause();
      return;
    }
    if (!ready) return;
    final player = _player ??= AudioPlayer();
    await player.setAudioSources([
      for (final track in tracks)
        AudioSource.file(cache.fileFor(track.relPath).path),
    ]);
    _listen(player);
    playing.value = true;
    await player.play();
    playing.value = false;
    currentWordId.value = null;
  }

  /// The words that would sound if the reader tapped them: every word of an
  /// aya whose file is on disk. Held against the cache's revision rather than
  /// recomputed, because `cached` is an `existsSync` and the word row rebuilds
  /// every 40 ms while the set plays.
  Set<int> get speakable {
    if (_speakableAt != cache.revision) {
      _speakableAt = cache.revision;
      _speakable = {
        for (final track in tracks)
          if (cache.cached(track.relPath) != null)
            for (final span in track.segments) span.wordId,
      };
    }
    return _speakable;
  }

  /// Plays one word out of its aya's file. False means that file was never
  /// downloaded, or the platform refused it: the caller shows the
  /// transliteration, and nothing spins.
  ///
  /// A tap is the gesture now, so the reader's next word arrives while this
  /// one is still sounding — `play()` answers when the clip ENDS, not when it
  /// starts. The word already sounding is stopped first, so its future is
  /// settled before the next word takes the highlight, and the token keeps a
  /// superseded word from clearing the highlight of the word that superseded
  /// it.
  Future<bool> playWord(int wordId) async {
    final found = locate(tracks, wordId);
    if (found == null) return false;
    final file = cache.cached(found.track.relPath);
    if (file == null) return false;
    final token = ++_speaking;
    try {
      final player = _player ??= AudioPlayer();
      await player.pause();
      await player.setAudioSource(AudioSource.file(file.path));
      await player.setClip(
        start: clipStart(found.span.startMs),
        end: Duration(milliseconds: found.span.endMs),
      );
      if (token != _speaking) return true;
      currentWordId.value = wordId;
      playing.value = true;
      await player.play();
    } on Exception {
      // A platform that refuses the clip is the silent case, not a crash
      // under the reader's finger.
      return false;
    } finally {
      if (token == _speaking) {
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
        .listen(
          (position) => currentWordId.value = wordAt(
            tracks,
            player.currentIndex ?? 0,
            position.inMilliseconds,
          ),
        );
  }

  /// ponytail: the two notifiers are left alive. A screen swapping one set's
  /// audio for the next still has builders listening to the old pair for the
  /// rest of the frame, and two dead ValueNotifiers cost nothing.
  Future<void> dispose() async {
    await _positions?.cancel();
    await _player?.dispose();
  }
}
