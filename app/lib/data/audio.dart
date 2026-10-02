import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:sqflite/sqflite.dart';


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

/// How many ayas from the open one screen 1a keeps on disk, so a reader who
/// loses the network still hears the next stretch of the sūra.
///
/// ponytail: a fixed count, not a byte budget. Ten of al-Baqarah's longest
/// ayas in the heaviest voice are still a small slice of [audioCacheBytes];
/// make it a budget if a reciter ever brings files big enough to matter.
const aheadAyas = 10;

/// The files kept on disk around [ayahId]: the aya and the [aheadAyas] after
/// it. A reader who hears words alone gets the open aya's words first, since
/// a long press there is what they are about to do.
List<String> windowPaths(
  List<AyaTrack> tracks,
  int ayahId, {
  bool wordByWord = false,
}) {
  final from = tracks.indexWhere((t) => t.ayahId == ayahId);
  final window = tracks.skip(from < 0 ? 0 : from).take(aheadAyas).toList();
  return [
    if (wordByWord && window.isNotEmpty) ...window.first.wordFiles.values,
    for (final track in window) track.relPath,
    if (wordByWord)
      for (final track in window.skip(1)) ...track.wordFiles.values,
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
    _dropUnfinished(dir);
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

  /// A download cut off by the app being killed leaves its `.part` behind.
  /// Nothing will ever finish it, and it holds its share of the cap.
  static void _dropUnfinished(Directory dir) {
    for (final file in dir.listSync().whereType<File>()) {
      if (file.path.endsWith('.part')) file.deleteSync();
    }
  }

  final Directory dir;
  final String origin;
  final int capBytes;
  final FetchBytes _fetch;
  final _pinned = <String>{};

  /// The files the player has loaded. A recitation started from the top of a
  /// long sūra holds files the window around the open aya does not, and
  /// evicting one of them ends the recitation the moment it reaches it.
  final _held = <String>{};

  void hold(Iterable<String> relPaths) => _held
    ..clear()
    ..addAll(relPaths.map(_name));

  /// Which prefetch owns the pins. A download outlives the screen state that
  /// asked for it — a reader who jumps to an aya and moves on again leaves one
  /// in flight — and the pins it set are no longer what is on screen.
  int _request = 0;

  /// One flat directory, the reciter's folder folded into the name: two
  /// reciters' copies of one aya never share a file, and the sweep and the
  /// pins see every file without walking a tree.
  String _name(String relPath) => relPath.replaceAll('/', '_');

  File fileFor(String relPath) => File('${dir.path}/${_name(relPath)}');

  /// A word's own recording lives on its own host; everything else is a
  /// reciter's folder on [origin].
  String urlFor(String relPath) => relPath.startsWith('wbw/')
      ? '$wordAudioOrigin$relPath'
      : '$origin$relPath';

  /// The file if it is already on disk, and never a request.
  File? cached(String relPath) {
    final file = fileFor(relPath);
    return file.existsSync() ? file : null;
  }

  /// What the player is handed: the file when it is on disk, else the public
  /// URL, fetched by the player as it plays — the same runtime fetch as a
  /// download, with nothing kept. So a reader can hear any aya of the sūra
  /// without waiting for it to land.
  AudioSource sourceFor(String relPath) => switch (cached(relPath)) {
    final file? => AudioSource.file(file.path),
    null => AudioSource.uri(Uri.parse(urlFor(relPath))),
  };

  /// Writes [body] under a name nothing reads, then renames it into place.
  /// A file written in place exists, and so counts as cached, from its first
  /// byte. The suffix keeps two writers of one file — a sample and a
  /// prefetch — from writing into each other.
  Future<void> _write(File file, List<int> body) async {
    final part = File(
      '${file.path}.${DateTime.now().microsecondsSinceEpoch}.part',
    );
    await part.writeAsBytes(body, flush: true);
    await part.rename(file.path);
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
      await _write(file, body);
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
        await _write(file, body);
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
      final name = file.uri.pathSegments.last;
      if (_pinned.contains(name) || _held.contains(name)) continue;
      total -= file.lengthSync();
      file.deleteSync();
    }
  }
}

