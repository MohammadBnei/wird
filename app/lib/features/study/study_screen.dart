import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';

import '../../app.dart';
import '../../data/audio.dart';
import '../../data/db.dart';
import '../../data/root_repo.dart';
import '../../data/sets.dart';
import '../report/report.dart';
import '../../l10n/app_localizations.dart';
import '../../nav.dart';
import '../../shell/wird_shell.dart';
import '../../theme/nocturne.dart';
import 'reading_walk.dart';
import 'root_sheet.dart';
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

  /// The ayas around the open word that the recitation carries and a prayer
  /// takes. Moves with the reader; [_surah] does not.
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

  /// The word being opened, while its root is read: a second step counts from
  /// here, so two quick swipes move two words.
  int? _opening;

  bool _expanded = false;

  /// Another aya the reader opened from the root's list, shown in place of
  /// the sūra until they go back.
  RootAya? _away;

  bool _loaded = false;
  int _generation = 0;
  Locale? _readIn;

  Recitation? _audio;
  Set<int> _speakable = const {};
  int? _unheard;

  final _sheetScroll = ScrollController();

  /// One key per word, kept for the screen's life, so the open word can be
  /// found to centre it. A single key moved from word to word re-created the
  /// tile it landed on, and the aya flashed under every tap.
  final _wordKeys = <int, GlobalKey>{};
  GlobalKey _keyOf(int wordId) => _wordKeys.putIfAbsent(wordId, GlobalKey.new);
  static const _anchor = ValueKey('reading-anchor');
  static final _silent = ValueNotifier<int?>(null);
  static final _paused = ValueNotifier<bool>(false);

  /// The position is written once the reader has settled on a word, not on
  /// every swipe: a sitting sends a handful of moves to their other devices.
  Timer? _settle;
  static const _settleAfter = Duration(seconds: 2);

  Prefs get _prefs => Wird.of(context).prefs;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final locale = Localizations.localeOf(context);
    if (!_loaded || locale != _readIn) {
      _readIn = locale;
      _load(target: widget.target, word: _word?.id ?? widget.word);
    }
  }

  @override
  void dispose() {
    // A reader who leaves before the position settled still left from there.
    if (_settle?.isActive ?? false) {
      _settle!.cancel();
      if (_word case final word?) unawaited(movePosition(widget.db, word.id));
    }
    _sheetScroll.dispose();
    super.dispose();
  }

  /// Opens a sūra on the aya [target], on the word [word], or where the reader
  /// last stood: their latest position, else the walk's next aya, else 1:1.
  Future<void> _load({int? target, int? word}) async {
    final generation = ++_generation;
    final order = _prefs.order;
    var at = word ?? (target == null ? null : target * 1000 + 1);
    if (at == null) {
      final positions = await readingPositions(widget.db);
      if (positions.isNotEmpty) {
        at = positions.first.wordId;
      } else {
        final next = await nextSet(widget.db, order);
        at = (next?.ayas.first.id ?? 1001) * 1000 + 1;
      }
    }
    final surah = await ayaSet(widget.db, order, at ~/ 1000);
    if (surah == null || !mounted || generation != _generation) return;
    final lang = Localizations.localeOf(context).languageCode;
    final rendered = await translationsFor(widget.db, [
      for (final aya in surah.reading) aya.id,
    ], lang);
    if (!mounted || generation != _generation) return;
    final words = {
      for (final aya in surah.reading)
        if (aya.words.isNotEmpty) aya.id: aya.words,
    };
    final open =
        words[at ~/ 1000]?.where((w) => w.id == at).firstOrNull ??
        words[at ~/ 1000]?.firstOrNull;
    setState(() {
      _surah = surah;
      _words = words;
      _translated
        ..clear()
        ..addAll(rendered);
      _pending.clear();
      _away = null;
      _loaded = true;
    });
    if (open != null) await _open(open);
  }

  /// Reads everything the sheet shows for [word], then shows it.
  ///
  /// The sheet keeps the word it is showing until the next one has been read,
  /// so a swipe never blanks it.
  Future<void> _open(StudyWord word) async {
    final generation = _generation;
    _opening = word.id;
    final readIn = Localizations.localeOf(context);
    final letters = word.root;
    final root = letters == null
        ? null
        : await rootReading(widget.db, letters, readIn: readIn);
    final sheet = (
      word: word,
      root: root,
      lemmas: letters == null
          ? const <Lemma>[]
          : await lemmasOf(widget.db, letters),
      inSurah: letters == null
          ? 0
          : await rootCountInSurah(widget.db, letters, word.id ~/ 1000000),
      ayas: letters == null
          ? const <RootAya>[]
          : await rootAyas(
              widget.db,
              letters,
              lang: readIn.languageCode,
              except: word.id ~/ 1000,
            ),
      irab: await wordIrab(widget.db, word.id, readIn: readIn),
    );
    if (!mounted || generation != _generation) return;
    setState(() {
      _word = word;
      _sheet = sheet;
      _opening = null;
      _away = null;
    });
    if (_sheetScroll.hasClients) _sheetScroll.jumpTo(0);
    _settle?.cancel();
    _settle = Timer(_settleAfter, () => movePosition(widget.db, word.id));
    WidgetsBinding.instance.addPostFrameCallback((_) => _centre());
    await _carry(word.id ~/ 1000);
  }

  /// Keeps the recitation on the ayas around the open word, so the play
  /// button and a prayer are always about where the reader is.
  Future<void> _carry(int ayahId) async {
    final acted = _acted;
    if (acted != null && acted.ayas.any((a) => a.id == ayahId)) return;
    final generation = _generation;
    final recitation = Wird.of(context).recitation;
    final order = _prefs.order;
    final set = await ayaSet(
      widget.db,
      order,
      ayahId,
      ayas: await readingWidth(widget.db, order),
    );
    if (set == null || !mounted || generation != _generation) return;
    await recitation.carry(
      await tracksFor(widget.db, [for (final aya in set.ayas) aya.id]),
      title: set.title,
      words: {
        for (final aya in set.ayas)
          for (final word in aya.words) word.id: word.text,
      },
    );
    final keep = await pathsToKeep(widget.db, order, set, onTheWalk: false);
    if (!mounted || generation != _generation) return;
    setState(() {
      _acted = set;
      _audio = recitation;
      _speakable = recitation.speakable;
    });
    await recitation.prefetch(keep);
    if (mounted) setState(() => _speakable = recitation.speakable);
  }

  /// Puts the open word in the middle of the sūra list.
  ///
  /// ponytail: only a word whose aya has been built. A jump to an aya off the
  /// screen lands it at the list's anchor instead, which is where [_load]
  /// opens a sūra; move the anchor if a jump inside a long sūra ever lands
  /// out of sight.
  void _centre() {
    final word = _word;
    if (word == null) return;
    final context = _keyOf(word.id).currentContext;
    if (context == null) return;
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

  /// Which way a step can go: null at the ends of the sūra.
  VoidCallback? _stepTo(int by) {
    final surah = _surah;
    final from = _opening ?? _word?.id;
    if (surah == null || from == null) return null;
    return stepFrom(surah.reading, _words, from, by) == null
        ? null
        : () => _step(by);
  }

  /// The word next to the open one, for the sheet's hint row, when its aya
  /// has been read.
  StudyWord? _beside(int by) {
    final surah = _surah;
    final from = _word?.id;
    if (surah == null || from == null) return null;
    final step = stepFrom(surah.reading, _words, from, by);
    if (step?.wordId == null) return null;
    return _words[surah.reading[step!.ayaIndex].id]!.firstWhere(
      (w) => w.id == step.wordId,
    );
  }

  Future<void> _markUnderstood(StudyAya aya) async {
    await markSetUnderstood(widget.db, newOpId(), [aya.id]);
    if (!mounted) return;
    setState(() => _surah = _surah?.withUnderstood({aya.id}));
  }

  /// Queued, never sent here: a verdict given on a plane is not told it
  /// failed, and nothing is drawn over the reading either way.
  Future<void> _judgeSense(String root, bool good) async {
    await judgeSense(
      widget.db,
      root: root,
      good: good,
      context: await reportContext(widget.db, screen: screenName(Routes.study)),
    );
  }

  Future<void> _speak(StudyWord word) async {
    final sounded = await _audio?.playWord(word.id) ?? false;
    if (mounted) setState(() => _unheard = sounded ? null : word.id);
  }

  Future<void> _visit(String route, Object arguments) async {
    final chosen = await Navigator.of(context)
        .pushNamed(route, arguments: arguments);
    if (mounted && chosen is int) await _load(target: chosen);
  }

  void _setExpanded(bool expanded) {
    setState(() => _expanded = expanded);
    if (!expanded && _sheetScroll.hasClients) _sheetScroll.jumpTo(0);
  }

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
                  const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
                      _stepTo(1)?.call(),
                  const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
                      _stepTo(-1)?.call(),
                },
                child: Focus(
                  autofocus: true,
                  child: LayoutBuilder(
                    builder: (context, box) => Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _bar(n, surah),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 350),
                          curve: const Cubic(0.3, 0.7, 0.2, 1),
                          // The design's 318 of 812.
                          height: _expanded ? 58 : box.maxHeight * 0.39,
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(color: n.divider),
                            ),
                          ),
                          clipBehavior: Clip.hardEdge,
                          child: _top(n, surah),
                        ),
                        Expanded(
                          child: _sheet == null
                              ? const SizedBox.shrink()
                              : RootSheet(
                                  sheet: _sheet!,
                                  expanded: _expanded,
                                  previous: _beside(-1),
                                  next: _beside(1),
                                  onPrevious: _stepTo(-1),
                                  onNext: _stepTo(1),
                                  onToggle: () => _setExpanded(!_expanded),
                                  onExpand: () => _setExpanded(true),
                                  onRoot: (letters) =>
                                      _visit(Routes.root, letters),
                                  onJudge: _judgeSense,
                                  onConstellation: (letters) =>
                                      _visit(Routes.deepDive, (
                                        ayahId: _word!.id ~/ 1000,
                                        letters: letters,
                                      )),
                                  onAya: (aya) {
                                    setState(() => _away = aya);
                                    if (_sheetScroll.hasClients) {
                                      _sheetScroll.jumpTo(0);
                                    }
                                  },
                                  scroll: _sheetScroll,
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
                _position(l, surah, word),
                key: const Key('position'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: n.textAt(0.62)),
              ),
            ),
          ValueListenableBuilder<bool>(
            valueListenable: _audio?.playing ?? _paused,
            builder: (context, playing, _) => IconButton(
              // A dark button says why it is dark: the corpus carries no
              // recitation for these ayas, or it is not on the phone yet.
              tooltip: playing
                  ? l.study_pauseRecitation
                  : _audio == null || _audio!.ready
                  ? l.study_recite
                  : _audio!.tracks.isEmpty
                  ? l.study_noRecitation
                  : l.notDownloaded,
              onPressed: _audio?.ready ?? false ? _audio!.toggle : null,
              icon: Icon(
                playing ? Icons.pause : Icons.play_arrow,
                size: 20,
                color: n.color('accent-300'),
              ),
            ),
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
  String _position(AppLocalizations l, StudySet surah, StudyWord word) {
    final ayaId = word.id ~/ 1000;
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
      return _expanded ? _awayStrip(n, away) : _awayFull(n, away);
    }
    return _expanded ? _strip(n) : _list(n, surah);
  }

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
        key: ValueKey(ayas.first.id),
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
          SliverToBoxAdapter(child: SizedBox(height: n.space('8'))),
        ],
      ),
    );
  }

  Widget _ayaTile(Nocturne n, List<StudyAya> ayas, int index, int? recited) {
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
                    onOpen: _open,
                    onHear: _speak,
                  ),
                ),
              AyaMark(
                aya: face.aya,
                arabicSize: _prefs.arabicSize,
                label: l.study_markUnderstood(ayahRef(aya.id)),
                onMark: aya.understood ? null : () => _markUnderstood(aya),
              ),
            ],
          ),
          if (_translated[aya.id] case final rendered?
              when _prefs.ayaTranslation) ...[
            SizedBox(height: n.space('2')),
            Text(
              rendered,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.55,
                color: n.textAt(0.78),
              ),
            ),
            SizedBox(height: n.space('1')),
            Text(
              l.study_ayaTranslated,
              style: TextStyle(fontSize: 10.5, color: n.textAt(0.45)),
            ),
          ],
        ],
      ),
    );
  }

  /// One line: the aya open, and the open word with two either side of it.
  Widget _strip(Nocturne n) {
    final word = _word;
    final words = word == null ? null : _words[word.id ~/ 1000];
    if (word == null || words == null) return const SizedBox.shrink();
    final at = words.indexWhere((w) => w.id == word.id);
    final lo = (at - 2).clamp(0, words.length);
    final hi = (at + 3).clamp(0, words.length);
    final dim = n.textAt(0.4);
    Widget arabic(String text, Color colour, {bool line = false}) => Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: line ? n.accent : Colors.transparent,
            width: 2,
          ),
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: Nocturne.arabicFamily,
          fontSize: 20,
          height: 1.6,
          color: colour,
        ),
      ),
    );
    return GestureDetector(
      key: const Key('strip'),
      behavior: HitTestBehavior.opaque,
      onTap: () => _setExpanded(false),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          spacing: 10,
          children: [
            Text(
              ayahRef(word.id ~/ 1000),
              style: TextStyle(fontSize: 11, color: n.textAt(0.6)),
            ),
            Expanded(
              child: ClipRect(
                child: Row(
                  textDirection: TextDirection.rtl,
                  mainAxisAlignment: MainAxisAlignment.center,
                  spacing: 9,
                  children: [
                    if (lo > 0) arabic('…', dim),
                    for (final w in words.sublist(lo, hi))
                      arabic(
                        w.text,
                        w.id == word.id
                            ? n.color('accent-100')
                            : n.textAt(0.62),
                        line: w.id == word.id,
                      ),
                    if (hi < words.length) arabic('…', dim),
                  ],
                ),
              ),
            ),
            Icon(Icons.expand_more, size: 16, color: n.textAt(0.6)),
          ],
        ),
      ),
    );
  }

  Widget _awayFull(Nocturne n, RootAya away) {
    final l = AppLocalizations.of(context)!;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OutlinedButton.icon(
            key: const Key('back to reading'),
            onPressed: () => setState(() => _away = null),
            icon: const Icon(Icons.chevron_left, size: 14),
            label: Text(l.study_backTo(ayahRef((_word?.id ?? 0) ~/ 1000))),
          ),
          const SizedBox(height: 18),
          Text(
            ayahRef(away.ayahId),
            style: TextStyle(
              fontSize: 10,
              letterSpacing: 1.1,
              color: n.color('accent-300'),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            away.text,
            textDirection: TextDirection.rtl,
            style: TextStyle(
              fontFamily: Nocturne.arabicFamily,
              fontSize: 28,
              height: 1.8,
              color: n.text,
            ),
          ),
          if (away.translation != null) ...[
            const SizedBox(height: 8),
            Text(
              away.translation!,
              style: TextStyle(
                fontSize: 14,
                height: 1.55,
                color: n.textAt(0.78),
              ),
            ),
          ],
          TextButton(
            key: const Key('read from here'),
            onPressed: () => _load(target: away.ayahId),
            child: Text(l.study_readFromHere),
          ),
        ],
      ),
    );
  }

  Widget _awayStrip(Nocturne n, RootAya away) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: Row(
      spacing: 10,
      children: [
        OutlinedButton(
          onPressed: () => setState(() => _away = null),
          child: Text('‹ ${ayahRef((_word?.id ?? 0) ~/ 1000)}'),
        ),
        Text(
          ayahRef(away.ayahId),
          style: TextStyle(fontSize: 11, color: n.color('accent-300')),
        ),
        Expanded(
          child: Text(
            away.text,
            textDirection: TextDirection.rtl,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: Nocturne.arabicFamily,
              fontSize: 18,
              height: 1.6,
              color: n.text,
            ),
          ),
        ),
      ],
    ),
  );

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
    final read = await wordsFor(widget.db, want);
    if (!mounted || generation != _generation) return;
    setState(() => _words.addAll(read));
  }
}
