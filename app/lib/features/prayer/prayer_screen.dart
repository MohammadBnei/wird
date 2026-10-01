import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../l10n/app_localizations.dart';
import '../../data/sets.dart';
import '../study/word_row.dart';
import '../../theme/glow.dart';
import '../../theme/nocturne.dart';
import '../../widgets/nocturne_button.dart';
import 'prayer_cursor.dart';
import 'prayer_trail.dart';
import 'prayer_voice.dart';

/// Screen 1b — the set recited inside the prayer.
///
/// It runs in a room that usually has no signal, while the reader recites from
/// memory and is not looking at the phone. So it reads nothing, asks for
/// nothing and downloads nothing: the set arrives from screen 1a already read,
/// which is what leaves this screen with no dialog, no error and no spinner to
/// show. The recitation is the reader's own voice, so the audio the app holds
/// stays silent here.
///
/// The design reads "nothing to tap", and voice-follow is what makes that
/// true — when the reader has allowed the microphone and downloaded the model,
/// both of which happen in Settings. It stays off for everyone else, and it
/// gives up silently for anyone it fails: the field is split into two tap
/// zones, a large one that goes on an aya and a smaller one that steps back an
/// aya, sized to be hit without being looked at. The deviation is recorded in
/// the plan.
class PrayerScreen extends StatefulWidget {
  const PrayerScreen({
    super.key,
    required this.db,
    required this.set,
    this.cursor,
    this.wakelock = WakelockPlus.toggle,
  });

  final Database db;
  final StudySet set;

  /// Supplied by the golden, which needs the prayer held on one frame.
  final PrayerCursor? cursor;

  /// Supplied by the test that has to prove the phone is kept awake for the
  /// whole prayer and let go of afterwards.
  final Future<void> Function({required bool enable}) wakelock;

  static const nextZone = Key('prayer next');
  static const backZone = Key('prayer back');

  @override
  State<PrayerScreen> createState() => _PrayerScreenState();
}

/// The design's own geometry, in its own numbers. The space scale stops at
/// 22.4 and the rhythm of this screen is set by its type, so the gaps between
/// the lines are read off the mockup where no step carries them.
const _side = 26.0;
const _foot = 46.0;
const _previewSize = 25.0;

/// How long the aya just finished stands before the next one arrives.
///
/// Not a flourish. The reciter's last syllable and the screen's next aya
/// landing together reads as the screen hurrying them; a breath between the
/// two reads as the screen having listened.
const _dwell = Duration(seconds: 1);

/// How long the next aya takes to arrive once it starts arriving.
const _turn = Duration(milliseconds: 420);
const _previewHeight = 1.9;
const _reciting = 52.0;

class _PrayerScreenState extends State<PrayerScreen> {
  late final List<({StudyAya aya, StudyWord word})> _flat = [
    for (final aya in widget.set.ayas)
      for (final word in aya.words) (aya: aya, word: word),
  ];
  late final PrayerCursor _cursor = widget.cursor ?? PrayerCursor(_flat.length);

  /// The word each aya of the set starts on, with one whole reading standing
  /// in for the aya after the last one, so the aya after the end of the set is
  /// the first aya of the next reading. A set with no words in it leaves the
  /// two sentinels, and a tap on it moves by the one word the cursor claims.
  late final List<int> _ayaStarts = [
    0,
    for (var i = 1; i < _flat.length; i++)
      if (_flat[i].aya.id != _flat[i - 1].aya.id) i,
  ];

  /// Null until the microphone is open, and null for good on a phone where it
  /// never will be. Nothing on this screen tells the reader which, because
  /// there is nothing they could do about it while praying.
  PrayerVoice? _voice;

  /// The same voice, from the moment the microphone is live rather than from
  /// the moment there is anything to follow with.
  ///
  /// The two are up to twenty seconds apart — the model loads after the stream
  /// opens — and [_voice] is what the screen draws with, so it stays null until
  /// voice-follow is really running. This is the one the way out has to stop: a
  /// reader who mis-taps into a prayer and backs out after two seconds must not
  /// leave a microphone streaming behind a screen nobody is looking at.
  PrayerVoice? _opening;

  /// Which aya is on screen. It lags the cursor by [_dwell] when the reciter
  /// crosses into the next one, so the aya they have just finished stands for
  /// a moment before the next arrives. A prayer is not a race, and a screen
  /// that changes the instant the last syllable lands reads as impatience.
  late int _shown = _ayaOf(_cursor.at);
  Timer? _turning;

  /// Whether the move now arriving is the reader's own hand.
  var _theirHand = false;

