import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import '../../data/audio.dart';
import '../../data/db.dart';
import '../../data/mic.dart';
import '../../data/sets.dart';
import '../../nav.dart';
import '../../theme/nocturne.dart';
import '../../widgets/nocturne_button.dart';
import '../../widgets/nocturne_segmented.dart';
import '../../widgets/nocturne_tag.dart';
import '../settings/parked_writes.dart';

/// Screen 1a — the set the reader studies before praying it.
class StudyScreen extends StatefulWidget {
  const StudyScreen({
    super.key,
    required this.db,
    this.target,
    this.audioCache,
  });

  final Database db;

  /// The aya to open on, or null to open on the walk's next set.
  ///
  /// The walk's position is derived — the next aya not yet understood — so
  /// visiting an aya costs the reader nothing: marking it counts like any other
  /// mark and the walk recomputes around it.
  final int? target;

  /// Where the recitation is downloaded to. Supplied by the test that has to
  /// prove the screen works with the radio off.
  final AudioCache? audioCache;

  @override
  State<StudyScreen> createState() => _StudyScreenState();
}

class _StudyScreenState extends State<StudyScreen> {
  StudySet? _set;
  RootDetail? _root;
  StudyWord? _word;
  String? _reciter;
  ReadingOrder _order = ReadingOrder.nuzul;
  MicPermission _mic = MicPermission.notAsked;
  SetAudio? _audio;

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

  /// Minted once for the screen rather than once per load. A second cache
  /// carries a pin list of its own and knows nothing of the first's, so it
  /// deletes files the first pinned.
  Future<AudioCache>? _cache;

  bool _loaded = false;

  /// The word whose transliteration stands in for audio it cannot play. One
  /// word at a time, and never a snackbar: 2:282 is 128 words, and tapping
  /// through them must not queue 128 of anything.
  int? _unheard;
  bool _settingsOpen = false;
  int _display = 0;
  double _arabicSize = 31;

  /// Stand-ins for the set that has no audio yet, so the bar and the ayas
  /// have something to listen to before the first set is read.
  static final _silent = ValueNotifier<int?>(null);
  static final _paused = ValueNotifier<bool>(false);

  String get _micCaption => switch (_mic) {
    MicPermission.notAsked =>
      'Voice-follow needs the microphone. Off by '
          'default; never asked for during a prayer.',
    MicPermission.granted =>
      'Microphone allowed. Voice-follow stays off '
          'until you turn it on.',
    MicPermission.denied =>
      'Microphone refused. The prayer screen advances '
          'on a tap, as it always does.',
    MicPermission.unavailable =>
      'This build cannot reach the microphone. The prayer screen advances on '
          'a tap.',
  };

  /// Every aya in the set is understood, so marking it again would write
  /// nothing and the only thing left to do is walk on.
  bool _allUnderstood(StudySet set) => set.ayas.every((a) => a.understood);

  bool get _showGloss => _display == 0 || _display == 2;
  bool get _showTranslit => _display == 1 || _display == 2;

  @override
  void initState() {
    super.initState();
    _load(target: widget.target);
  }

  @override
  void dispose() {
    unawaited(_audio?.dispose());
    super.dispose();
  }

  /// Reads what the screen shows: the walk's next set, or the one aya at
  /// [target]. Everything after the set itself — the reciter, the microphone,
  /// the root panel's first root, the audio — is the same either way. What is
  /// downloaded is not, which is what `onTheWalk` says.
  Future<void> _load({int? target}) async {
    final generation = ++_generation;
    final order = await readingOrder(widget.db);
    final set = target == null
        ? await nextSet(widget.db, order)
        : await ayaSet(widget.db, order, target);
    final reciter = await reciterLabel(widget.db);
    final mic = await micPermission(widget.db);
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
        : await pathsToKeep(widget.db, order, set, onTheWalk: target == null);
    final audio = set == null
        ? null
        : SetAudio(
            cache: await _audioCache(),
            tracks: await tracksFor(widget.db, [
              for (final aya in set.ayas) aya.id,
            ]),
          );
    if (!mounted || generation != _generation) {
      unawaited(audio?.dispose());
      return;
    }
    unawaited(_audio?.dispose());
    setState(() {
      _order = order;
      _target = target;
      _set = set;
      _reciter = reciter;
      _mic = mic;
      _word = first;
      _root = root;
      _audio = audio;
      _loaded = true;
    });
    if (audio == null) return;
    // The download runs behind the set rather than in front of it: the reader
    // studies while the recitation arrives, and an aeroplane leaves the screen
    // working with the play button honestly dark.
    await audio.cache.prefetch(keep);
    if (mounted && identical(_audio, audio)) setState(() {});
  }