/// The recitation of one sūra: plays it from any word or aya, says which word
/// is sounding, and speaks a single word on demand.
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

  /// There is a recitation to play. Whatever is not on disk is fetched by the
  /// player as it plays, so this no longer waits on a download.
  bool get ready => tracks.isNotEmpty;

  /// Whether the set's own playback was paused and can carry on from where it
  /// stopped. A word played since, or the set reaching its end, clears it.
  bool get paused => _paused;
  var _paused = false;

  /// Pauses, or resumes a paused recitation, or else recites the sūra from
  /// its start.
  ///
  /// Pausing used to be stopping: the next press loaded the set again and
  /// started it from its first aya, so a reader who paused to look at a word
  /// lost their place in the recitation. A pause now keeps the player where it
  /// is, and the next press carries on.
  Future<void> toggle() async {
    final player = _player;
    if (playing.value) {
      playing.value = false;
      // Only the set's own playback has a place to resume from; a word paused
      // here is simply over.
      _paused = _setTurn == _turn;
      await player?.pause();
      return;
    }
    if (_paused && _setTurn == _turn && player != null) {
      _paused = false;
      await _run(_turn, (player) async {
        playing.value = true;
        await player.play();
      });
      return;
    }
    await playFrom(null);
  }

  /// Recites from [wordId] to the end of the sūra, or from its first aya when
  /// null. A recitation that stopped at the end of the ayas around the open
  /// word was a recitation that stopped in the middle of the sūra.
  Future<bool> playFrom(int? wordId) async {
    final at = wordId == null ? null : locate(tracks, wordId);
    // A word the timings miss still has an aya: the recitation starts there,
    // not back at the top of the sūra.
    final first = at != null
        ? tracks.indexOf(at.track)
        : wordId == null
        ? 0
        : tracks.indexWhere((t) => t.ayahId == wordId ~/ 1000);
    if (first < 0) return false;
    return _recite(
      first,
      tracks.length - first,
      at == null ? null : clipStart(at.span.startMs),
    );
  }

  /// Plays one aya of the set alone, from its start to its end, with its
  /// words lit as it goes. False when the set has no such aya.
  Future<bool> playAya(int ayahId) async {
    final index = tracks.indexWhere((t) => t.ayahId == ayahId);
    return index >= 0 && await _recite(index, 1, null);
  }

  /// Which track the player's first source is: 0 for the whole set, the aya's
  /// own index when one aya plays alone, so the highlight reads the right
  /// timings.
  var _first = 0;

  Future<bool> _recite(int first, int count, Duration? at) async {
    if (count <= 0) return false;
    _first = first;
    final turn = _setTurn = _take();
    final paths = [
      for (final track in tracks.skip(first).take(count)) track.relPath,
    ];
    return _run(turn, (player) async {
      // A player that reached the end of an aya still reports itself playing,
      // and its next play() answers at once: the aya tapped "again" would
      // sound with the bar and the highlight already gone. playWord pauses
      // first for the same reason.
      await player.pause();
      // Positions stay those of the file, not of a clip, so the highlight's
      // timings hold from the first word.
      await player.setAudioSources([
        for (final path in paths) cache.sourceFor(path),
      ], initialPosition: at);
      _listen(player);
      if (turn != _turn) return;
      cache.hold(paths);
      playing.value = true;
      await player.play();
    });
  }

  /// A new playback's turn. Whatever was paused is replaced by it, so there
  /// is nothing left to resume.
  int _take() {
    _paused = false;
    return ++_turn;
  }

  /// Runs one playback to its end and settles the transport after it, for
  /// every kind of playback alike.
  ///
  /// Stopping it while the files are still being opened is not an error: the
  /// player throws `Loading interrupted` into whoever started the play, and
  /// that caller is the screen. Nothing in this app may spin or shout, least
  /// of all over a reader who pressed stop, so an interrupted play is silence.
  ///
  /// An aya that cannot be fetched — the network dropped past the ayas on
  /// disk — reaches only the player's error stream, and play() would go on
  /// waiting with the bar lit over silence. The error pauses it instead,
  /// which ends the wait, and the playback answers false like a refused one.
  Future<bool> _run(
    int turn,
    Future<void> Function(AudioPlayer player) start,
  ) async {
    final player = _player ??= AudioPlayer();
    var failed = false;
    final errors = player.errorStream.listen((_) {
      failed = true;
      if (turn == _turn) unawaited(player.pause().catchError((_) {}));
    });
    try {
      await start(player);
      return !failed;
    } on Exception {
      // A platform that will not take the source, or a load the reader cut
      // short. The bar goes back to dark and the screen says nothing.
      return false;
    } finally {
      await errors.cancel();
      // A pause also ends play()'s wait; it keeps the word lit and the place.
      if (turn == _turn && !_paused) {
        playing.value = false;
        currentWordId.value = null;
        cache.hold(const []);
      }
    }
  }

  /// Ends a paused set, so the next press starts it again from its start.
  Future<void> stop() async {
    // Taking the turn keeps a load still in flight from starting to play
    // after the reader pressed stop.
    _take();
    playing.value = false;
    currentWordId.value = null;
    cache.hold(const []);
    await _player?.stop();
  }

  /// The words that answer a press: every word of the sūra, since whatever is
  /// not on disk is fetched as it plays. Empty only for a reciter this build
  /// has no recitation for.
  Set<int> get speakable => _speakable ??= {
    for (final track in tracks) ...[
      for (final span in track.segments) span.wordId,
      ...track.wordFiles.keys,
    ],
  };
  Set<int>? _speakable;

  /// The word's own recording if the reader asked for those, else null.
  String? _alone(int wordId) {
    if (!wordByWord) return null;
    for (final track in tracks) {
      if (track.wordFiles[wordId] case final path?) return path;
    }
    return null;
  }

  /// Plays one word: its own recording when the reader chose those, else its
  /// stretch of its aya's file. False means the sūra has no recording of it,
  /// or the platform refused it: the caller shows the transliteration, and
  /// nothing spins.
  ///
  /// What is on disk comes first. A reader offline whose word was never
  /// downloaded alone, but whose aya was, hears the reciter's stretch of it
  /// rather than nothing; online, the word alone is fetched as it plays.
  ///
  /// A tap is the gesture now, so the reader's next word arrives while this
  /// one is still sounding — `play()` answers when the clip ENDS, not when it
  /// starts. The word already sounding is stopped first, so its future is
  /// settled before the next word takes the highlight, and taking the turn
  /// keeps a superseded word, and the set's own position stream, from writing
  /// over the word that superseded them.
  Future<bool> playWord(int wordId) async {
    final alone = _alone(wordId);
    final at = locate(tracks, wordId);
    final stretch =
        alone == null ||
        (cache.cached(alone) == null &&
            at != null &&
            cache.cached(at.track.relPath) != null);
    final found = stretch ? at : null;
    final path = found?.track.relPath ?? alone;
    if (path == null) return false;
    final turn = _take();
    return _run(turn, (player) async {
      await player.pause();
      await player.setAudioSource(cache.sourceFor(path));
      // A word's own file is the word, start to end; only a stretch of the
      // reciter's aya needs cutting out.
      if (found != null) {
        await player.setClip(
          start: clipStart(found.span.startMs),
          end: Duration(milliseconds: found.span.endMs),
        );
      }
      if (turn != _turn) return;
      cache.hold([path]);
      currentWordId.value = wordId;
      playing.value = true;
      await player.play();
    });
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
    cache.hold(const []);
    try {
      await _positions?.cancel();
      await _player?.dispose();
    } catch (_) {
      // ponytail: swallows any throw from a player being discarded; narrow
      // it to just_audio's StateError if a real failure ever hides here.
    }
  }
}
