import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:sqflite/sqflite.dart';

import 'data/audio.dart';
import 'data/db.dart';
import 'data/mic.dart';
import 'data/sets.dart';
import 'nav.dart';

/// The application: everything that outlives a screen.
///
/// Wird was seven screens and nothing above them, so anything that had to
/// survive a screen had nowhere to be. The recitation belonged to the reading
/// screen that started it, the reading order and the Arabic size were fields
/// on a State object, and the doors to the rest of the app were buttons inside
/// a collapsed panel on the one screen that happened to be the initial route.
/// This is the layer that was missing: one owner, above the navigator, for the
/// audio, the preferences and the account the identity server will bring.
class Wird extends InheritedWidget {
  const Wird({
    super.key,
    required this.db,
    required this.recitation,
    required this.prefs,
    required super.child,
  });

  final Database db;

  /// What is sounding, wherever the reader has walked to since it started.
  final Recitation recitation;

  final Prefs prefs;

  static Wird of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<Wird>()!;

  /// The three never change identity for the life of the app; a screen that
  /// wants to know when the audio or a preference moved listens to the object
  /// itself.
  @override
  bool updateShouldNotify(Wird oldWidget) => false;
}

/// What is sounding: one word, or the set.
///
/// The distinction is the whole point. A word probe and a running recitation
/// both light a word, and on a phone that was the only difference between
/// them, so a reader could not tell whether they had started a single word or
/// the whole portion.
enum Sounded { word, aya, set }

/// What is sounding, and what to call it on screen.
typedef Sounding = ({Sounded what, String label});

/// The recitation, owned by the application rather than by a screen.
///
/// What it exposes to a word row is unchanged in name from the player the
/// reading screen used to build for itself, so a row asks "am I sounding"
/// without owning anything:
///
/// * [currentWordId] — the word being recited this instant, for the highlight.
/// * [playing] — whether anything is sounding at all.
/// * [speakable] — the words that answer a press, so the row can be honest
///   about which words will sound.
/// * [playWord] — plays one word; false means the sūra has no recording of
///   it or the platform refused it.
/// * [ready], [toggle] and [playFrom] — the sūra's own play control.
///
/// What a screen above the row gets, which is new:
///
/// * [sounding] — WHICH of the two is running, and what it is called.
/// * [stop] — silence from anywhere, without knowing what started it.
///
/// The reading screen hands over the set through [carry] and then owns none of
/// it: the player survives the screen being popped, which is what lets the
/// transport in the shell show and stop a recitation from anywhere.
class Recitation {
  Recitation({AudioCache? cache}) : _given = cache;

  final AudioCache? _given;
  Future<AudioCache>? _cache;

  /// One cache for the application. A second one carries a pin list of its own
  /// and knows nothing of the first's, so it deletes the files the first
  /// pinned — which is what a cache built per screen was doing.
  Future<AudioCache> get cache => _cache ??= _given == null
      ? getDatabasesPath().then(AudioCache.beside)
      : Future.value(_given);

  final sounding = ValueNotifier<Sounding?>(null);

  SetAudio? _set;
  String _title = '';

  /// Who recites the set, named beside its title while it plays: a reader who
  /// changed reciter last week can tell from the bar who they are hearing.
  String? _voice;

  /// The reciter being sampled in the settings, or null. A player of its own,
  /// so a sample never replaces the set the reading screen loaded.
  final sampling = ValueNotifier<String?>(null);
  AudioPlayer? _sampler;

  /// The files the loaded player covers, so walking away from the reading
  /// screen and back does not rebuild it underneath a recitation that is
  /// still running. Files rather than ayas: the same ayas in another
  /// reciter's voice are another recitation.
  List<String> _covers = const [];

  /// Which playback owns the transport: a word, an aya or the set. Each
  /// takes the next number, and only the latest may clear the bar.
  int _probe = 0;

  static final _noWord = ValueNotifier<int?>(null);
  static final _silent = ValueNotifier<bool>(false);

  ValueListenable<int?> get currentWordId => _set?.currentWordId ?? _noWord;
  ValueListenable<bool> get playing => _set?.playing ?? _silent;

  bool get ready => _set?.ready ?? false;

  /// The sūra's own recitation is paused and the next press resumes it.
  bool get paused => _set?.paused ?? false;

  /// The recitation the corpus carries for the sūra being read, which is
  /// empty when it carries none.
  List<AyaTrack> get tracks => _set?.tracks ?? const [];
  Set<int> get speakable => _set?.speakable ?? const {};

  /// Hands the application the sūra the reader is on: its recitation and
  /// what to call it. The player is built here and outlives the screen that
  /// asked for it.
  ///
  /// The same sūra twice is the reader opening another of its words, or
  /// leaving the reading screen and coming back: the player stays, and so
  /// does whatever it was playing. The same sūra in a new reciter's voice is
  /// a new player.
  Future<void> carry(
    List<AyaTrack> tracks, {
    required String title,
    bool wordByWord = false,
    String? voice,
  }) async {
    _title = title;
    _voice = voice;
    final covers = [for (final track in tracks) track.relPath];
    if (_set != null && listEquals(covers, _covers)) {
      _set!.wordByWord = wordByWord;
      return;
    }
    final previous = _set;
    _set = SetAudio(cache: await cache, tracks: tracks, wordByWord: wordByWord);
    _covers = covers;
    sounding.value = null;
    await previous?.dispose();
  }