  Future<AudioCache> _audioCache() => _cache ??= widget.audioCache == null
      ? getDatabasesPath().then(AudioCache.beside)
      : Future.value(widget.audioCache!);

  /// Opens a screen that may hand back an aya to read.
  ///
  /// 1a is at the bottom of the stack, so a screen above it names the aya the
  /// reader chose by popping its id down rather than by pushing a second 1a.
  Future<void> _openFor(String route) async {
    final chosen = await Navigator.of(context).pushNamed(route);
    if (mounted && chosen is int) await _load(target: chosen);
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
      _set = StudySet(order: set.order, [
        for (final aya in set.ayas) aya.asUnderstood(),
      ]);
      _opId = newOpId();
    });
  }

  /// Pulls the set's end out or back in. The width is remembered against the
  /// aya the set starts at, so leaving the screen does not discard it.
  Future<void> _resize(StudySet set, int by) async {
    await setDragSpan(widget.db, set.ayas.first.id, set.ayas.length + by);
    await _load();
  }

  /// Screen 1b writes nothing: it runs inside the prayer, where there is no
  /// safe moment for a database write. So the prayer is recorded here, when
  /// the reader comes back from it — `pushNamed` completes however 1b was
  /// left, by the Exit button, the back-swipe or Android's back, so no gesture
  /// loses the prayer and 1b needs to know nothing about any of them.
  ///
  /// A prayer the reader never returns from — the app killed mid-prayer — is
  /// not recorded. That is the price of 1b writing nothing, and it is the side
  /// to be wrong on: the prayer count is allowed to be short, never invented.
  Future<void> _prayThisSet(StudySet set) async {
    await Navigator.of(context).pushNamed(Routes.prayer, arguments: set);
    if (!mounted) return;
    await recordSetPrayed(widget.db, set);
  }

  /// A tap speaks one word. An aya that was never downloaded shows the word's
  /// transliteration under it and plays nothing — it must never spin, and it
  /// must not shout.
  Future<void> _speak(StudyWord word) async {
    final sounded = await _audio?.playWord(word.id) ?? false;
    if (mounted) setState(() => _unheard = sounded ? null : word.id);
  }

  Future<void> _chooseOrder(ReadingOrder order) async {
    await setReadingOrder(widget.db, order);
    await _load();
  }

  Future<void> _askForMic() async {
    final answer = await askForMic(widget.db);
    if (mounted) setState(() => _mic = answer);
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
    return Scaffold(
      backgroundColor: n.bg,
      body: SafeArea(
        child: !_loaded
            ? const SizedBox.shrink()
            : set == null
            ? _finished(n)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _header(n, set),
                  _progress(n, set),
                  if (_settingsOpen) _settings(n),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          _ayas(n, set),
                          Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: n.space('6'),
                            ),
                            child: _audioBar(n),
                          ),
                          SizedBox(height: n.space('6')),
                        ],
                      ),
                    ),
                  ),
                  _rootPanel(n, set),
                ],
              ),
      ),
    );
  }

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

  Widget _header(Nocturne n, StudySet set) {
    final first = set.ayas.first;
    final place = first.revelationPlace;
    final where = _order == ReadingOrder.nuzul
        ? 'Revelation ${first.revelationOrder} · ${_capitalise(place)}'
        : 'Sūra ${first.surahId} · ${_capitalise(place)}';
    // An aya the reader asked for is not where the walk left them, and nothing
    // else on the screen says so. Without this the only way back to the walk
    // would be to mark the visited aya understood.
    final kicker = _target == null ? where : 'Visiting · $where';
    return Padding(
      padding: EdgeInsets.fromLTRB(n.space('6'), n.space('2'), n.space('6'), 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  kicker.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    height: 1.2,
                    letterSpacing: 0.11 * 10,
                    color: n.accent,
                  ),
                ),
                SizedBox(height: n.space('1')),
                Text(
                  set.title,
                  style: Theme.of(context).textTheme.displaySmall,
                ),
                SizedBox(height: n.space('1')),
                Text(
                  first.surahNameAr,
                  textDirection: TextDirection.rtl,
                  style: TextStyle(
                    fontFamily: Nocturne.arabicFamily,
                    fontSize: 13,
                    color: n.textAt(0.5),
                  ),
                ),
              ],
            ),
          ),
          if (_target != null)
            NocturneButton(
              variant: NocturneButtonVariant.ghost,
              onPressed: () => _load(),
              child: const Text(
                'Back to the walk',
                style: TextStyle(fontSize: 11),
              ),
            ),
          NocturneButton(
            variant: NocturneButtonVariant.icon,
            child: const Icon(Icons.bookmark_border),
          ),
          SizedBox(width: n.space('1')),
          NocturneButton(
            variant: NocturneButtonVariant.icon,
            onPressed: () => setState(() => _settingsOpen = !_settingsOpen),
            child: const Icon(Icons.tune),
          ),
        ],
      ),
    );
  }

  Widget _progress(Nocturne n, StudySet set) => Padding(
    padding: EdgeInsets.fromLTRB(n.space('6'), n.space('6'), n.space('6'), 0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          spacing: n.space('2'),
          children: [
            for (final aya in set.ayas)
              Expanded(
                child: Container(
                  height: 3,
                  decoration: BoxDecoration(
                    color: aya.understood ? n.accent : n.color('neutral-800'),
                    borderRadius: BorderRadius.circular(2),
                    boxShadow: aya.understood
                        ? [
                            BoxShadow(
                              color: n.accent.withValues(alpha: 0.6),
                              blurRadius: 10,
                            ),
                          ]
                        : null,
                  ),
                ),
              ),
          ],
        ),
        SizedBox(height: n.space('2')),
        Text(
          _progressCaption(set.ayas),
          style: TextStyle(fontSize: 10.5, color: n.textAt(0.42)),
        ),
      ],
    ),
  );

  Widget _settings(Nocturne n) => Padding(
    padding: EdgeInsets.fromLTRB(n.space('6'), n.space('4'), n.space('6'), 0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        NocturneSegmented(
          options: const ['Gloss', 'Translit', 'Both', 'Neither'],
          selected: _display,
          onChanged: (i) => setState(() => _display = i),
        ),
        SizedBox(height: n.space('2')),
        NocturneSegmented(
          options: const ['Chronological', 'Muṣḥaf'],
          selected: _order.index,
          onChanged: (i) => _chooseOrder(ReadingOrder.values[i]),
        ),
        SizedBox(height: n.space('1')),
        Text(
          'The chronology orders sūras; ayas inside a sūra stay in written '
          'order.',
          style: TextStyle(fontSize: 10.5, color: n.textAt(0.42)),
        ),
        SizedBox(height: n.space('2')),
        // Voice-follow is a later phase and off by default. The microphone is
        // asked for here and only here: the in-prayer screen may not raise a
        // dialog, so it can never be the screen that asks.
        Row(
          spacing: n.space('3'),
          children: [
            NocturneButton(
              onPressed: _askForMic,
              child: const Text('Allow microphone'),
            ),
            Expanded(
              child: Text(
                _micCaption,
                style: TextStyle(fontSize: 10.5, color: n.textAt(0.55)),
              ),
            ),
          ],
        ),
        Row(
          children: [
            Text(
              'Arabic ${_arabicSize.round()} px',
              style: TextStyle(fontSize: 11, color: n.textAt(0.55)),
            ),
            Expanded(
              child: SliderTheme(
                data: SliderThemeData(
                  activeTrackColor: n.accent,
                  inactiveTrackColor: n.color('neutral-800'),
                  thumbColor: n.accent,
                  overlayColor: n.accent.withValues(alpha: 0.12),
                  trackHeight: 2,
                ),
                child: Slider(
                  min: 24,
                  max: 44,
                  divisions: 20,
                  value: _arabicSize,
                  onChanged: (v) => setState(() => _arabicSize = v),
                ),
              ),
            ),
          ],
        ),
        // The set's width is the reader's, not the walk's: five ayas inside
        // the word budget is what the walk proposes, and this is where the
        // reader says otherwise. Drawn here rather than as a handle on the set
        // itself because the design draws no handle, and 1a's chrome is fixed
        // by its acceptance row.
        // The width is remembered against the aya the set starts at, so a set
        // pulled wider while merely visiting an aya would change what the walk
        // proposes when it reaches that aya months later. The handle belongs to
        // the walk's own set.
        if (_set case final set? when _target == null)
          Row(
            spacing: n.space('3'),
            children: [
              NocturneButton(
                key: const Key('narrow set'),
                variant: NocturneButtonVariant.icon,
                onPressed: _allUnderstood(set) || set.ayas.length == 1
                    ? null
                    : () => _resize(set, -1),
                child: const Icon(Icons.remove),
              ),
              Text(
                set.ayas.length == 1 ? '1 aya' : '${set.ayas.length} ayas',
                style: TextStyle(fontSize: 11, color: n.textAt(0.55)),
              ),
              NocturneButton(
                key: const Key('widen set'),
                variant: NocturneButtonVariant.icon,
                onPressed:
                    _allUnderstood(set) || set.ayas.length >= setMaxDragAyas
                    ? null
                    : () => _resize(set, 1),
                child: const Icon(Icons.add),
              ),
              Expanded(
                child: Text(
                  'A wider set may cross an aya you already understood. It is '
                  'recited with the rest and stays counted where it is.',
                  style: TextStyle(fontSize: 10.5, color: n.textAt(0.55)),
                ),
              ),
            ],
          ),
        // The prayer, the progress and the kept list are drawn nowhere in the
        // design, and 1a's chrome is fixed by its acceptance row, so they hang
        // here beside the other controls the design does not draw.
        Wrap(
          spacing: n.space('2'),
          runSpacing: n.space('2'),
          children: [
            NocturneButton(
              onPressed: _set == null ? null : () => _prayThisSet(_set!),
              child: const Text('Pray this set'),
            ),
            NocturneButton(
              onPressed: () => _openFor(Routes.progress),
              child: const Text('Your passage'),
            ),
            NocturneButton(
              onPressed: () => Navigator.of(context).pushNamed(Routes.kept),
              child: const Text('Kept'),
            ),
            // The walk is otherwise the only way into the text: a reader who
            // wants Al-Fātiḥa, or the aya they were thinking about, asks here.
            NocturneButton(
              onPressed: () => _openFor(Routes.index),
              child: const Text('Sūra index'),
            ),
          ],
        ),
        // Writes the server would not take are named here and only here.
        // Quiet when there are none.
        ParkedWrites(db: widget.db),
        SizedBox(height: n.space('2')),
        // The corpus grants its use on the condition that its source is named
        // and linked where a user can reach it. This is that door.
        NocturneButton(
          block: true,
          onPressed: () => Navigator.of(context).pushNamed(Routes.about),
          child: const Text('Sources and licences'),
        ),
      ],
    ),
  );

  Widget _ayas(Nocturne n, StudySet set) {
    // Read once per set rather than per word per frame: this builder runs
    // every 40 ms while the recitation plays, and the answer is a question
    // about files on disk.
    final speakable = _audio?.speakable ?? const <int>{};
    return ValueListenableBuilder<int?>(
      valueListenable: _audio?.currentWordId ?? _silent,
      builder: (context, recited, _) => Padding(
        padding: EdgeInsets.all(n.space('6')),
        child: Column(
          children: [
            for (final (i, aya) in set.ayas.indexed) ...[
              if (i > 0)
                Padding(
                  padding: EdgeInsets.symmetric(vertical: n.space('2')),
                  child: const _DashedRule(),
                ),
              Wrap(
                textDirection: TextDirection.rtl,
                alignment: WrapAlignment.center,
                // Tops, so the Arabic of a word carrying a two-line gloss
                // stays in line with its neighbours and the gloss hangs below
                // at whatever height it needs.
                crossAxisAlignment: WrapCrossAlignment.start,
                spacing: n.space('6'),
                runSpacing: n.space('1'),
                children: [
                  for (final word in aya.words)
                    _wordTile(n, word, recited, speakable),
                  _ayaMark(n, aya.number, aya.understood),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// The underline says the word can be HEARD, which is what a tap now does.
  /// An aya nobody has downloaded is left plain: the row has to be honest
  /// that tapping those words will play nothing.
  Widget _wordTile(
    Nocturne n,
    StudyWord word,
    int? recited,
    Set<int> speakable,
  ) {
    final sounding = word.id == recited;
    final underline = sounding
        ? n.accent
        : speakable.contains(word.id)
        ? n.color('accent-700')
        : Colors.transparent;
    return GestureDetector(
      // Keyed by the corpus id so the tile keeps its element across a rebuild,
      // rather than being matched by position against a different word.
      key: ValueKey(word.id),
      onTap: () => _speak(word),
      onLongPress: word.root == null ? null : () => _openRoot(word),
      child: Container(
        padding: EdgeInsets.all(n.space('1')),
        decoration: BoxDecoration(
          color: sounding
              ? n.accent.withValues(alpha: 0.16)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(n.radius('sm')),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // The line belongs to the Arabic rather than to the tile: on the
            // tile it sits under the gloss, and a two-line gloss drops it out
            // of the row.
            Container(
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: underline, width: 2)),
              ),
              child: Text(
                word.text,
                textDirection: TextDirection.rtl,
                style: TextStyle(
                  fontFamily: Nocturne.arabicFamily,
                  fontSize: _arabicSize,
                  height: 1.75,
                  color: n.text,
                ),
              ),
            ),
            if ((_showTranslit || word.id == _unheard) && word.translit != null)
              Text(
                word.translit!,
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 9.5,
                  letterSpacing: 0.02 * 9.5,
                  color: n.color('accent-400'),
                ),
              ),
            if (_showGloss && word.gloss != null)
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 88),
                child: Text(
                  word.gloss!,
                  textDirection: TextDirection.ltr,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.25,
                    color: n.textAt(0.66),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// [understood] marks an aya the set was pulled across: it is recited with
  /// the rest, and its mark is lit to say it is already counted.
  ///
  /// The row aligns tops, so the mark is let down onto the Arabic's baseline
  /// by hand — a line box of 1.75 puts the baseline about 1.175 em below its
  /// top, and the tile's own padding sits above that. Centred on the line box
  /// instead it floats above the words, which is not where the design draws
  /// it.
  Widget _ayaMark(Nocturne n, int number, bool understood) => Container(
    width: 26,
    height: 26,
    margin: EdgeInsets.only(top: n.space('1') + _arabicSize * 1.175 - 13),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: understood ? n.accent.withValues(alpha: 0.16) : Colors.transparent,
      border: Border.all(
        color: n.color(understood ? 'accent-300' : 'accent-700'),
      ),
    ),
    child: Text(
      _arabicDigits(number),
      textDirection: TextDirection.rtl,
      style: TextStyle(
        fontFamily: Nocturne.arabicFamily,
        fontSize: 12,
        color: n.color('accent-300'),
      ),
    ),
  );

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
                  child: const _DashedRule(),
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

  Widget _rootPanel(Nocturne n, StudySet set) {
    final root = _root;
    final letters = _word?.root;
    return Container(
      padding: EdgeInsets.fromLTRB(
        n.space('6'),
        n.space('4'),
        n.space('6'),
        n.space('8'),
      ),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: n.divider)),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: const [0, 0.7],
          colors: [
            n.accent.withValues(alpha: 0.07),
            n.accent.withValues(alpha: 0),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (root == null)
            Text(
              'No word in this set carries a root.',
              style: TextStyle(fontSize: 13, color: n.textAt(0.62)),
            )
          else ...[
            // The design reaches 3a by tapping a word in 1a, but the word's
            // gestures are spoken for — a tap speaks it, a long press swaps
            // this panel — so the root the panel names opens the root screen.
            GestureDetector(
              key: const ValueKey('open-root'),
              behavior: HitTestBehavior.opaque,
              onTap: letters == null
                  ? null
                  : () =>
                        Navigator.of(context)
                            .pushNamed(Routes.root, arguments: letters),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    root.display,
                    textDirection: TextDirection.rtl,
                    style: TextStyle(
                      fontFamily: Nocturne.arabicFamily,
                      fontSize: 26,
                      letterSpacing: 0.14 * 26,
                      color: n.color('accent-300'),
                    ),
                  ),
                  SizedBox(width: n.space('3')),
                  Expanded(
                    child: Text(
                      root.translit,
                      style: TextStyle(
                        fontSize: 11,
                        letterSpacing: 0.06 * 11,
                        color: n.textAt(0.55),
                      ),
                    ),
                  ),
                  NocturneTag(
                    '${root.occurrences}×',
                    variant: NocturneTagVariant.outline,
                  ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(vertical: n.space('3')),
              child: const _DashedRule(),
            ),
            // The design's "core sense" prose is lexicon text, which arrives
            // over the network in a later phase. What the corpus itself knows
            // about this word is its gloss in this aya, so that is what the
            // section says it is.
            // "Open constellation" used to sit beside "Mark set understood"
            // at equal weight. One of the two moves the reader through the
            // Qur'an and the other is an occasional detour, so the detour is
            // demoted into the panel it belongs to and the bottom of the screen
            // carries one action.
            Row(
              children: [
                Expanded(
                  child: Text(
                    'IN THIS AYA',
                    style: TextStyle(
                      fontSize: 10,
                      letterSpacing: 0.11 * 10,
                      color: n.accent,
                    ),
                  ),
                ),
                if (letters != null)
                  NocturneButton(
                    variant: NocturneButtonVariant.ghost,
                    onPressed: () => Navigator.of(context).pushNamed(
                      Routes.deepDive,
                      arguments: (ayahId: _word!.id ~/ 1000, letters: letters),
                    ),
                    child: const Text(
                      'Constellation',
                      style: TextStyle(fontSize: 11),
                    ),
                  ),
              ],
            ),
            SizedBox(height: n.space('1')),
            Text(
              _word?.gloss ?? '—',
              style: TextStyle(fontSize: 13.5, height: 1.5, color: n.text),
            ),
            SizedBox(height: n.space('3')),
            Wrap(
              spacing: n.space('2'),
              runSpacing: n.space('2'),
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                // The tag sets everything about its label but the family, so
                // the Arabic face reaches it through the default style.
                for (final kin in root.kin)
                  GestureDetector(
                    key: ValueKey('kin-${kin.ayahId}'),
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _load(target: kin.ayahId),
                    child: DefaultTextStyle.merge(
                      style: const TextStyle(fontFamily: Nocturne.arabicFamily),
                      child: NocturneTag(
                        kin.text,
                        variant: NocturneTagVariant.neutral,
                      ),
                    ),
                  ),
                Text(
                  root.sources.join(', '),
                  style: TextStyle(fontSize: 11, color: n.textAt(0.45)),
                ),
              ],
            ),
            SizedBox(height: n.space('2')),
            Text(
              'A kin opens the aya it is first met in.',
              style: TextStyle(fontSize: 10.5, color: n.textAt(0.45)),
            ),
          ],
          SizedBox(height: n.space('3')),
          NocturneButton(
            block: true,
            variant: NocturneButtonVariant.primary,
            onPressed: _allUnderstood(set)
                ? () => _load()
                : () => _markUnderstood(set),
            child: Text(
              _allUnderstood(set) ? 'Next set' : 'Mark set understood',
            ),
          ),
        ],
      ),
    );
  }
}

String _capitalise(String word) =>
    word.isEmpty ? word : word[0].toUpperCase() + word.substring(1);

String _arabicDigits(int number) => number
    .toString()
    .split('')
    .map((d) => String.fromCharCode(0x0660 + int.parse(d)))
    .join();

String _progressCaption(List<StudyAya> ayas) {
  final done = [
    for (final a in ayas)
      if (a.understood) a.number,
  ];
  final open = [
    for (final a in ayas)
      if (!a.understood) a.number,
  ];
  if (done.isEmpty) return 'No aya marked understood yet';
  if (open.isEmpty) return 'Every aya in this set is understood';
  return 'Aya ${_numbers(done)} marked understood · aya ${_numbers(open)} open';
}

String _numbers(List<int> numbers) => numbers.length == 1
    ? '${numbers.first}'
    : '${numbers.sublist(0, numbers.length - 1).join(', ')} and ${numbers.last}';

/// The design's separators are dashes, not rules: 2 px on, 5 px off.
class _DashedRule extends StatelessWidget {
  const _DashedRule();

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    height: 1,
    child: CustomPaint(
      painter: _DashPainter(Nocturne.of(context).textAt(0.22)),
    ),
  );
}

class _DashPainter extends CustomPainter {
  const _DashPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    for (var x = 0.0; x < size.width; x += 7) {
      canvas.drawRect(Rect.fromLTWH(x, 0, 2, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(_DashPainter old) => old.color != color;
}
