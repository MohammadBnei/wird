import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../data/db.dart';
import '../../data/sets.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/glow.dart';
import '../../theme/nocturne.dart';
import '../../widgets/nocturne_button.dart';
import '../study/word_row.dart';
import 'prayer_cursor.dart';
import 'prayer_pace.dart';
import 'prayer_plan.dart';
import 'prayer_trail.dart';
import 'prayer_voice.dart';

/// What the prayer leaves behind for whoever opened it, filled in as it goes.
///
/// The prayer screen writes nothing — it runs inside the prayer, where a
/// database write has no safe moment: `dispose()` cannot await, and the
/// back-swipe and Android's back are not the Exit button. So it says what
/// happened here, and the screen that pushed it writes when it gets the reader
/// back, however they left.
class PrayerOutcome {
  /// The furthest rakʿah the reader began, counted from one.
  int reached = 1;

  /// The Arabic size the reader pinched to, or null where they left it.
  double? size;
}

/// Screen 1b — the prayer, one rakʿah at a time.
///
/// It runs in a room that usually has no signal, while the reader recites from
/// memory and is not looking at the phone. So it reads nothing, asks for
/// nothing and downloads nothing: the plan and Al-Fātiḥa arrive already read,
/// which is what leaves this screen with no dialog, no error and no spinner to
/// show.
///
/// Each rakʿah is Al-Fātiḥa and then its passage. What moves the text is the
/// reader's choice, made before the prayer: their voice, a steady pace, both
/// (the voice leads and the pace covers for it), or neither. Whatever was
/// chosen, the field is two tap zones — a large one that goes on an aya and a
/// narrow one down the left that steps back an aya — because the voice and
/// the pace can both be wrong and the reader's hand is the correction. With
/// neither chosen, the large zone goes on a word: that reader is following
/// along by hand.
class PrayerScreen extends StatefulWidget {
  const PrayerScreen({
    super.key,
    required this.db,
    required this.plan,
    required this.fatiha,
    this.prefs = defaultPrayerPrefs,
    this.outcome,
    this.cursor,
    this.preview,
    this.wakelock = WakelockPlus.toggle,
  });

  final Database db;
  final PrayerPlan plan;

  /// Al-Fātiḥa's seven ayas, with their words, recited at the head of every
  /// rakʿah.
  final List<StudyAya> fatiha;
  final PrayerPrefs prefs;
  final PrayerOutcome? outcome;

  /// The first rakʿah's cursor, supplied by the golden, which needs the prayer
  /// held on one frame.
  final PrayerCursor? cursor;

  /// The rakʿah to preview, from one, or null for the prayer itself. A
  /// preview opens on the passage rather than on Al-Fātiḥa, which the reader
  /// knows, never opens the microphone, and goes round again at the end.
  final int? preview;

  /// Supplied by the test that has to prove the phone is kept awake for the
  /// whole prayer and let go of afterwards.
  final Future<void> Function({required bool enable}) wakelock;

  static const nextZone = Key('prayer next');
  static const backZone = Key('prayer back');

  @override
  State<PrayerScreen> createState() => _PrayerScreenState();
}

/// The design's own geometry, in its own numbers.
const _side = 22.0;
const _aroundSize = 24.0;
const _minSize = 30.0;
const _maxSize = 88.0;

/// How long the aya just finished stands before the next one arrives, counted
/// from its last word being heard. Long enough not to snatch the aya from
/// under its last syllable, short enough that the next one is there when the
/// reciter looks for it.
const _dwell = Duration(milliseconds: 500);

/// How long the voice may rest on the last word before the rakʿah is taken as
/// recited: the end of the aya, and the breath before bowing.
const _lastWordHeld = Duration(seconds: 2);

/// How long "Prayer complete" stands before the prayer closes itself.
const _completeFor = Duration(milliseconds: 2400);

/// How long the aya takes to arrive once it starts arriving.
const _turn = Duration(milliseconds: 420);

enum _Phase { reading, between, done }

class _PrayerScreenState extends State<PrayerScreen> {
  /// Which rakʿah is on screen, from one. Between two rakʿahs it is already
  /// the next one, waiting to be begun.
  var _r = 1;
  var _phase = _Phase.reading;

