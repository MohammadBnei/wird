import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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
enum Sounded { word, set }

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
/// * [speakable] — the words whose aya is on disk, so the row can be honest
///   about which words will answer a press.
/// * [playWord] — plays one word; false means it was never downloaded or the
///   platform refused it.
/// * [ready] and [toggle] — the set's own play control.
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
  Map<int, String> _words = const {};

  /// The ayas the loaded player covers, so walking away from the reading
  /// screen and back does not rebuild it underneath a recitation that is
  /// still running.
  List<int> _covers = const [];

  /// Which word probe owns the transport.
  int _probe = 0;

  static final _noWord = ValueNotifier<int?>(null);
  static final _silent = ValueNotifier<bool>(false);

  ValueListenable<int?> get currentWordId => _set?.currentWordId ?? _noWord;
  ValueListenable<bool> get playing => _set?.playing ?? _silent;

  bool get ready => _set?.ready ?? false;
  Set<int> get speakable => _set?.speakable ?? const {};

  /// Hands the application the set the reader is on: its recitation, what to
  /// call it, and the Arabic of each word so the transport can name the one
  /// being sounded. The player is built here and outlives the screen that
  /// asked for it.
  ///
  /// The same set twice is the reader leaving the reading screen and coming
  /// back: the player stays, and so does whatever it was playing.
  Future<void> carry(
    List<AyaTrack> tracks, {
    required String title,
    required Map<int, String> words,
  }) async {
    _title = title;
    _words = words;
    final covers = [for (final track in tracks) track.ayahId];
    if (_set != null && listEquals(covers, _covers)) return;
    final previous = _set;
    _set = SetAudio(cache: await cache, tracks: tracks);
    _covers = covers;
    sounding.value = null;
    await previous?.dispose();
  }

  Future<void> prefetch(Iterable<String> relPaths) async =>
      (await cache).prefetch(relPaths);

  /// Plays one word, and says so: the transport names the word rather than
  /// leaving the reader to guess whether a whole recitation just started.
  ///
  /// A word answers when its clip ENDS, so the reader's next word arrives
  /// while this one is still in flight. The probe carries a number for the
  /// same reason the player's own does: without it, the word that was
  /// superseded clears the transport of the word that superseded it, and the
  /// bar goes dark over a recitation that is still sounding.
  Future<bool> playWord(int wordId) async {
    final set = _set;
    if (set == null) return false;
    final probe = ++_probe;
    sounding.value = (what: Sounded.word, label: _words[wordId] ?? '');
    final sounded = await set.playWord(wordId);
    if (identical(_set, set) &&
        probe == _probe &&
        sounding.value?.what == Sounded.word) {
      sounding.value = null;
    }
    return sounded;
  }

  /// Plays or pauses the whole set.
  Future<void> toggle() async {
    final set = _set;
    if (set == null) return;
    if (set.playing.value) {
      sounding.value = null;
      await set.toggle();
      return;
    }
    if (!set.ready) return;
    sounding.value = (what: Sounded.set, label: _title);
    await set.toggle();
    if (identical(_set, set) && sounding.value?.what == Sounded.set) {
      sounding.value = null;
    }
  }

  /// Silence, from wherever the reader is. A word long-pressed by accident
  /// used to play to its end because the only control was on the screen that
  /// started it, and that screen had been scrolled or navigated away from.
  Future<void> stop() async {
    sounding.value = null;
    final set = _set;
    if (set == null) return;
    if (set.playing.value) await set.toggle();
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
    this._mic,
  );

  static Future<Prefs> read(Database db) async {
    final display = await displayPrefs(db);
    return Prefs._(
      db,
      await readingOrder(db),
      display.display,
      display.arabicSize,
      display.headerOpen,
      display.rootOpen,
      await micPermission(db),
    );
  }

  final Database _db;
  ReadingOrder _order;
  int _display;
  double _arabicSize;
  bool _headerOpen;
  bool _rootOpen;
  MicPermission _mic;

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

  MicPermission get mic => _mic;

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
    _rootOpen = open;
    notifyListeners();
    await _write();
  }

  Future<void> _write() => setDisplayPrefs(
    _db,
    display: _display,
    arabicSize: _arabicSize,
    headerOpen: _headerOpen,
    rootOpen: _rootOpen,
  );

  Future<void> askForTheMic() async {
    _mic = await askForMic(_db);
    notifyListeners();
  }
}

/// Enters the prayer and records it on the way out.
///
/// Screen 1b writes nothing — it runs inside the prayer, where there is no
/// safe moment for a database write — so the prayer is recorded here, when the
/// reader comes back from it, however they left: the Exit button, the
/// back-swipe or Android's back all complete the push.
///
/// A prayer the reader never returns from is not recorded. That is the price
/// of 1b writing nothing, and it is the side to be wrong on: the prayer count
/// is allowed to be short, never invented.
///
/// It lives here because starting a prayer is the application's act, not a
/// screen's. It used to be a button in the reading screen's settings panel,
/// which is the furthest thing from where the app's central act belongs.
Future<void> prayTheSet(BuildContext context, StudySet set) async {
  final db = Wird.of(context).db;
  final navigator = Navigator.of(context);
  await Wird.of(context).recitation.stop();
  await navigator.pushNamed(Routes.prayer, arguments: set);
  await recordSetPrayed(db, set);
}