  Future<void> prefetch(Iterable<String> relPaths) async =>
      (await cache).prefetch(relPaths);

  /// Plays one word, named [label] in the bar: the transport names the word
  /// rather than leaving the reader to guess whether a whole recitation just
  /// started.
  Future<bool> playWord(int wordId, {required String label}) =>
      _own(Sounded.word, label, (set) => set.playWord(wordId));

  /// Recites the sūra from [wordId], or from its first aya when null.
  Future<bool> playFrom(int? wordId) =>
      _own(Sounded.set, _setLabel, (set) => set.playFrom(wordId));

  /// Plays one aya alone, named [label] in the bar.
  Future<bool> playAya(int ayahId, {required String label}) =>
      _own(Sounded.aya, label, (set) => set.playAya(ayahId));

  /// Pauses, or resumes what was paused. A paused recitation keeps its bar,
  /// so the reader can carry on or stop from any screen.
  Future<void> toggle() async {
    final set = _set;
    if (set == null) return;
    if (set.playing.value) return set.toggle();
    if (!set.paused) {
      await playFrom(null);
      return;
    }
    // Resuming keeps what the bar already says: the sūra, or the one aya.
    final bar = sounding.value;
    await _own(bar?.what ?? Sounded.set, bar?.label ?? _setLabel, (set) async {
      await set.toggle();
      return true;
    });
  }

  String get _setLabel => _voice == null ? _title : '$_title · $_voice';

  /// Runs one playback under the bar, for words, ayas and the sūra alike.
  ///
  /// Whoever starts something next owns the bar: a playback clears it when it
  /// ends only if nothing was started over it meanwhile. A word answers when
  /// its clip ENDS, so the reader's next word arrives while this one is still
  /// in flight; the probe carries a number for the same reason the player's
  /// own turn does — without it, the word that was superseded clears the bar
  /// of the word that superseded it.
  Future<bool> _own(
    Sounded what,
    String label,
    Future<bool> Function(SetAudio set) run,
  ) async {
    final set = _set;
    if (set == null) return false;
    await stopSample();
    // The same aya tapped twice is two plays with one label: the number, not
    // the label, says which of them still owns the bar.
    final probe = ++_probe;
    sounding.value = (what: what, label: label);
    final played = await run(set);
    if (identical(_set, set) && probe == _probe && !set.paused) {
      sounding.value = null;
    }
    return played;
  }

  /// Silence, from wherever the reader is. A word long-pressed by accident
  /// used to play to its end because the only control was on the screen that
  /// started it, and that screen had been scrolled or navigated away from.
  Future<void> stop() async {
    await stopSample();
    sounding.value = null;
    await _set?.stop();
  }

  /// Plays [reciter]'s voice on [sampleFile], or stops it if it is the one
  /// sounding. Whatever else is sounding stops first: two voices at once is
  /// noise. Offline and never fetched, it plays nothing and says nothing.
  Future<void> sample(String reciter) async {
    if (sampling.value == reciter) return stopSample();
    await stop();
    final folder = reciterFolders[reciter];
    if (folder == null) return;
    sampling.value = reciter;
    final file = await (await cache).fetchOne('$folder/$sampleFile');
    if (file == null || sampling.value != reciter) {
      if (sampling.value == reciter) sampling.value = null;
      return;
    }
    try {
      final player = _sampler ??= AudioPlayer();
      await player.setAudioSource(AudioSource.file(file.path));
      await player.play();
    } on Exception {
      // A platform that will not play it is the silent case.
    } finally {
      if (sampling.value == reciter) sampling.value = null;
    }
  }

  Future<void> stopSample() async {
    sampling.value = null;
    await _sampler?.stop();
  }
}

/// What the reader has chosen, held for the app rather than for a screen.
///
/// The display mode and the Arabic size used to be fields on the reading
/// screen's State. A reader who set them, walked to the sūra index and came
/// back found them reset, because the screen they lived on had been disposed.
class Prefs extends ChangeNotifier {
  Prefs._(
    this._db,
    this._order,
    this._display,
    this._arabicSize,
    this._headerOpen,
    this._rootOpen,
    this._ayaTranslation,
    this._mic,
    this._locale,
    ({String reciter, bool wordByWord}) audio,
  ) : _reciter = audio.reciter,
      _wordByWord = audio.wordByWord {
    locale.value = _locale == null ? null : Locale(_locale!);
  }

  static Future<Prefs> read(Database db) async {
    final display = await displayPrefs(db);
    return Prefs._(
      db,
      await readingOrder(db),
      display.display,
      display.arabicSize,
      display.headerOpen,
      display.rootOpen,
      display.ayaTranslation,
      await micPermission(db),
      await languagePref(db),
      await audioPref(db),
    );
  }