  late Rakah _rakah;
  late List<({StudyAya aya, StudyWord word})> _flat;

  /// The word each aya of the rakʿah starts on.
  late List<int> _ayaStarts;
  late PrayerCursor _cursor;
  late PrayerPace _pace;

  /// Null until the microphone is open, and null for good on a phone where it
  /// never will be. Nothing on this screen tells the reader which, because
  /// there is nothing they could do about it while praying.
  PrayerVoice? _voice;

  /// The same voice, from the moment the microphone is live rather than from
  /// the moment there is anything to follow with. The two are up to twenty
  /// seconds apart, and this is the one the way out has to stop: a reader who
  /// backs out after two seconds must not leave a microphone streaming.
  PrayerVoice? _opening;

  /// Which aya is on screen. It lags the cursor by [_dwell] when the reciter
  /// crosses into the next one, so the aya they have just finished stands for
  /// a moment before the next arrives.
  late int _shown;
  Timer? _turning;

  /// Whether the move now arriving is the reader's own hand.
  var _theirHand = false;

  Timer? _finishing;
  Timer? _closing;
  late final AppLifecycleListener _life;

  late double _size = widget.prefs.arabicSize;
  double _pinchFrom = 0;
  Timer? _flash;

  final _window = ScrollController();

  bool get _wordByWord => !widget.prefs.voice && !widget.prefs.pace;

  @override
  void initState() {
    super.initState();
    _load(widget.preview ?? 1, cursor: widget.cursor);
    _pace.start();
    _life = AppLifecycleListener(
      // A prayer the phone left for another app is not a prayer the pace can
      // go on reciting by itself.
      onHide: () => _pace.pause(),
      onShow: () {
        if (_phase == _Phase.reading) _pace.start();
      },
    );
    unawaited(_keepAwake(true));
    if (widget.prefs.voice && widget.preview == null) {
      unawaited(_followTheReciter());
    }
  }

  @override
  void dispose() {
    _turning?.cancel();
    _finishing?.cancel();
    _closing?.cancel();
    _flash?.cancel();
    _life.dispose();
    _pace.dispose();
    _cursor.removeListener(_onTheMove);
    if (!identical(_cursor, widget.cursor)) _cursor.dispose();
    _window.dispose();
    unawaited(_keepAwake(false));
    unawaited((_voice ?? _opening)?.stop());
    super.dispose();
  }

  /// Sets rakʿah [r] on screen, on a cursor of its own: [PrayerCursor] knows
  /// how many words it has, and the next rakʿah is a different length.
  void _load(int r, {PrayerCursor? cursor}) {
    _r = r;
    _rakah = rakahOf(widget.fatiha, widget.plan.passageFor(r));
    _flat = [
      for (final aya in _rakah.ayas)
        for (final word in aya.words) (aya: aya, word: word),
    ];
    _ayaStarts = [
      0,
      for (var i = 1; i < _flat.length; i++)
        if (_flat[i].aya.id != _flat[i - 1].aya.id) i,
    ];
    _cursor =
        (cursor ??
              PrayerCursor(
                _flat.length,
                at: widget.preview != null ? _passageStart : 0,
              ))
          ..addListener(_onTheMove);
    _shown = _ayaOf(_cursor.at);
    _pace = PrayerPace(
      _cursor,
      voice: widget.prefs.voice,
      pace: widget.prefs.pace,
      wpm: widget.prefs.wpm,
      onEnd: _endRakah,
    );
  }

  /// The first word after Al-Fātiḥa, or the first word where there is none.
  int get _passageStart {
    final fatiha = [for (final a in widget.fatiha) ...a.words].length;
    return fatiha < _flat.length ? fatiha : 0;
  }

  /// The aya the cursor is in, which is not always the one on screen.
  int _ayaOf(int word) {
    var at = 0;
    for (var i = 0; i < _ayaStarts.length; i++) {
      if (_ayaStarts[i] <= word) at = i;
    }
    return at;
  }

