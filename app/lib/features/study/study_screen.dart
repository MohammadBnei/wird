import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import '../../app.dart';
import '../../data/audio.dart';
import '../../data/db.dart';
import '../../data/sets.dart';
import '../../nav.dart';
import '../../shell/wird_shell.dart';
import '../../theme/nocturne.dart';
import '../../widgets/nocturne_button.dart';
import 'reading_nav.dart';
import 'study_chrome.dart';
import 'word_row.dart';

/// Screen 1a — the set the reader studies before praying it.
class StudyScreen extends StatefulWidget {
  const StudyScreen({super.key, required this.db, this.target});

  final Database db;

  /// The aya to open on, or null to open on the walk's next set.
  ///
  /// The walk's position is derived — the next aya not yet understood — so
  /// visiting an aya costs the reader nothing: marking it counts like any other
  /// mark and the walk recomputes around it.
  final int? target;

  @override
  State<StudyScreen> createState() => _StudyScreenState();
}

class _StudyScreenState extends State<StudyScreen> {
  StudySet? _set;
  RootDetail? _root;
  StudyWord? _word;
  String? _reciter;
  ReadingOrder _order = ReadingOrder.nuzul;

  /// The application's recitation, once it is carrying the set on screen.
  /// Null before then, which is what the word row asks about: a set with no
  /// player yet has no word that will answer a press.
  ///
  /// The screen no longer owns it. It hands over the set and walks away, so a
  /// recitation the reader started here can be seen and stopped from the
  /// shell's transport on any screen they go to next.
  Recitation? _audio;

  /// Minted once here and again after every mark that lands. Two presses of
  /// "Mark set understood" carry one op id and the set is counted once; a
  /// second, different mark — after the reader pulls the set wider — carries a
  /// new one, because an op id already in the outbox is read as that same
  /// press replayed and the write is dropped.
  String _opId = newOpId();

  /// The aya the reader asked for, or null while they are on the walk.
  int? _target;

  /// Which load owns the screen. A load that has been overtaken stops before it
  /// touches either: two of them in flight both prefetch, and a prefetch re-pins
  /// the cache, so the loser would unpin the aya actually on screen and the
  /// sweep would delete the recitation of the aya the reader is listening to.
  int _generation = 0;

  bool _loaded = false;

  /// The sets either side of this one in the written order, or null at the
  /// two ends of the Qur'an, which are the only places a step has nowhere to
  /// go. A span rather than an aya, because the footer moves by the set.
  AyaSpan? _before;
  AyaSpan? _after;

  /// How many ayas the reader takes at once, kept so a step hands over that
  /// many. It is not read back off the span the arrow printed: a span stops
  /// at the sūra's edge, so a step into Al-Kawthar's three ayas would
  /// otherwise shrink every step after it to three.
  int _width = 1;

  /// Which words the phone can sound, worked out once rather than at render
  /// time — it used to be an `existsSync` per word per frame. Rebuilt at the
  /// three moments it can change: the set arrives, a download lands, an aya is
  /// marked.
  Set<int> _speakable = const {};

  /// The words of the passage, by aya, as far as they have been read. A sūra
  /// arrives as ayas alone and its words come a chunk at a time, because
  /// Al-Baqarah is 6116 of them and the screen shows twenty.
  Map<int, List<StudyWord>> _words = {};

  /// Ayas whose words are on their way. Without it the list asks for the same
  /// chunk on every frame it draws a gap.
  final _pending = <int>{};

  /// Where the passage hangs from. Everything before it in the sliver list
  /// grows upward, so opening Al-Baqarah at 255 costs nothing for the 254
  /// ayas above and the reader can still move up into them.
  static const _anchor = ValueKey('reading-anchor');

  /// The word whose transliteration stands in for audio it cannot play. One
  /// word at a time, and never a snackbar: 2:282 is 128 words, and tapping
  /// through them must not queue 128 of anything.
  int? _unheard;

  /// Stand-ins for the set that has no audio yet, so the bar and the ayas
  /// have something to listen to before the first set is read.
  static final _silent = ValueNotifier<int?>(null);
  static final _paused = ValueNotifier<bool>(false);

  /// Every aya in the set is understood, so marking it again would write
  /// nothing and the only thing left to do is walk on.
  bool _allUnderstood(StudySet set) => set.ayas.every((a) => a.understood);

  void _bake() => _speakable = _audio?.speakable ?? const {};

  Prefs get _prefs => Wird.of(context).prefs;
  double get _arabicSize => _prefs.arabicSize;

