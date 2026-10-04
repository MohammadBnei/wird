import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';

import '../../app.dart';
import '../../data/audio.dart';
import '../../data/db.dart';
import '../../data/root_repo.dart';
import '../../data/sets.dart';
import '../../l10n/app_localizations.dart';
import '../../nav.dart';
import '../../shell/wird_shell.dart';
import '../../theme/glow.dart';
import '../../theme/nocturne.dart';
import '../../widgets/lit_aya.dart';
import 'away_aya.dart';
import 'aya_translation.dart';
import 'reading_walk.dart';
import 'root_sheet.dart';
import 'word_swipe.dart';
import 'study_chrome.dart' show DashedRule;
import 'word_row.dart';

/// Screen 1a — a whole sūra, read a word at a time.
///
/// The sūra fills the top of the screen and the open word's root fills a sheet
/// under it; a sideways swipe on the sheet walks to the next word. Scrolling
/// the sheet shrinks the sūra to one line and brings up the counts, the root's
/// forms and the other ayas it is read in (ADR 0014).
class StudyScreen extends StatefulWidget {
  const StudyScreen({super.key, required this.db, this.target, this.word});

  final Database db;

  /// The aya to open on, or null to open where the reader last stood.
  final int? target;

  /// The word to open on, which wins over [target].
  final int? word;

  @override
  State<StudyScreen> createState() => _StudyScreenState();
}

class _StudyScreenState extends State<StudyScreen> {
  /// The sūra on screen: [StudySet.reading] is every aya of it. Kept while
  /// the reader walks, so the list never rebuilds under them.
  StudySet? _surah;

  /// The ayas around the open word that a prayer takes. Moves with the
  /// reader; [_surah] does not.
  StudySet? _acted;

  /// The words of the sūra, by aya, as far as they have been read. Al-Baqarah
  /// is 6116 of them and the screen shows a screenful, so they arrive in
  /// chunks.
  Map<int, List<StudyWord>> _words = {};

  /// Each aya's translation in the reader's language, as far as it has been
  /// read. Read whether or not the reader shows it, so the setting needs no
  /// reload.
  final Map<int, String> _translated = {};
  final _pending = <int>{};

  StudyWord? _word;
  SheetWord? _sheet;

  /// The sheets of the words either side of the open one, read ahead so a
  /// swipe can draw them beside it and land without a wait.
  final Map<int, SheetWord> _peek = {};

  /// The word being opened, while its root is read: a second step counts from
  /// here, so two quick swipes move two words.
  int? _opening;

  bool _expanded = false;

  /// Set while the sheet folds down: its content stays drawn until the sūra
  /// has taken the screen, rather than vanishing at the start of the fold.
  bool _folding = false;

  /// How the sūra and the sheet trade height: opening, folding and
  /// expanding all move the same way.
  static const _sheetMove = Duration(milliseconds: 350);
  static const _sheetCurve = Cubic(0.3, 0.7, 0.2, 1);

  /// How far the sūra and the open aya drift as one gives way to the other.
  static const _drift = 24.0;

  /// Another aya the reader opened from the root's list, shown in place of
  /// the sūra until they go back.
  RootAya? _away;

  /// Every sūra's place in both orders, for the links to the ones beside
  /// this one. Read once.
  List<SurahPlace> _suras = const [];

  bool _loaded = false;
  int _generation = 0;
  Locale? _readIn;

  Recitation? _audio;
  Set<int> _speakable = const {};

  /// The sūra and the voice the recitation was carried in: the reciter, and
  /// whether a word plays alone. A reader who changes either in the settings
  /// comes back to the same sūra, which must be carried again.
  (int, (String, bool))? _heard;

  /// The first aya of the stretch kept on disk ([aheadAyas] long). Opening a
  /// word outside it moves it.
  int? _keptFrom;
  Prefs? _listening;
  int? _unheard;

  final _sheetScroll = ScrollController();

  /// The sūra list moves between a fixed band and the whole screen when the
  /// sheet folds; one key carries it across, so it keeps its scroll.
  final _topKey = GlobalKey();

  /// The sheet's slide, which the arrow keys drive like the sheet's arrows.
  final _swipe = GlobalKey<WordSwipeState>();