  /// The aya the screen should show: the cursor's, or the one after it once
  /// the voice is sure of the last word — the reciter has finished the aya
  /// and is about to begin the next. Not past the rakʿah's last aya, whose
  /// last word ends the rakʿah instead.
  int _wanted() {
    final aya = _ayaOf(_cursor.at);
    final last = aya + 1 < _ayaStarts.length
        ? _ayaStarts[aya + 1] - 1
        : _cursor.words - 1;
    final finished =
        !_theirHand &&
        _cursor.sure &&
        _cursor.at == last &&
        aya + 1 < _ayaStarts.length;
    return finished ? aya + 1 : aya;
  }

  /// The word moved. Redraw at once — the word being recited is inside the
  /// aya already shown — and if it has crossed into another aya, decide
  /// whether the next one arrives now or after a breath.
  ///
  /// **A hand turns the page at once.** The reader tapping is the reader
  /// saying where they are.
  ///
  /// **A voice gets the breath, unless it is still going.** A reciter running
  /// straight on says so by moving again, and a second move cancels the wait.
  ///
  /// Between two rakʿahs the only thing that moves the cursor is the voice
  /// hearing the reader begin Al-Fātiḥa (`PrayerVoice.follow`), so a move
  /// there begins the rakʿah.
  void _onTheMove() {
    if (_phase == _Phase.between) {
      _begin();
      return;
    }
    if (_phase != _Phase.reading) return;
    setState(() {});
    _holdTheLine();
    _finishing?.cancel();
    _finishing = null;
    if (_voice != null && !_theirHand && _cursor.at == _cursor.words - 1) {
      _finishing = Timer(_lastWordHeld, _endRakah);
    }
    final wants = _wanted();
    if (wants == _shown) {
      _turning?.cancel();
      _turning = null;
      _theirHand = false;
      return;
    }
    if (_theirHand || _turning != null) {
      _theirHand = false;
      _turning?.cancel();
      _turning = null;
      setState(() => _shown = wants);
      return;
    }
    _turning = Timer(_dwell, () {
      _turning = null;
      if (mounted) setState(() => _shown = _wanted());
    });
  }

  /// The rakʿah is recited: on to the next, or the prayer is over.
  void _endRakah() {
    if (_phase != _Phase.reading || !mounted) return;
    _finishing?.cancel();
    _turning?.cancel();
    _turning = null;
    _pace.pause();
    if (widget.preview != null) {
      _theirHand = true;
      _cursor.moveTo(_passageStart);
      _pace.start();
      return;
    }
    if (_r >= widget.plan.rakahs) {
      setState(() => _phase = _Phase.done);
      _closing = Timer(_completeFor, () {
        if (mounted) unawaited(Navigator.of(context).maybePop());
      });
      return;
    }
    _cursor.removeListener(_onTheMove);
    if (!identical(_cursor, widget.cursor)) _cursor.dispose();
    _pace.dispose();
    setState(() {
      _phase = _Phase.between;
      _load(_r + 1);
    });
    _voice?.follow(_cursor, _rakah.heard, unseenAt: _rakah.basmalaAt);
    if (_window.hasClients) _window.jumpTo(0);
  }

  /// The next rakʿah is begun: by the reader reciting it, or by a tap.
  void _begin() {
    if (_phase != _Phase.between) return;
    widget.outcome?.reached = _r;
    _voice?.begun();
    setState(() {
      _phase = _Phase.reading;
      _shown = _ayaOf(_cursor.at);
    });
    _pace.start();
  }

  Future<void> _followTheReciter() async {
    final trail = await PrayerTrail.beside(await getDatabasesPath());
    trail.note(
      'prayer',
      '${widget.plan.rakahs} rakʿahs, ${_flat.length} words in the first',
    );
    final voice = await PrayerVoice.start(
      widget.db,
      _cursor,
      _rakah.heard,
      unseenAt: _rakah.basmalaAt,
      trail: trail,
      // Before this answers, and it is what `dispose` above stops. The
      // microphone is open from here on.
      listening: (live) => _opening = live,
    );
    // The prayer can be over before the model is loaded; `dispose` has stopped
    // the microphone through `_opening`, and this refuses a loaded recogniser
    // held open by a screen that has gone.
    if (!mounted) {
      await voice?.stop();
      return;
    }
    if (voice == null) {
      trail.note('voice', 'did not start; the prayer answers taps only');
      await trail.close();
      return;
    }
    // The voice was started on the first rakʿah, and the reader may be past
    // it by the time the model has loaded.
    if (_r > 1) {
      voice.follow(_cursor, _rakah.heard, unseenAt: _rakah.basmalaAt);
      if (_phase == _Phase.reading) voice.begun();
    }
    voice.onRecognised = () => _pace.recognised();
    setState(() => _voice = voice);
  }