  final Database _db;
  ReadingOrder _order;
  int _display;
  double _arabicSize;
  bool _headerOpen;
  bool _rootOpen;
  bool _ayaTranslation;
  MicPermission _mic;
  String? _locale;
  String _reciter;
  bool _wordByWord;

  ReadingOrder get order => _order;

  /// 0 gloss, 1 transliteration, 2 both, 3 neither — the four the segmented
  /// control offers, in the order it offers them.
  int get display => _display;
  double get arabicSize => _arabicSize;

  /// Whether each end of screen 1a is unfolded. It lives here rather than on
  /// the screen for the reason the display settings do: a reader who folded
  /// the chrome away, walked to the sūra index and came back would find it
  /// back, because the screen it lived on had been disposed.
  bool get headerOpen => _headerOpen;
  bool get rootOpen => _rootOpen;

  /// Whether each aya's translation is drawn under it on the reading screen:
  /// Pickthall's English or Rashid Maash's French, by the reader's language.
  bool get ayaTranslation => _ayaTranslation;

  MicPermission get mic => _mic;

  /// Whose voice the recitation is in: a slug of the corpus `recitations`.
  String get reciter => _reciter;

  Future<void> setReciter(String reciter) async {
    if (reciter == _reciter) return;
    _reciter = reciter;
    notifyListeners();
    await setAudioPref(_db, reciter: _reciter, wordByWord: _wordByWord);
  }

  /// Whether a tapped word plays its own recording, spoken alone by
  /// quran.com's word-by-word voice, rather than its stretch of the reciter's
  /// aya.
  bool get wordByWord => _wordByWord;

  Future<void> setWordByWord(bool alone) async {
    if (alone == _wordByWord) return;
    _wordByWord = alone;
    notifyListeners();
    await setAudioPref(_db, reciter: _reciter, wordByWord: _wordByWord);
  }

  /// The language the reader picked, or null to take the phone's. Null is what
  /// [MaterialApp.locale] wants for "resolve it from the device", so the two
  /// agree without a translation between them.
  ///
  /// Its own notifier rather than this object's: the app root listens for the
  /// language, and it is the only preference that rebuilds the whole tree. On
  /// [notifyListeners] it would rebuild once per frame of the Arabic-size
  /// drag, which is every screen redrawn to move a slider.
  final locale = ValueNotifier<Locale?>(null);

  Future<void> setLocale(Locale? locale) async {
    final code = locale?.languageCode;
    if (code == _locale) return;
    _locale = code;
    this.locale.value = code == null ? null : Locale(code);
    await setLanguagePref(_db, code);
  }

  @override
  void dispose() {
    locale.dispose();
    super.dispose();
  }

  bool get showGloss => _display == 0 || _display == 2;
  bool get showTranslit => _display == 1 || _display == 2;

  Future<void> setOrder(ReadingOrder order) async {
    if (order == _order) return;
    await setReadingOrder(_db, order);
    _order = order;
    notifyListeners();
  }

  Future<void> setDisplay(int display) async {
    _display = display;
    notifyListeners();
    await _write();
  }

  Future<void> setArabicSize(double size) async {
    _arabicSize = size;
    notifyListeners();
    await _write();
  }

  Future<void> setHeaderOpen(bool open) async {
    _headerOpen = open;
    notifyListeners();
    await _write();
  }

  Future<void> setRootOpen(bool open) async {
    // A drag reports every frame it moves; only the first one changes this.
    if (open == _rootOpen) return;
    _rootOpen = open;
    notifyListeners();
    await _write();
  }

  Future<void> setAyaTranslation(bool shown) async {
    _ayaTranslation = shown;
    notifyListeners();
    await _write();
  }

  Future<void> _write() => setDisplayPrefs(
    _db,
    display: _display,
    arabicSize: _arabicSize,
    headerOpen: _headerOpen,
    rootOpen: _rootOpen,
    ayaTranslation: _ayaTranslation,
  );

  Future<void> askForTheMic() async {
    _mic = await askForMic(_db);
    notifyListeners();
  }
}

/// Prepares a prayer on [set], which the prayer then answers for.
///
/// Screen 1b writes nothing — it runs inside the prayer, where there is no
/// safe moment for a database write — so the prayer is recorded by the
/// screen that prepared it, when the reader comes back from it, however they
/// left: the Exit button, the back-swipe or Android's back all complete the
/// push. A prayer the reader never returns from is not recorded, and a
/// preparation backed out of before Begin is no prayer at all.
///
/// It lives here because starting a prayer is the application's act, not a
/// screen's. It used to be a button in the reading screen's settings panel,
/// which is the furthest thing from where the app's central act belongs.
Future<void> prayTheSet(BuildContext context, StudySet set) async {
  final navigator = Navigator.of(context);
  await Wird.of(context).recitation.stop();
  await navigator.pushNamed(Routes.prepare, arguments: set);
}