  /// The set is read here rather than in initState because the reader's order
  /// and the recitation are reached through the application above this screen.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) _load(target: widget.target);
  }

  /// Reads what the screen shows: the walk's next set, the portion a footer
  /// [step] hands over, or the aya at [target]. Everything after the set
  /// itself — the reciter, the root panel's first root, the recitation — is
  /// the same either way. What is downloaded is not, which is what
  /// `onTheWalk` says.
  ///
  /// A step arrives as the whole span its arrow printed rather than as a place
  /// and a count worked out again here: [_span] is the one rule for what a
  /// step is. It carries no grain with it, so a step into a short sūra takes
  /// the ayas that are there without narrowing the one after it.
  ///
  /// A reference — a kin, a row in the index — passes [target] and gets the
  /// one aya it named, which is ADR 0003 and has not moved.
  Future<void> _load({int? target, AyaSpan? step}) async {
    final generation = ++_generation;
    final recitation = Wird.of(context).recitation;
    final order = _prefs.order;
    final at = step?.first ?? target;
    final set = at == null
        ? await nextSet(widget.db, order)
        : await ayaSet(
            widget.db,
            order,
            at,
            ayas: step == null ? 1 : step.last - step.first + 1,
          );
    final reciter = await reciterLabel(widget.db);
    // The width the reader reads in. On the walk the set already is it, the
    // width they pulled in settings and all. A step keeps the width it was
    // taken at rather than the width it got — a step into Al-Kawthar takes
    // the three ayas there and must not shrink the reader's grain to three.
    // A visit's one aya is a reference and not a width, so it asks.
    final width = set == null
        ? 1
        : step != null
        ? _width
        : target == null
        ? set.ayas.length
        : await readingWidth(widget.db, order);
    final before = set == null
        ? null
        : await _span(
            await ayaBeside(widget.db, set.ayas.first.id, after: false),
            width,
            after: false,
          );
    final after = set == null
        ? null
        : await _span(
            await ayaBeside(widget.db, set.ayas.last.id, after: true),
            width,
            after: true,
          );
    final rooted =
        set?.ayas
            .expand((a) => a.words)
            .where((w) => w.root != null)
            .toList() ??
        const <StudyWord>[];
    final first = rooted.isEmpty ? null : rooted.first;
    final root = first == null
        ? null
        : await rootDetail(widget.db, first.root!);
    final keep = set == null
        ? const <String>[]
        : await pathsToKeep(widget.db, order, set, onTheWalk: at == null);
    if (set != null) {
      await recitation.carry(
        await tracksFor(widget.db, [for (final aya in set.ayas) aya.id]),
        title: set.title,
        words: {
          for (final aya in set.ayas)
            for (final word in aya.words) word.id: word.text,
        },
      );
    }
    if (!mounted || generation != _generation) return;
    setState(() {
      _order = order;
      _target = at;
      _before = before;
      _after = after;
      _width = width;
      _set = set;
      _reciter = reciter;
      _word = first;
      _root = root;
      _audio = set == null ? null : recitation;
      _loaded = true;
      _pending.clear();
      _words = {
        for (final aya in set?.reading ?? const <StudyAya>[])
          if (aya.words.isNotEmpty) aya.id: aya.words,
      };
      _bake();
    });
    if (set == null) return;
    // The download runs behind the set rather than in front of it: the reader
    // studies while the recitation arrives, and an aeroplane leaves the screen
    // working with the play button honestly dark.
    await recitation.prefetch(keep);
    if (mounted && generation == _generation) setState(_bake);
  }

  /// The set on one side of the reading, grown from the aya next to its edge.
  ///
  /// It is [width] ayas wide and stops at the sūra's edge: a step into
  /// Al-Kawthar takes the three ayas that are there. That the edge aya itself
  /// may belong to the next sūra is deliberate — see [ayaBeside].
  Future<AyaSpan?> _span(int? edge, int width, {required bool after}) async {
    if (edge == null) return null;
    final surahId = edge ~/ 1000;
    final number = edge % 1000;
    final first = after ? number : max(1, number - width + 1);
    final last = after
        ? min(number + width - 1, await ayahCount(widget.db, surahId))
        : number;
    return (first: surahId * 1000 + first, last: surahId * 1000 + last);
  }

  /// Marks what is open in the set and stays on it.
  ///
  /// An aya the set was pulled across is already understood and is left out:
  /// it was recited along with the rest, and re-marking it would move the day
  /// the reader understood it to today. The flags are refreshed in place
  /// because they are baked at load — without that the progress bars would go
  /// on calling a marked aya open.
  Future<void> _markUnderstood(StudySet set) async {
    final open = [
      for (final aya in set.ayas)
        if (!aya.understood) aya.id,
    ];
    if (open.isEmpty) return;
    await markSetUnderstood(widget.db, _opId, open);
    if (!mounted) return;
    setState(() {
      _set = set.withUnderstood(open.toSet());
      _opId = newOpId();
      _bake();
    });
  }

  /// Sounds one word. An aya that was never downloaded shows the word's
  /// transliteration under it and plays nothing — it must never spin, and it
  /// must not shout.
  Future<void> _speak(StudyWord word) async {
    final sounded = await _audio?.playWord(word.id) ?? false;
    if (mounted) setState(() => _unheard = sounded ? null : word.id);
  }

  /// Pushes a screen that reads a root, and takes the aya it answers with.
  ///
  /// A root, its spine and the constellation all print aya references, and a
  /// reference answers by popping the aya down to here rather than by stacking
  /// a second reader over this one — ADR-0003. This is the screen that catches
  /// it, and it changes in place, exactly as a kin tag in the panel does.
  Future<void> _visit(String route, Object arguments) async {
    final chosen = await Navigator.of(context)
        .pushNamed(route, arguments: arguments);
    if (mounted && chosen is int) await _load(target: chosen);
  }

  /// The panel keeps the root it is showing until the next one has been read,
  /// so a tap never blanks the screen the reader is looking at.
  Future<void> _openRoot(StudyWord word) async {
    final detail = await rootDetail(widget.db, word.root!);
    if (!mounted || detail == null) return;
    setState(() {
      _word = word;
      _root = detail;
    });
  }

  @override
  Widget build(BuildContext context) {
    final n = Nocturne.of(context);
    final set = _set;
    // The display mode and the Arabic size are set on the settings screen and
    // held by the application, so the words redraw when the reader comes back
    // from having changed them.
    return ListenableBuilder(
      listenable: _prefs,
      builder: (context, _) => SafeArea(
        child: !_loaded
            ? const SizedBox.shrink()
            : set == null
            ? _finished(n)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  StudyHeader(
                    key: const Key('study header'),
                    set: set,
                    order: _order,
                    visiting: _target != null,
                    open: _prefs.headerOpen,
                    onToggle: () => _prefs.setHeaderOpen(!_prefs.headerOpen),
                    onBackToTheWalk: () => _load(),
                  ),
                  Expanded(child: _reading(n, set)),
                  _footer(n, set),
                  RootPanel(
                    root: _root,
                    word: _word,
                    open: _prefs.rootOpen,
                    onToggle: () => _prefs.setRootOpen(!_prefs.rootOpen),
                    onVisit: _visit,
                    onKin: (ayahId) => _load(target: ayahId),
                    allUnderstood: _allUnderstood(set),
                    onMark: _allUnderstood(set)
                        ? () => _load()
                        : () => _markUnderstood(set),
                  ),
                ],
              ),
      ),
    );
  }

  /// What is sounding, and where the reader can go: one block at the foot of
  /// the screen, under one edge.
  ///
  /// The transport used to sit under the top bar, a thumb's length from the
  /// controls it belongs with. It is first in the block rather than last
  /// because a [Column] hangs its tail off the bottom: everything below the
  /// transport keeps its place when a recitation starts, and the reading gives
  /// up the height instead. Nothing under the reader's thumb moves.
  Widget _footer(Nocturne n, StudySet set) => Container(
    decoration: BoxDecoration(
      border: Border(top: BorderSide(color: n.divider)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: n.space('6')),
          child: const SoundingNow(),
        ),
        ReadingNav(
          surahId: set.ayas.first.surahId,
          previous: _before,
          next: _after,
          onStep: (to) => _load(step: to),
          onIndex: () => _visit(Routes.index, const AStepFrom()),
        ),
      ],
    ),
  );

  Widget _finished(Nocturne n) => Center(
    child: Padding(
      padding: EdgeInsets.all(n.space('8')),
      child: Text(
        'Every aya is understood. There is nothing left to serve.',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.headlineSmall,
      ),
    ),
  );

  /// The passage, hung from the aya the reader opened on.
  ///
  /// An aya is built when it comes near the viewport and not before: the walk
  /// serves five ayas, but a sūra is up to 286 and Al-Baqarah's 6116 words
  /// laid out in one `Column` is a frame no phone can draw. The slivers before
  /// [_anchor] grow upward, which is what lets the screen open at 2:255
  /// without building the 254 ayas above it and still let the reader move up
  /// into them — a sūra is continuous.
  Widget _reading(Nocturne n, StudySet set) {
    final ayas = set.reading;
    final focus = set.focusIndex;
    return ValueListenableBuilder<int?>(
      valueListenable: _audio?.currentWordId ?? _silent,
      builder: (context, recited, _) => CustomScrollView(
        // A new passage starts at its own aya rather than at the offset the
        // last one was left scrolled to.
        key: ValueKey(set.ayas.first.id),
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
              (context, i) => i == set.ayas.length
                  // The recitation carries the acted set and nothing else, so
                  // the bar sits where that set ends: under the last aya on
                  // the walk, and under the visited aya rather than 285 ayas
                  // below it while a sūra is being read.
                  ? Padding(
                      padding: EdgeInsets.symmetric(horizontal: n.space('6')),
                      child: _audioBar(n),
                    )
                  : _ayaTile(
                      n,
                      ayas,
                      focus + (i > set.ayas.length ? i - 1 : i),
                      recited,
                      lastBeforeBar: focus + set.ayas.length - 1,
                    ),
              childCount: ayas.length - focus + 1,
            ),
          ),
          SliverToBoxAdapter(child: SizedBox(height: n.space('6'))),
        ],
      ),
    );
  }

  Widget _ayaTile(
    Nocturne n,
    List<StudyAya> ayas,
    int index,
    int? recited, {
    int lastBeforeBar = -1,
  }) {
    final aya = ayas[index];
    final words = _words[aya.id];
    if (words == null) {
      _readWordsAround(index, ayas);
      // ponytail: a word is about 28 px of column once it has wrapped. The
      // guess only has to keep an aya above the reader from shoving the one
      // they are reading when its words land, and the chunk read ahead means
      // the gap is rarely drawn at all. Measure a tile if scrolling up ever
      // jumps.
      return SizedBox(height: 28.0 * aya.wordCount);
    }
    final face = faceOf(aya, words, _speakable);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: n.space('6')),
      child: Column(
        children: [
          if (index == 0)
            SizedBox(height: n.space('6'))
          else
            Padding(
              padding: EdgeInsets.symmetric(vertical: n.space('2')),
              child: const DashedRule(),
            ),
          Wrap(
            textDirection: TextDirection.rtl,
            alignment: WrapAlignment.center,
            // Tops, so the Arabic of a word carrying a two-line gloss stays
            // in line with its neighbours and the gloss hangs below at
            // whatever height it needs.
            crossAxisAlignment: WrapCrossAlignment.start,
            spacing: n.space('6'),
            runSpacing: n.space('1'),
            children: [
              for (final word in face.words)
                WordTile(
                  // Keyed by the corpus id so the tile keeps its element
                  // across a rebuild, rather than being matched by position
                  // against a different word.
                  key: WordKey(word.word.id),
                  face: word,
                  voice: word.voice(sounding: recited, unheard: _unheard),
                  open: word.word.id == _word?.id,
                  prefs: _prefs,
                  onOpen: _openRoot,
                  onHear: _speak,
                ),
              AyaMark(aya: face.aya, arabicSize: _arabicSize),
            ],
          ),
          if (index == lastBeforeBar || index == ayas.length - 1)
            SizedBox(height: n.space('6')),
        ],
      ),
    );
  }

  /// Reads the words of the ayas around [index], a chunk at a time.
  ///
  /// The chunk reaches further down than up because that is the direction a
  /// reader moves, and it is one query however many ayas it covers: a query
  /// per aya would be 286 of them to read Al-Baqarah.
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

  Widget _audioBar(Nocturne n) => Container(
    padding: EdgeInsets.symmetric(
      horizontal: n.space('3'),
      vertical: n.space('2'),
    ),
    decoration: BoxDecoration(
      color: n.surface,
      borderRadius: BorderRadius.circular(n.radius('md')),
      boxShadow: n.shadow('sm'),
    ),
    child: Row(
      spacing: n.space('3'),
      children: [
        ValueListenableBuilder<bool>(
          valueListenable: _audio?.playing ?? _paused,
          builder: (context, playing, _) => NocturneButton(
            variant: NocturneButtonVariant.icon,
            onPressed: _audio?.ready ?? false ? _audio!.toggle : null,
            child: Icon(playing ? Icons.pause : Icons.play_arrow),
          ),
        ),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            spacing: n.space('1'),
            children: [
              for (final (i, height) in const [
                20.0,
                14.0,
                18.0,
                9.0,
                6.0,
              ].indexed)
                Container(
                  width: 2.5,
                  height: height,
                  decoration: BoxDecoration(
                    color: i < 3
                        ? n.accent
                        : n.color(i == 3 ? 'accent-600' : 'accent-700'),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(bottom: n.space('3')),
                  child: const DashedRule(),
                ),
              ),
            ],
          ),
        ),
        Text(
          (_audio?.ready ?? false) ? (_reciter ?? '') : 'Not downloaded',
          style: TextStyle(fontSize: 10.5, color: n.textAt(0.55)),
        ),
      ],
    ),
  );
}