  /// A tap carries the reader to the start of an aya, not of a word: a set
  /// runs to 25 words, and a word per tap is 25 taps in the middle of a
  /// prayer. Past the last aya it ends the rakʿah. With nothing else moving
  /// the text, it goes on a word, because then the hand is the only pace.
  void _onToTheNext() {
    if (_phase == _Phase.between) return _begin();
    if (_phase != _Phase.reading) return;
    _theirHand = true;
    if (_wordByWord) {
      if (_cursor.at + 1 >= _cursor.words) return _endRakah();
      _cursor.moveTo(_cursor.at + 1);
    } else {
      final next = _ayaStarts.indexWhere((w) => w > _cursor.at);
      if (next < 0) return _endRakah();
      _cursor.moveTo(_ayaStarts[next]);
    }
    _pace.restartFrom();
    _voice?.hold();
  }

  /// From inside an aya it is that aya's own start, because a reader tapping
  /// back is saying the screen has run ahead of them; from an aya's start it
  /// is the aya before.
  void _backAnAya() {
    if (_phase == _Phase.between) return _begin();
    if (_phase != _Phase.reading) return;
    _theirHand = true;
    final at = _ayaStarts.lastIndexWhere((w) => w < _cursor.at);
    _cursor.moveTo(at < 0 ? 0 : _ayaStarts[at]);
    _pace.restartFrom();
    _voice?.hold();
  }