  @override
  void initState() {
    super.initState();
    _cursor.addListener(_onTheMove);
    unawaited(_keepAwake(true));
    unawaited(_followTheReciter());
  }

  @override
  void dispose() {
    _turning?.cancel();
    _cursor.removeListener(_onTheMove);
    unawaited(_keepAwake(false));
    unawaited((_voice ?? _opening)?.stop());
    if (widget.cursor == null) _cursor.dispose();
    super.dispose();
  }

  /// The aya the cursor is in, which is not always the one on screen.
  int _ayaOf(int word) {
    var at = 0;
    for (var i = 0; i < _ayaStarts.length; i++) {
      if (_ayaStarts[i] <= word) at = i;
    }
    return at;
  }

  /// The word moved. Redraw at once — the word being recited is inside the
  /// aya already shown — and if it has crossed into another aya, decide
  /// whether the next one arrives now or after a breath.
  ///
  /// **A hand turns the page at once.** The reader tapping is the reader
  /// saying where they are, and making them wait a second for an answer reads
  /// as the screen ignoring them.
  ///
  /// **A voice gets the breath, unless it is still going.** The dwell is for
  /// the moment a reciter finishes an aya and pauses: the one they have just
  /// said stands while it settles. A reciter running straight on says so by
  /// moving again, and a second move cancels the wait and turns immediately —
  /// nobody reciting without pauses should be watching the screen catch up.
  void _onTheMove() {
    setState(() {});
    final wants = _ayaOf(_cursor.at);
    if (wants == _shown) {
      _turning?.cancel();
      _turning = null;
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
      if (mounted) setState(() => _shown = _ayaOf(_cursor.at));
    });
  }

  Future<void> _followTheReciter() async {
    final trail = await PrayerTrail.beside(await getDatabasesPath());
    trail.note('set', '${_flat.length} words, ${widget.set.ayas.length} ayas');
    final voice = await PrayerVoice.start(
      widget.db,
      _cursor,
      [for (final here in _flat) here.word.text],
      trail: trail,
      // Before this answers, and it is what `dispose` above stops. The
      // microphone is open from here on.
      listening: (live) => _opening = live,
    );
    // The prayer can be over before the model is loaded, and a microphone left
    // open behind a screen nobody is looking at is the worst of the failures
    // available here. `dispose` has already stopped the microphone through
    // `_opening` by the time this is reached; what this refuses is a loaded
    // recogniser held open by a screen that has gone.
    if (!mounted) {
      await voice?.stop();
      return;
    }
    if (voice == null) {
      trail.note('voice', 'did not start; the prayer answers taps only');
      await trail.close();
      return;
    }
    setState(() => _voice = voice);
  }

  /// The words that last moved the prayer, under the aya, fading as they age.
  ///
  /// Only what matched. A window the matcher refused is a window it could not
  /// read, and putting that in front of somebody praying would be the screen
  /// talking about itself — contract 2 bends this far and no further: what is
  /// shown is the reader's own recitation, arriving because it was understood.
  Widget _echo(Nocturne n) => ValueListenableBuilder<String>(
    valueListenable: _voice!.matched,
    builder: (context, heard, _) => AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      transitionBuilder: (child, fade) => FadeTransition(
        opacity: fade,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0, 0.4),
            end: Offset.zero,
          ).animate(fade),
          child: child,
        ),
      ),
      child: heard.isEmpty
          ? const SizedBox.shrink()
          : Text(
              heard,
              key: ValueKey(heard),
              textDirection: TextDirection.rtl,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: Nocturne.arabicFamily,
                fontSize: 15,
                color: n.accent.withValues(alpha: 0.5),
              ),
            ),
    ),
  );

  /// A tap carries the reader to the start of an aya, not of a word. Most
  /// readers have nothing following their voice — voice-follow wants a
  /// permission and a 73 MB download — and a set runs to 25 words, so a word
  /// per tap is 25 taps in the middle of a prayer. It is the same move while
  /// the voice is being followed, where the tap is the reader saying the
  /// screen is behind them: a screen one word out is not one anybody reaches
  /// for, and two grains to learn is worse than the one that is right both
  /// times.
  ///
  /// Both zones wrap at the ends of the set, because the set is recited again
  /// for the next rakʿa and the cursor no longer counts readings — the last
  /// aya's "on" is the first aya, and the first aya's "back" is the last.
  /// They also name their own direction: the cursor takes any move it is
  /// given now, so nothing downstream will quietly correct a wrong one.
  void _onToTheNextAya() {
    _theirHand = true;
    final next = _ayaStarts.indexWhere((w) => w > _cursor.at);
    _cursor.moveTo(next < 0 ? 0 : _ayaStarts[next] % _cursor.words);
    _voice?.hold();
  }

  /// From inside an aya it is that aya's own start, because a reader tapping
  /// back is saying the screen has run ahead of them; from an aya's start it
  /// is the aya before, and from the first it is the last.
  void _backAnAya() {
    _theirHand = true;
    final at = _ayaStarts.lastIndexWhere((w) => w < _cursor.at);
    _cursor.moveTo(at < 0 ? _ayaStarts.last : _ayaStarts[at]);
    _voice?.hold();
  }

  Future<void> _keepAwake(bool awake) async {
    try {
      await widget.wakelock(enable: awake);
    } on Object {
      // A phone that will not hold the screen open is still a phone someone
      // is praying with. There is nothing to say about it here.
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = Nocturne.of(context);
    final ayas = widget.set.ayas;
    // The aya on screen lags the cursor by [_dwell] when the reciter crosses
    // into the next one, so `here` is drawn from what is shown rather than
    // from where the reciter is. Inside one aya the two agree and the word
    // moves as it is recited.
    final at = _flat.isEmpty ? -1 : _shown.clamp(0, ayas.length - 1);
    final word = _ayaOf(_cursor.at) == at ? _cursor.at : _ayaStarts[at];
    final here = _flat.isEmpty ? null : _flat[word.clamp(0, _flat.length - 1)];
    return Scaffold(
      backgroundColor: n.bg,
      body: DecoratedBox(
        // The design's ground: a bloom of the accent behind the reciter,
        // falling back to the page. Its `#1b1d31` is that bloom at five
        // percent over the background, and an ellipse where Flutter draws a
        // circle.
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -0.32),
            radius: 1.2,
            colors: [
              Color.alphaBlend(n.accent.withValues(alpha: 0.05), n.bg),
              n.bg,
            ],
            stops: const [0, 0.62],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _chrome(n),
              Expanded(
                child: _field(
                  n,
                  here,
                  at > 0 ? ayas[at - 1] : null,
                  at >= 0 && at < ayas.length - 1 ? ayas[at + 1] : null,
                ),
              ),
              if (_voice != null)
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: _side),
                  child: SizedBox(height: 22, child: _echo(n)),
                ),
              _strip(n),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chrome(Nocturne n) => Padding(
    padding: EdgeInsets.fromLTRB(n.space('8'), n.space('4'), n.space('8'), 0),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          spacing: n.space('3'),
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: n.accent,
                boxShadow: [BoxShadow(color: n.accent, blurRadius: 8)],
              ),
            ),
            // The design says "Following your voice", and it says so only
            // while something is: a screen that claims to hear the reader
            // when it does not is worse than a plain one.
            Text(
              _voice == null
                  ? AppLocalizations.of(context)!.prayer_in_prayer
                  : AppLocalizations.of(context)!.prayer_following_your_voice,
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 0.13 * 10,
                color: n.accent,
              ),
            ),
          ],
        ),
        NocturneButton(
          variant: NocturneButtonVariant.ghost,
          onPressed: () => Navigator.of(context).maybePop(),
          child: Text(
            AppLocalizations.of(context)!.prayer_exit,
            style: TextStyle(fontSize: 12, color: n.textAt(0.6)),
          ),
        ),
      ],
    ),
  );

  Widget _field(
    Nocturne n,
    ({StudyAya aya, StudyWord word})? here,
    StudyAya? before,
    StudyAya? after,
  ) {
    final locale = Localizations.localeOf(context);
    final gloss = here == null
        ? ''
        : [for (final w in here.aya.words) ?w.glossIn(locale)].join(' ');
    final note = here?.word.glossIn(locale) ?? here?.word.translit;
    return Stack(
      children: [
        // An aya too long for the field runs off the top and bottom of it
        // rather than striping an overflow banner across the prayer: 2:282 is
        // a page by itself and the word budget lets it be a set on its own.
        Positioned.fill(
          child: IgnorePointer(
            child: ClipRect(
              child: OverflowBox(
                // The field is tight, so the minimum has to be let go of too
                // or the column is stretched to it and paints from the top.
                minHeight: 0,
                maxHeight: double.infinity,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: _side),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _preview(n, before, 0.24),
                      const SizedBox(height: 18),
                      if (here != null)
                        // Keyed by the aya, so the switcher has something to
                        // switch on: it compares runtimeType and key, and an
                        // unkeyed Wrap would be updated in place and never
                        // animate. The new aya rises as the old one leaves.
                        AnimatedSwitcher(
                          duration: _turn,
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeIn,
                          transitionBuilder: (child, fade) => FadeTransition(
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
                            key: ValueKey(here.aya.id),
                            child: _recited(n, here),
                          ),
                        ),
                      const SizedBox(height: 24),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 34),
                        child: _DottedRule(),
                      ),
                      SizedBox(height: n.space('6')),
                      if (gloss.isNotEmpty)
                        Text(
                          gloss,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            height: 1.55,
                            color: n.textAt(0.72),
                          ),
                        ),
                      SizedBox(height: n.space('2')),
                      if (here != null)
                        Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: here.word.text,
                                style: const TextStyle(
                                  fontFamily: Nocturne.arabicFamily,
                                ),
                              ),
                              if (note != null) TextSpan(text: ' · $note'),
                            ],
                          ),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11.5,
                            height: 1.5,
                            color: n.textAt(0.4),
                          ),
                        ),
                      const SizedBox(height: 34),
                      _preview(n, after, 0.18),
                    ],
                  ),
                ),
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
                  AppLocalizations.of(context)!.prayer_back_an_aya,
                  _backAnAya,
                ),
              ),
              Expanded(
                flex: 2,
                child: _zone(
                  PrayerScreen.nextZone,
                  AppLocalizations.of(context)!.prayer_on_to_the_next_aya,
                  _onToTheNextAya,
                ),
              ),
            ],
          ),
        ),
      ],
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

  /// The aya before or after the one being recited, kept to a single line so
  /// the frame under the reciter never reflows as the prayer moves.
  Widget _preview(Nocturne n, StudyAya? aya, double opacity) => SizedBox(
    height: _previewSize * _previewHeight,
    child: aya == null
        ? null
        : Text(
            [for (final w in aya.words) w.text].join(' '),
            textDirection: TextDirection.rtl,
            textAlign: TextAlign.center,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: Nocturne.arabicFamily,
              fontSize: _previewSize,
              height: _previewHeight,
              color: n.textAt(opacity),
            ),
          ),
  );

  Widget _recited(Nocturne n, ({StudyAya aya, StudyWord word}) here) => Wrap(
    textDirection: TextDirection.rtl,
    alignment: WrapAlignment.center,
    crossAxisAlignment: WrapCrossAlignment.end,
    spacing: 16,
    children: [
      for (final word in here.aya.words)
        Text(
          word.text,
          key: WordKey(word.id),
          textDirection: TextDirection.rtl,
          style:
              TextStyle(
                fontFamily: Nocturne.arabicFamily,
                fontSize: _reciting,
                height: 1.95,
                // The aya is what the screen is for: one is drawn at a time, at
                // 52px, and a word either side of the truth is not visible from a
                // metre away on the floor. The word inside it is singled out only
                // when the recitation named one place clearly — otherwise every
                // word of the aya is lit alike, which is the truth about what was
                // heard rather than a claim the matcher never made.
                color: !_cursor.sure || word.id < here.word.id
                    ? n.text
                    : n.textAt(0.3),
              ).merge(
                _cursor.sure && word.id == here.word.id
                    ? glowing(n, Glow.recited)
                    : null,
              ),
        ),
    ],
  );

  /// Where the reciter is, as the muṣḥaf would say it. Factual, and the same
  /// sentence on every reading of the set: the count of readings that stood
  /// here before could only be derived from a cursor that never moved
  /// backward, and a reciter repeating an aya would have made it tick down.
  String _whereInTheSurah() {
    if (_flat.isEmpty) return '';
    final aya = _flat[_cursor.at].aya;
    return '${aya.surahNameEn} · ${aya.number}';
  }

  Widget _strip(Nocturne n) {
    final through = (_cursor.at + 1) / _cursor.words;
    return Padding(
      padding: const EdgeInsets.fromLTRB(_side, 0, _side, _foot),
      child: Column(
        children: [
          Row(
            spacing: n.space('4'),
            children: [
              Expanded(
                child: Container(
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
              ),
              Text(
                _whereInTheSurah(),
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 0.08 * 10,
                  color: n.textAt(0.58),
                ),
              ),
            ],
          ),
          SizedBox(height: n.space('4')),
          Text(
            _voice == null
                ? AppLocalizations.of(context)!.prayer_foot_taps_only
                : AppLocalizations.of(context)!.prayer_foot_following,
            style: TextStyle(fontSize: 10.5, color: n.textAt(0.58)),
          ),
        ],
      ),
    );
  }
}

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
