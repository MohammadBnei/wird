import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:sqflite/sqflite.dart';

import 'sets.dart';

/// `ayah_audio.rel_path` is relative on purpose: the reciter's files can move
/// to another host without an App Store release. This is the bundled default,
/// which server config overrides.
const defaultAudioOrigin = 'https://audio-cdn.tarteel.ai/quran/husary/';

/// The whole recitation is roughly 0.9 GB at ~150 KB an aya, so this cap
/// evicts on nearly every set. The set being studied is pinned, so the file
/// the reader is about to hear is never the one thrown away.
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

/// The recitation files screen 1a keeps on disk: the set being studied and
/// the set after it. Pinning only the current set leaves the cap free to
/// evict the very set the reader is about to be handed.
Future<List<String>> pathsToKeep(
  Database db,
  ReadingOrder order,
  StudySet current,
) async {
  final currentIds = [for (final aya in current.ayas) aya.id];
  final ahead = await nextSet(db, order, alsoUnderstood: currentIds.toSet());
  final tracks = await tracksFor(db, [
    ...currentIds,
    if (ahead != null) for (final aya in ahead.ayas) aya.id,
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
  static Future<AudioCache> beside(String databasesPath, {String? origin}) async {
    final dir = Directory('$databasesPath/audio');
    await dir.create(recursive: true);
    return AudioCache(dir, origin: origin ?? defaultAudioOrigin);
  }

  final Directory dir;
  final String origin;
  final int capBytes;
  final FetchBytes _fetch;
  final _pinned = <String>{};

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
    _pinned
      ..clear()
      ..addAll(relPaths.map(_name));
    await dir.create(recursive: true);
    final now = DateTime.now();
    for (final rel in relPaths) {
      final file = fileFor(rel);
      if (file.existsSync()) {
        file.setLastModifiedSync(now);
        continue;
      }
      try {
        final body = await _fetch('$origin${_name(rel)}');
        if (body.isNotEmpty) await file.writeAsBytes(body, flush: true);
      } on Exception {
        continue;
      }
    }
    _evict();
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
      for (final track in tracks) AudioSource.file(cache.fileFor(track.relPath).path),
    ]);
    _listen(player);
    playing.value = true;
    await player.play();
    playing.value = false;
    currentWordId.value = null;
  }

  /// Plays one word out of its aya's file. False means that file was never
  /// downloaded: the caller shows the transliteration, and nothing spins.
  Future<bool> playWord(int wordId) async {
    final found = locate(tracks, wordId);
    if (found == null) return false;
    final file = cache.cached(found.track.relPath);
    if (file == null) return false;
    final player = _player ??= AudioPlayer();
    await player.setAudioSource(AudioSource.file(file.path));
    await player.setClip(
      start: clipStart(found.span.startMs),
      end: Duration(milliseconds: found.span.endMs),
    );
    currentWordId.value = wordId;
    playing.value = true;
    await player.play();
    playing.value = false;
    currentWordId.value = null;
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