  /// Keeps the word being recited a third of the way down the aya, whatever
  /// the size: a long aya at a large size runs off the field, and the reader
  /// should find the word in the same place every time they look.
  void _holdTheLine() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Keyed by the word's own id rather than one key for whichever word is
      // lit: while an aya turns, the one leaving is still in the tree, lit.
      final lit = GlobalObjectKey(_flat[_cursor.at].word.id).currentContext;
      if (lit == null || !mounted) return;
      unawaited(
        Scrollable.ensureVisible(
          lit,
          alignment: 0.3,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        ),
      );
    });
  }

  void _setSize(double size) {
    final next = size.clamp(_minSize, _maxSize).roundToDouble();
    if (next == _size) return;
    widget.outcome?.size = next;
    _flash?.cancel();
    setState(() => _size = next);
    _flash = Timer(const Duration(milliseconds: 1100), () {
      if (mounted) setState(() => _flash = null);
    });
    _holdTheLine();
  }

  Future<void> _keepAwake(bool awake) async {
    try {
      await widget.wakelock(enable: awake);
    } on Object {
      // A phone that will not hold the screen open is still a phone someone
      // is praying with. There is nothing to say about it here.
    }
  }

  /// What is moving the text, as it is and not as it was asked for: a voice
  /// chosen and not running is not claimed.
  String _mode(AppLocalizations l) {
    final pace = widget.prefs.pace;
    if (_voice != null) return pace ? l.prayer_mode_both : l.prayer_mode_voice;
    if (pace) return l.prayer_mode_pace(widget.prefs.wpm);
    return l.prayer_mode_tap;
  }

  @override
  Widget build(BuildContext context) {
    final n = Nocturne.of(context);
    final l = AppLocalizations.of(context)!;
    final ayas = _rakah.ayas;
    final at = _shown.clamp(0, ayas.length - 1);
    // The aya on screen lags the cursor by [_dwell], so the word is drawn from
    // what is shown rather than from where the reciter is.
    final word = _ayaOf(_cursor.at) == at ? _cursor.at : _ayaStarts[at];
    final here = _flat[word.clamp(0, _flat.length - 1)];
    return Scaffold(
      backgroundColor: n.bg,
      body: DecoratedBox(
        // The design's ground: a bloom of the accent behind the reciter,
        // falling back to the page.
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -0.24),
            radius: 1.2,
            colors: [
              Color.alphaBlend(n.accent.withValues(alpha: 0.05), n.bg),
              n.bg,
            ],
            stops: const [0, 0.62],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  _chrome(n, l, here),
                  Expanded(
                    child: _field(
                      n,
                      l,
                      here,
                      at > 0 ? ayas[at - 1] : null,
                      at < ayas.length - 1 ? ayas[at + 1] : null,
                    ),
                  ),
                  _strip(n, l),
                ],
              ),
              if (_phase == _Phase.between) _between(n, l),
              if (_phase == _Phase.done) _complete(n, l),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chrome(
    Nocturne n,
    AppLocalizations l,
    ({StudyAya aya, StudyWord word}) here,
  ) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 14, 12, 0),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l
                    .prayer_header(
                      prayerName(l, widget.plan.preset),
                      _r,
                      widget.plan.rakahs,
                    )
                    .toUpperCase(),
                style: TextStyle(
                  fontSize: 10.5,
                  letterSpacing: 0.13 * 10.5,
                  color: n.color('accent-300'),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                l.prayer_part(
                  here.aya.surahNameEn,
                  '${here.aya.surahId}:${here.aya.number}',
                ),
                style: TextStyle(fontSize: 12, color: n.textAt(0.55)),
              ),
            ],
          ),
        ),
        NocturneButton(
          variant: NocturneButtonVariant.ghost,
          onPressed: () => Navigator.of(context).maybePop(),
          child: Text(
            l.prayer_exit,
            style: TextStyle(fontSize: 13, color: n.textAt(0.62)),
          ),
        ),
      ],
    ),
  );

  Widget _field(
    Nocturne n,
    AppLocalizations l,
    ({StudyAya aya, StudyWord word}) here,
    StudyAya? before,
    StudyAya? after,
  ) {
    final locale = Localizations.localeOf(context);
    final around = widget.prefs.around;
    // The design trades the aya before for room as the Arabic grows, and the
    // aya after with it once the size passes 72.
    final above = !around
        ? 0.0
        : _size <= 60
        ? 120.0
        : _size <= 72
        ? 64.0
        : 0.0;
    final gloss = here.word.glossIn(locale) ?? here.word.translit ?? '';
    return GestureDetector(
      // Pinching the text is the one control the prayer has that is not a
      // tap: the size that reads from the floor is found by trying it.
      onScaleStart: (_) => _pinchFrom = _size,
      onScaleUpdate: (d) {
        if (d.pointerCount >= 2) _setSize(_pinchFrom * d.scale);
      },
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: _side),
                child: Column(
                  children: [
                    SizedBox(
                      height: above,
                      child: ClipRect(
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: _neighbour(n, before, 0.3, current: here.aya),
                        ),
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        controller: _window,
                        physics: const NeverScrollableScrollPhysics(),
                        padding: const EdgeInsets.only(top: 10),
                        child: Column(
                          children: [
                            // Keyed by the rakʿah and the aya, so the
                            // switcher has something to switch on and the
                            // new aya rises as the old one leaves.
                            AnimatedSwitcher(
                              duration: _turn,
                              switchInCurve: Curves.easeOutCubic,
                              switchOutCurve: Curves.easeIn,
                              transitionBuilder: (child, fade) =>
                                  FadeTransition(
                                    opacity: fade,
                                    child: SlideTransition(
                                      position: Tween(
                                        begin: const Offset(0, 0.16),
                                        end: Offset.zero,
                                      ).animate(fade),
                                      child: child,
                                    ),
                                  ),
                              child: KeyedSubtree(
                                key: ValueKey((_r, here.aya.id)),
                                child: _recited(
                                  n,
                                  here,
                                  named:
                                      _cursor.sure &&
                                      _ayaOf(_cursor.at) == _shown,
                                  behind: _ayaOf(_cursor.at) > _shown,
                                ),
                              ),
                            ),
                            if (around && _size <= 72) ...[
                              const SizedBox(height: 14),
                              _neighbour(n, after, 0.22, current: here.aya),
                            ],
                          ],
                        ),
                      ),
                    ),
                    if (widget.prefs.gloss)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(0, 12, 0, 16),
                        child: Column(
                          children: [
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 34),
                              child: _DottedRule(),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              gloss,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 18,
                                height: 1.45,
                                color: n.textAt(0.82),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          // The whole field advances the prayer; a narrower strip at its left
          // edge steps back. A person mid-prayer is not aiming at anything.
          Positioned.fill(
            child: Row(
              children: [
                Expanded(
                  child: _zone(
                    PrayerScreen.backZone,
                    l.prayer_back_an_aya,
                    _backAnAya,
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: _zone(
                    PrayerScreen.nextZone,
                    _wordByWord
                        ? l.prayer_on_a_word
                        : l.prayer_on_to_the_next_aya,
                    _onToTheNext,
                  ),
                ),
              ],
            ),
          ),
          if (_flash != null)
            Positioned(
              top: 40,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: n.surface,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    l.prayer_size_remembered(_size.round()),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _zone(Key key, String label, VoidCallback onTap) => Semantics(
    button: true,
    label: label,
    child: GestureDetector(
      key: key,
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: const SizedBox.expand(),
    ),
  );

  /// The aya before or after the one being recited, faded, so the reader
  /// knows where they are in the passage without it competing with the aya.
  /// The aya beside the one being recited, or — where it belongs to another
  /// sūra — the boundary between the two, named by the later of them. Drawn
  /// as an aya, al-Fātiḥa's last ran straight into the passage's first and
  /// the two read as one sūra.
  Widget _neighbour(
    Nocturne n,
    StudyAya? aya,
    double opacity, {
    required StudyAya current,
  }) {
    if (aya == null) return const SizedBox.shrink();
    if (aya.surahId != current.surahId) {
      final later = aya.id < current.id ? current : aya;
      return _suraMark(n, later);
    }
    return Text(
      [for (final w in aya.words) w.text].join(' '),
      textDirection: TextDirection.rtl,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontFamily: Nocturne.arabicFamily,
        fontSize: _aroundSize,
        height: 1.85,
        color: n.textAt(opacity),
      ),
    );
  }

  Widget _suraMark(Nocturne n, StudyAya of) {
    final rule = Expanded(child: Divider(color: n.color('accent-700')));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        spacing: 12,
        children: [
          rule,
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                of.surahNameAr,
                textDirection: TextDirection.rtl,
                style: TextStyle(
                  fontFamily: Nocturne.arabicFamily,
                  fontSize: 22,
                  height: 1.6,
                  color: n.color('accent-300'),
                ),
              ),
              Text(
                of.surahNameEn,
                style: TextStyle(fontSize: 11, color: n.textAt(0.55)),
              ),
            ],
          ),
          rule,
        ],
      ),
    );
  }

  /// [named] is whether a word of this aya has been named. An aya shown
  /// because the one before it was finished has none yet: lighting its first
  /// word claimed the reader had begun it. [behind] is the aya the reader has
  /// just left, standing for the dwell: all of it recited.
  Widget _recited(
    Nocturne n,
    ({StudyAya aya, StudyWord word}) here, {
    required bool named,
    required bool behind,
  }) => Wrap(
    textDirection: TextDirection.rtl,
    alignment: WrapAlignment.center,
    crossAxisAlignment: WrapCrossAlignment.end,
    spacing: (_size * 0.28).roundToDouble(),
    children: [
      for (final word in here.aya.words)
        KeyedSubtree(
          key: word.id == here.word.id ? GlobalObjectKey(word.id) : null,
          child: Text(
            word.text,
            key: WordKey(word.id),
            textDirection: TextDirection.rtl,
            style:
                TextStyle(
                  fontFamily: Nocturne.arabicFamily,
                  fontSize: _size,
                  height: 1.9,
                  // The word inside the aya is singled out only when the
                  // recitation, the pace or a tap named it — otherwise every
                  // word of the aya is drawn as still to come, which is the
                  // truth about what was heard rather than a claim nobody
                  // made. Full white read as an aya already recited.
                  color: behind
                      ? n.textAt(0.72)
                      : !named
                      ? n.textAt(0.4)
                      : word.id < here.word.id
                      ? n.textAt(0.72)
                      : n.textAt(0.4),
                ).merge(
                  named && word.id == here.word.id
                      ? glowing(n, Glow.recited)
                      : null,
                ),
          ),
        ),
    ],
  );

  Widget _strip(Nocturne n, AppLocalizations l) {
    final through = (_cursor.at + 1) / _cursor.words;
    final small = TextStyle(fontSize: 11, color: n.textAt(0.58));
    return Padding(
      padding: const EdgeInsets.fromLTRB(_side, 0, _side, 22),
      child: Column(
        children: [
          Container(
            height: 2,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(2),
              gradient: LinearGradient(
                colors: [
                  n.accent,
                  n.accent,
                  n.color('neutral-800'),
                  n.color('neutral-800'),
                ],
                stops: [0, through, through, 1],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            spacing: 12,
            children: [
              Expanded(
                child: Row(
                  spacing: 7,
                  children: [
                    _dot(n, n.accent, glow: true, size: 6),
                    Flexible(
                      child: Text(
                        _mode(l),
                        style: small,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                spacing: 7,
                children: [
                  for (var r = 1; r <= widget.plan.rakahs; r++)
                    _dot(
                      n,
                      r < _r
                          ? n.color('accent-700')
                          : r == _r
                          ? n.accent
                          : n.color('neutral-800'),
                      glow: r == _r,
                    ),
                ],
              ),
              Expanded(
                child: Text(
                  l.prayer_rakah_count(_r, widget.plan.rakahs),
                  textAlign: TextAlign.right,
                  style: small,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dot(Nocturne n, Color color, {bool glow = false, double size = 8}) =>
      Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          boxShadow: glow ? [BoxShadow(color: n.accent, blurRadius: 8)] : null,
        ),
      );

  /// Between two rakʿahs the reader is bowing and prostrating, and the screen
  /// all but goes out: the next rakʿah's number, and what will begin it.
  Widget _between(Nocturne n, AppLocalizations l) => Positioned.fill(
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _begin,
      child: ColoredBox(
        color: const Color(0xF0090A11),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          spacing: 10,
          children: [
            Text(
              l.prayer_between(_r, widget.plan.rakahs).toUpperCase(),
              style: TextStyle(
                fontSize: 10.5,
                letterSpacing: 0.13 * 10.5,
                color: n.textAt(0.4),
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 8,
              children: [
                _dot(n, n.color('accent-700'), size: 6),
                Text(
                  _voice != null
                      ? l.prayer_between_voice
                      : l.prayer_between_tap,
                  style: TextStyle(fontSize: 13, color: n.textAt(0.45)),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  Widget _complete(Nocturne n, AppLocalizations l) => Positioned.fill(
    child: ColoredBox(
      color: const Color(0xF0090A11),
      child: Center(
        child: Text(
          l.prayer_complete,
          style: TextStyle(fontSize: 13, color: n.textAt(0.42)),
        ),
      ),
    ),
  );
}

/// The prayer's name, or the word for a prayer with no preset.
String prayerName(AppLocalizations l, PrayerPreset? preset) => switch (preset) {
  null => l.prayer_generic,
  PrayerPreset.fajr => l.prayer_fajr,
  PrayerPreset.zuhr => l.prayer_zuhr,
  PrayerPreset.asr => l.prayer_asr,
  PrayerPreset.maghrib => l.prayer_maghrib,
  PrayerPreset.isha => l.prayer_isha,
};

/// ponytail: screen 1a has its own copy at a different period, and
/// lib/widgets/ belongs to one owner this phase. Lift them into a shared
/// widget the next time a third screen wants a dotted line.
class _DottedRule extends StatelessWidget {
  const _DottedRule();

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    height: 1,
    child: CustomPaint(painter: _DotPainter(Nocturne.of(context).textAt(0.2))),
  );
}

class _DotPainter extends CustomPainter {
  const _DotPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    for (var x = 0.0; x < size.width; x += 8) {
      canvas.drawRect(Rect.fromLTWH(x, 0, 2, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(_DotPainter old) => old.color != color;
}