  /// One key per word, kept for the screen's life, so the open word can be
  /// found to centre it. A single key moved from word to word re-created the
  /// tile it landed on, and the aya flashed under every tap.
  final _wordKeys = <int, GlobalKey>{};
  GlobalKey _keyOf(int wordId) => _wordKeys.putIfAbsent(wordId, GlobalKey.new);
  static const _anchor = ValueKey('reading-anchor');
  static final _silent = ValueNotifier<int?>(null);
  static final _paused = ValueNotifier<bool>(false);

  /// Where the reader stands, written once they settle on a word.
  late final _position = PositionKeeper(widget.db);

  Prefs get _prefs => Wird.of(context).prefs;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final prefs = _prefs;
    if (!identical(prefs, _listening)) {
      _listening?.removeListener(_reciterChanged);
      _listening = prefs..addListener(_reciterChanged);
    }
    final locale = Localizations.localeOf(context);
    if (!_loaded || locale != _readIn) {
      _readIn = locale;
      _load(target: widget.target, word: _word?.id ?? widget.word);
    }
  }

  (String, bool) get _voice => (_prefs.reciter, _prefs.wordByWord);

  /// The settings screen sits over this one, so the voice the reader picked
  /// there is carried here while they are still choosing.
  void _reciterChanged() {
    final word = _word;
    if (word == null || _heard == null || _heard!.$2 == _voice) return;
    _carry(ayahOfWord(word.id));
  }

  @override
  void dispose() {
    _listening?.removeListener(_reciterChanged);
    // A reader who leaves before the position settled still left from there.
    _position.flush();
    _sheetScroll.dispose();
    super.dispose();
  }

  /// Opens a sūra on the aya [target], on the word [word], or where the reader
  /// last stood: their latest position, else the walk's next aya, else 1:1.
  Future<void> _load({int? target, int? word}) async {
    final generation = ++_generation;
    final order = _prefs.order;
    var at = word ?? (target == null ? null : firstWordOf(target));
    if (at == null) {
      final positions = await readingPositions(widget.db, limit: 1);
      if (positions.isNotEmpty) {
        at = positions.first.wordId;
      } else {
        final next = await nextSet(widget.db, order);
        at = firstWordOf(next?.ayas.first.id ?? 1001);
      }
    }
    final surah = await ayaSet(widget.db, order, ayahOfWord(at));
    if (surah == null || !mounted || generation != _generation) return;
    final lang = Localizations.localeOf(context).languageCode;
    final rendered = await translationsFor(widget.db, [
      for (final aya in surah.reading) aya.id,
    ], lang);
    if (!mounted || generation != _generation) return;
    if (_suras.isEmpty) _suras = await surahPlaces(widget.db);
    if (!mounted || generation != _generation) return;
    final words = {
      for (final aya in surah.reading)
        if (aya.words.isNotEmpty) aya.id: aya.words,
    };
    final open =
        words[ayahOfWord(at)]?.where((w) => w.id == at).firstOrNull ??
        words[ayahOfWord(at)]?.firstOrNull;
    setState(() {
      _surah = surah;
      _words = words;
      _translated
        ..clear()
        ..addAll(rendered);
      _pending.clear();
      _peek.clear();
      _wordKeys.clear();
      _away = null;
      _loaded = true;
    });
    if (open != null) await _open(open, opening: true);
  }

  /// Reads everything the sheet shows for [word], then shows it.
  ///
  /// The sheet keeps the word it is showing until the next one has been read,
  /// so a swipe never blanks it. [opening] is a sūra just loaded on [word],
  /// which the list hangs from its top edge: it is centred whatever.
  Future<void> _open(StudyWord word, {bool opening = false}) async {
    final generation = _generation;
    final was = _sheet;
    _opening = word.id;
    try {
      final sheet = _peek[word.id] ?? await _readSheet(word);
      // Overtaken: a newer load, or a newer word opened while this one was
      // being read, which must not be drawn over it.
      if (!mounted || generation != _generation || _opening != word.id) {
        return;
      }
      setState(() {
        _word = word;
        _sheet = sheet;
        _away = null;
      });
    } finally {
      // Cleared whatever happened, so a failed read never leaves the next
      // step counting from a word the reader never saw.
      if (_opening == word.id) _opening = null;
    }
    // Not waited on: the recitation below need not wait for it, nor it for
    // the recitation.
    unawaited(_peekAround(word.id, was));
    _sheetToTop();
    _position.move(word.id);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _centre(always: opening || _prefs.centreTapped),
    );
    await _carry(ayahOfWord(word.id));
  }

  /// Reads the sheets of the words either side of [wordId] into [_peek]. The
  /// word the reader came from is [was], read already. A side whose aya's
  /// words have not been read is left out, and a step there reads as before.
  Future<void> _peekAround(int wordId, SheetWord? was) async {
    final surah = _surah;
    if (surah == null) return;
    final generation = _generation;
    bool stale() =>
        !mounted || generation != _generation || _word?.id != wordId;
    final read = <int, SheetWord>{};
    for (final by in const [1, -1]) {
      final step = stepFrom(surah.reading, _words, wordId, by);
      final id = step?.wordId;
      if (step == null || id == null) continue;
      final known = _peek[id] ?? (was?.word.id == id ? was : null);
      if (known != null) {
        read[id] = known;
        continue;
      }
      final word = _words[surah.reading[step.ayaIndex].id]!.firstWhere(
        (w) => w.id == id,
      );
      read[id] = await _readSheet(word);
      if (stale()) return;
    }
    if (stale()) return;
    setState(() {
      _peek
        ..clear()
        ..addAll(read);
    });
  }

  /// The read sheet of the word [by] along from [wordId], if there is one.
  SheetWord? _peekAt(int wordId, int by) {
    final surah = _surah;
    if (surah == null) return null;
    final id = stepFrom(surah.reading, _words, wordId, by)?.wordId;
    return id == null ? null : _peek[id];
  }

  /// Everything the sheet shows for [word], read together.
  Future<SheetWord> _readSheet(StudyWord word) async {
    final readIn = Localizations.localeOf(context);
    final letters = word.root;
    return (
      word: word,
      root: letters == null
          ? null
          : await rootReading(widget.db, letters, readIn: readIn),
      lemmas: letters == null
          ? const <Lemma>[]
          : await lemmasOf(widget.db, letters),
      inSurah: letters == null
          ? 0
          : await rootCountInSurah(widget.db, letters, surahOfWord(word.id)),
      ayas: letters == null
          ? const <RootAya>[]
          : await rootAyas(
              widget.db,
              letters,
              lang: readIn.languageCode,
              except: ayahOfWord(word.id),
            ),
      irab: await wordIrab(widget.db, word.id, readIn: readIn),
    );
  }

  /// Keeps the recitation on the open word's sūra, the ayas from the open one
  /// on disk, and the prayer on the ayas around it.
  ///
  /// The recitation is the whole sūra so that opening a word never replaces
  /// the player under a recitation that is still running: it used to carry
  /// only the ayas around the open word, so the recitation stopped at their
  /// end, and opening a word past them started a new player and silenced the
  /// old one.
  Future<void> _carry(int ayahId) async {
    final surah = _surah;
    if (surah == null) return;
    final voice = _voice;
    final (reciter, wordByWord) = voice;
    final heard = (surah.reading.first.id, voice);
    final acted = _acted;
    final keptFrom = _keptFrom;
    final carry = _heard != heard;
    final pray = acted == null || !acted.ayas.any((a) => a.id == ayahId);
    final keep =
        carry ||
        keptFrom == null ||
        ayahId < keptFrom ||
        // Half way through, so the stretch ahead is never down to nothing.
        ayahId >= keptFrom + aheadAyas ~/ 2;
    if (!carry && !pray && !keep) return;
    final generation = _generation;
    final recitation = Wird.of(context).recitation;
    final order = _prefs.order;
    if (carry) {
      final reciterName = (await reciters(widget.db))
          .where((r) => r.slug == reciter)
          .firstOrNull
          ?.name;
      await recitation.carry(
        await tracksFor(widget.db, [
          for (final aya in surah.reading) aya.id,
        ], reciter: reciter),
        title: surah.reading.first.surahNameEn,
        wordByWord: wordByWord,
        voice: reciterName,
      );
    }
    final set = pray
        ? await ayaSet(
            widget.db,
            order,
            ayahId,
            ayas: await readingWidth(widget.db, order),
          )
        : acted;
    if (!mounted || generation != _generation) return;
    // The reader may have walked on to another aya while this was read, and
    // the prayer is about the aya they are on.
    final open = _word;
    final here = open != null && ayahOfWord(open.id) == ayahId;
    setState(() {
      if (here) _acted = set;
      _heard = heard;
      if (keep) _keptFrom = ayahId;
      _audio = recitation;
      _speakable = recitation.speakable;
    });
    if (keep) {
      await recitation.prefetch(
        windowPaths(recitation.tracks, ayahId, wordByWord: wordByWord),
      );
    }
  }

  /// Brings the open word back into the sūra list, to its middle, when it is
  /// out of view — or [always]: for a sūra just opened on it, which hangs it
  /// from the list's top edge with the aya before it out of sight, and for
  /// every word when the reader has asked for the tapped word centred.
  ///
  /// ponytail: only a word whose aya has been built. A jump to an aya off the
  /// screen lands it at the list's anchor instead, which is where [_load]
  /// opens a sūra; move the anchor if a jump inside a long sūra ever lands
  /// out of sight.
  void _centre({required bool always}) {
    final word = _word;
    if (word == null) return;
    final context = _keyOf(word.id).currentContext;
    if (context == null) return;
    // Unless asked otherwise, a word the reader can see stays where it is: a
    // tap opens what is under their thumb, and moving the list under it can
    // lose the place they scrolled to. Only a step that walked the open word
    // out of view brings it back, to the middle. "Can see" is its middle being in view: a word half cut
    // at the list's edge can still be tapped, and must not jump either.
    final list = Scrollable.maybeOf(context)?.context.findRenderObject();
    final tile = context.findRenderObject();
    if (!always &&
        list is RenderBox &&
        tile is RenderBox &&
        list.hasSize &&
        tile.hasSize) {
      final seen = list.localToGlobal(Offset.zero) & list.size;
      final middle = tile.localToGlobal(tile.size.center(Offset.zero));
      if (seen.contains(middle)) return;
    }
    Scrollable.ensureVisible(
      context,
      alignment: 0.5,
      duration: const Duration(milliseconds: 300),
    );
  }

  /// The word [by] along from the open one, across the whole sūra.
  Future<void> _step(int by) async {
    final surah = _surah;
    final from = _opening ?? _word?.id;
    if (surah == null || from == null) return;
    var step = stepFrom(surah.reading, _words, from, by);
    if (step == null) return;
    if (step.wordId == null) {
      await _readWordsAround(step.ayaIndex, surah.reading);
      if (!mounted) return;
      step = stepFrom(surah.reading, _words, from, by);
      if (step?.wordId == null) return;
    }
    final to = _words[surah.reading[step!.ayaIndex].id]!.firstWhere(
      (w) => w.id == step!.wordId,
    );
    await _open(to);
  }

  /// A step the way the sheet's arrows take it, or a plain step while the
  /// sheet is folded away.
  void _slide(int by) {
    final swipe = _swipe.currentState;
    if (swipe == null) {
      _stepTo(by)?.call();
    } else if (by > 0) {
      swipe.slideNext();
    } else {
      swipe.slidePrevious();
    }
  }

  /// Which way a step can go: null at the ends of the sūra.
  Future<void> Function()? _stepTo(int by) {
    final surah = _surah;
    final from = _opening ?? _word?.id;
    if (surah == null || from == null) return null;
    return stepFrom(surah.reading, _words, from, by) == null
        ? null
        : () => _step(by);
  }

  Future<void> _markUnderstood(StudyAya aya) async {
    await markSetUnderstood(widget.db, newOpId(), [aya.id]);
    if (!mounted) return;
    setState(() => _surah = _surah?.withUnderstood({aya.id}));
  }

  /// A word the reader tapped: opened, and after a pause, where the next
  /// press of play starts. Only the tap: a word opened by a step, a load or
  /// a return from another screen is not the reader choosing where to
  /// recite from.
  Future<void> _tapped(StudyWord word) {
    _audio?.touch(word.id);
    return _open(word);
  }

  Future<void> _speak(StudyWord word) async {
    final sounded = await _audio?.playWord(word.id, label: word.text) ?? false;
    if (mounted) setState(() => _unheard = sounded ? null : word.id);
  }

  Future<void> _visit(String route, Object arguments) async {
    final chosen = await Navigator.of(context)
        .pushNamed(route, arguments: arguments);
    if (mounted && chosen is int) await _load(target: chosen);
  }

  void _setExpanded(bool expanded) {
    setState(() => _expanded = expanded);
    if (!expanded) _sheetToTop();
  }

  void _sheetToTop() {
    if (_sheetScroll.hasClients) _sheetScroll.jumpTo(0);
  }

  /// An aya's translation when the reader shows translations, else null.
  String? _shownTranslation(int ayahId) =>
      _prefs.ayaTranslation ? _translated[ayahId] : null;

  @override
  Widget build(BuildContext context) {
    final n = Nocturne.of(context);
    final surah = _surah;
    return ListenableBuilder(
      listenable: _prefs,
      builder: (context, _) => SafeArea(
        child: !_loaded || surah == null
            ? const SizedBox.shrink()
            : CallbackShortcuts(
                bindings: {
                  // Arabic reads leftward: the next word is to the left.
                  // With the sheet folded there is no slide to drive, and
                  // the step happens without one.
                  const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
                      _slide(1),
                  const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
                      _slide(-1),
                },
                child: Focus(
                  autofocus: true,
                  child: LayoutBuilder(
                    builder: (context, box) => Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _bar(n, surah),
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, rest) => Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                AnimatedContainer(
                                  duration: _sheetMove,
                                  curve: _sheetCurve,
                                  onEnd: () {
                                    if (_folding) {
                                      setState(() => _folding = false);
                                    }
                                  },
                                  // The design's 318 of 812 split; open, the
                                  // aya keeps a fifth, enough to be read
                                  // whole. Folded, the sūra takes all but the
                                  // sheet's handle.
                                  height: !_prefs.rootOpen
                                      ? rest.maxHeight - RootSheet.handleHeight
                                      : box.maxHeight *
                                            (_expanded ? 0.22 : 0.39),
                                  decoration: BoxDecoration(
                                    border: Border(
                                      bottom: _prefs.rootOpen
                                          ? BorderSide(color: n.divider)
                                          : BorderSide.none,
                                    ),
                                  ),
                                  clipBehavior: Clip.hardEdge,
                                  child: KeyedSubtree(
                                    key: _topKey,
                                    child: _top(n, surah),
                                  ),
                                ),
                                Expanded(
                                  child: _rootSheet(hidden: !_prefs.rootOpen),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  /// The open word's root, or its handle alone while the reader has folded
  /// it away to read.
  Widget _rootSheet({bool hidden = false}) {
    final sheet = _sheet;
    if (sheet == null) return const SizedBox.shrink();
    return RootSheet(
      sheet: sheet,
      expanded: _expanded,
      hidden: hidden,
      folding: _folding,
      onHidden: (fold) {
        // The sūra takes the screen whole, not the fifth an open sheet
        // leaves it.
        if (fold) _setExpanded(false);
        if (fold && _prefs.rootOpen) setState(() => _folding = true);
        _prefs.setRootOpen(!fold);
      },
      swipe: _swipe,
      onPrevious: _stepTo(-1),
      onNext: _stepTo(1),
      previous: _peekAt(sheet.word.id, -1),
      next: _peekAt(sheet.word.id, 1),
      onToggle: () => _setExpanded(!_expanded),
      onExpand: () {
        if (!_expanded) _setExpanded(true);
      },
      onCollapse: () {
        if (_expanded) _setExpanded(false);
      },
      onRoot: (letters) => _visit(Routes.root, letters),
      db: widget.db,
      onConstellation: (ayahId, letters) =>
          _visit(Routes.deepDive, (ayahId: ayahId, letters: letters)),
      translations: _prefs.ayaTranslation,
      onAya: (aya) {
        setState(() => _away = aya);
        _sheetToTop();
      },
      scroll: _sheetScroll,
    );
  }

  /// Menu, the sūra's name (which opens the index), where the reader is,
  /// the recitation and the prayer.
  Widget _bar(Nocturne n, StudySet surah) {
    final l = AppLocalizations.of(context)!;
    final first = surah.reading.first;
    final word = _word;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      child: Row(
        spacing: 4,
        children: [
          const ShellBurger(),
          Expanded(
            child: InkWell(
              key: const Key('surah name'),
              onTap: () => _visit(Routes.index, const AStepFrom()),
              // One run of text with the chevron inside it, so a narrow bar
              // or a large system text size ellipsises the name rather than
              // overflowing the row.
              child: Text.rich(
                TextSpan(
                  text: '${first.surahNameEn} ',
                  children: [
                    WidgetSpan(
                      alignment: PlaceholderAlignment.middle,
                      child: Icon(
                        Icons.expand_more,
                        size: 16,
                        color: n.textAt(0.6),
                      ),
                    ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 16, color: n.text),
              ),
            ),
          ),
          if (word != null)
            Flexible(
              child: Text(
                _positionLabel(l, surah, word),
                key: const Key('position'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: n.textAt(0.62)),
              ),
            ),
          // Rebuilt on the bar as well as on playing: a stop from the bar
          // while paused leaves playing false, and a button still holding
          // the paused press would start the sūra from its top.
          ListenableBuilder(
            listenable: Listenable.merge([
              _audio?.playing ?? _paused,
              ?_audio?.sounding,
            ]),
            builder: (context, _) {
              final playing = (_audio?.playing ?? _paused).value;
              final audio = _audio;
              final ready = audio?.ready ?? false;
              return IconButton(
                // A dark button says why it is dark: the corpus carries no
                // recitation for this sūra in this voice.
                tooltip: playing
                    ? l.study_pauseRecitation
                    : audio == null || ready
                    ? l.study_recite
                    : l.study_noRecitation,
                // A press carries on from the open word, or resumes a pause;
                // a hold starts the sūra again from its first aya.
                onPressed: !ready
                    ? null
                    : playing || audio!.paused
                    ? audio!.toggle
                    : () => audio.playFrom(_word?.id),
                onLongPress: ready ? () => audio!.playFrom(null) : null,
                icon: Icon(
                  playing ? Icons.pause : Icons.play_arrow,
                  size: 20,
                  color: n.color('accent-300'),
                ),
              );
            },
          ),
          TextButton(
            key: const Key('pray'),
            onPressed: _acted == null
                ? null
                : () => prayTheSet(context, _acted!),
            child: Text(
              l.study_pray,
              style: TextStyle(fontSize: 12.5, color: n.color('accent-300')),
            ),
          ),
        ],
      ),
    );
  }

  /// "2:255 · word 3/50": the aya and the word open, and where that word
  /// falls in the sūra, counting words whose ayas have not been read.
  String _positionLabel(AppLocalizations l, StudySet surah, StudyWord word) {
    final ayaId = ayahOfWord(word.id);
    var before = 0;
    var total = 0;
    for (final aya in surah.reading) {
      if (aya.id < ayaId) before += aya.wordCount;
      total += aya.wordCount;
    }
    return l.study_position(ayahRef(ayaId), before + word.id % 1000, total);
  }

  Widget _top(Nocturne n, StudySet surah) {
    final away = _away;
    if (away != null) {
      return AwayAya(
        aya: away,
        homeRef: ayahRef(ayahOfWord(_word?.id ?? 0)),
        compact: _expanded,
        translation: _prefs.ayaTranslation ? away.translation : null,
        onBack: () => setState(() => _away = null),
        onReadFromHere: () => _load(target: away.ayahId),
      );
    }
    // The sūra stays under the open aya rather than being rebuilt from its
    // anchor: the two cross, one fading as it drifts up and the other after
    // it, and the reader comes back to the sūra where they left it.
    return TweenAnimationBuilder<double>(
      tween: Tween(end: _expanded ? 1 : 0),
      duration: _sheetMove,
      curve: _sheetCurve,
      builder: (context, t, _) => Stack(
        fit: StackFit.expand,
        children: [
          _crossing(
            1 - const Interval(0, 0.55).transform(t),
            -_drift * t,
            _list(n, surah),
          ),
          if (t > 0)
            _crossing(
              const Interval(0.45, 1).transform(t),
              _drift * (1 - t),
              _openAya(n),
            ),
        ],
      ),
    );
  }

  /// One side of the crossing: untouchable once it is more gone than here.
  Widget _crossing(double shown, double dy, Widget child) => IgnorePointer(
    ignoring: shown < 0.5,
    child: Opacity(
      opacity: shown,
      child: Transform.translate(offset: Offset(0, dy), child: child),
    ),
  );

  /// The whole sūra, hung from the aya it was opened at.
  ///
  /// An aya is built when it comes near the viewport and not before. The
  /// slivers before [_anchor] grow upward, so opening Al-Baqarah at 255 does
  /// not build the 254 ayas above it, and the reader can still scroll up into
  /// them.
  Widget _list(Nocturne n, StudySet surah) {
    final ayas = surah.reading;
    final focus = surah.focusIndex;
    return ValueListenableBuilder<int?>(
      valueListenable: _audio?.currentWordId ?? _silent,
      builder: (context, recited, _) => CustomScrollView(
        // Keyed by where it hangs from too: opening another aya of the same
        // sūra must start from that aya, not from the old scroll offset.
        key: ValueKey((ayas.first.id, focus)),
        center: _anchor,
        slivers: [
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, i) => _ayaTile(n, ayas, focus - 1 - i, recited),
              childCount: focus,
            ),
          ),
          const SliverToBoxAdapter(key: _anchor, child: SizedBox.shrink()),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, i) => _ayaTile(n, ayas, focus + i, recited),
              childCount: ayas.length - focus,
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.only(bottom: n.space('8')),
              child: _suraNav(n, ayas.first.surahId),
            ),
          ),
        ],
      ),
    );
  }

  /// The sūras either side of this one in the order the reader chose, at the
  /// top of the sūra and again at its end. Read from the order on every
  /// build, so switching it in the settings moves the links without a reload.
  Widget _suraNav(Nocturne n, int surahId) {
    final l = AppLocalizations.of(context)!;
    final style = TextStyle(fontSize: 12, color: n.textAt(0.62));
    Widget link(int by) {
      final to = surahBeside(_suras, _prefs.order, surahId, by);
      if (to == null) return const Spacer();
      final icon = Icon(
        by < 0 ? Icons.chevron_left : Icons.chevron_right,
        size: 16,
        color: n.textAt(0.62),
      );
      final name = Flexible(
        child: Text(
          to.nameEn,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: style,
        ),
      );
      return Flexible(
        child: Tooltip(
          message: by < 0 ? l.study_previousSura : l.study_nextSura,
          child: TextButton(
            key: Key(by < 0 ? 'previous sura' : 'next sura'),
            onPressed: () => _load(target: to.id * 1000 + 1),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: by < 0 ? [icon, name] : [name, icon],
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: n.space('2')),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [link(-1), link(1)],
      ),
    );
  }

  Widget _ayaTile(Nocturne n, List<StudyAya> ayas, int index, int? recited) {
    // Above the first aya, whether or not its words have been read yet.
    if (index == 0) {
      return Column(
        children: [
          _suraNav(n, ayas.first.surahId),
          _ayaBody(n, ayas, index, recited),
        ],
      );
    }
    return _ayaBody(n, ayas, index, recited);
  }

  Widget _ayaBody(Nocturne n, List<StudyAya> ayas, int index, int? recited) {
    final aya = ayas[index];
    final words = _words[aya.id];
    if (words == null) {
      _readWordsAround(index, ayas);
      // ponytail: a word is about 28 px of column once it has wrapped. The
      // guess only has to keep an aya above the reader from shoving the one
      // they are reading when its words land.
      return SizedBox(height: 28.0 * aya.wordCount);
    }
    final l = AppLocalizations.of(context)!;
    final face = faceOf(aya, words, _speakable);
    final open = _word;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: n.space('4')),
      child: Column(
        children: [
          if (index == 0)
            SizedBox(height: n.space('2'))
          else
            Padding(
              padding: EdgeInsets.symmetric(vertical: n.space('2')),
              child: const DashedRule(),
            ),
          if (index == 0 &&
              Localizations.localeOf(context).languageCode == 'fr') ...[
            // Once, above the reading, not under every aya.
            Text(
              l.study_glossesSource,
              style: TextStyle(fontSize: 10.5, color: n.textAt(0.45)),
            ),
            SizedBox(height: n.space('2')),
          ],
          Wrap(
            textDirection: TextDirection.rtl,
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.start,
            spacing: n.space('3'),
            runSpacing: n.space('1'),
            children: [
              for (final word in face.words)
                KeyedSubtree(
                  key: _keyOf(word.word.id),
                  child: WordTile(
                    key: WordKey(word.word.id),
                    face: word,
                    voice: word.voice(sounding: recited, unheard: _unheard),
                    open: word.word.id == open?.id,
                    sameRoot:
                        open?.root != null &&
                        word.word.id != open?.id &&
                        word.word.root == open?.root,
                    prefs: _prefs,
                    onOpen: _tapped,
                    onHear: _speak,
                  ),
                ),
              AyaMark(
                aya: face.aya,
                arabicSize: _prefs.arabicSize,
                label: l.study_markUnderstood(ayahRef(aya.id)),
                onMark: aya.understood ? null : () => _markUnderstood(aya),
                // Every aya alone, from its own number: the header's button
                // recites on through the sūra, and a reader studying one aya
                // wants to hear just it, again. A hold, so the reading is not
                // a column of buttons. Pause and stop are on the bar it
                // brings up.
                playLabel: l.study_reciteAya,
                onPlay: _audio == null
                    ? null
                    : () => _audio!.playAya(aya.id, label: ayahRef(aya.id)),
              ),
            ],
          ),
          AyaTranslation(_shownTranslation(aya.id)),
        ],
      ),
    );
  }

  /// The open word's aya, whole, while the sheet below is open: it is the
  /// sentence the sheet is about, so it stays readable, with its translation
  /// when the reader shows translations. A long aya scrolls in its band. A
  /// tap closes the sheet again.
  ///
  /// ponytail: the band does not scroll to the open word; in the longest
  /// ayas it can sit below the fold. Scroll it into view if readers miss it.
  Widget _openAya(Nocturne n) {
    final word = _word;
    final words = word == null ? null : _words[ayahOfWord(word.id)];
    if (word == null || words == null) return const SizedBox.shrink();
    return GestureDetector(
      key: const Key('open aya'),
      behavior: HitTestBehavior.opaque,
      onTap: () => _setExpanded(false),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
        child: Column(
          children: [
            Row(
              children: [
                Text(
                  ayahRef(ayahOfWord(word.id)),
                  style: TextStyle(fontSize: 11, color: n.textAt(0.6)),
                ),
                const Spacer(),
                Icon(Icons.expand_more, size: 16, color: n.textAt(0.6)),
              ],
            ),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    LitAya(
                      [
                        for (final w in words)
                          (id: w.id, text: w.text, lit: w.id == word.id),
                      ],
                      glow: Glow.reading,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: Nocturne.arabicFamily,
                        fontSize: 24,
                        height: 1.8,
                        color: n.text,
                      ),
                    ),
                    AyaTranslation(_shownTranslation(ayahOfWord(word.id))),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Reads the words of the ayas around [index], a chunk at a time, in one
  /// query however many ayas the chunk covers.
  Future<void> _readWordsAround(int index, List<StudyAya> ayas) async {
    final generation = _generation;
    final want = <int>[];
    for (
      var i = (index - 4).clamp(0, ayas.length - 1);
      i <= (index + 12).clamp(0, ayas.length - 1);
      i++
    ) {
      final id = ayas[i].id;
      if (!_words.containsKey(id) && _pending.add(id)) want.add(id);
    }
    if (want.isEmpty) return;
    try {
      final read = await wordsFor(widget.db, want);
      if (!mounted || generation != _generation) return;
      setState(() => _words.addAll(read));
    } finally {
      // Released either way, so a failed read is asked again rather than
      // leaving its ayas as blank space for good.
      _pending.removeAll(want);
    }
  }
}
