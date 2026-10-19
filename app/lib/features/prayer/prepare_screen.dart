import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import '../../data/db.dart';
import '../../data/mic.dart';
import '../../data/sets.dart';
import '../../data/speech.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/nocturne.dart';
import '../../widgets/nocturne_segmented.dart';
import '../../widgets/nocturne_button.dart';
import '../../widgets/nocturne_kicker.dart';
import '../index/index_screen.dart';
import '../settings/settings_screen.dart';
import 'passage_chooser.dart';
import 'prayer_plan.dart';
import 'prayer_screen.dart';

/// The prayer, prepared before it begins: which prayer, how many rakʿahs,
/// what is recited after Al-Fātiḥa, and how the text moves.
///
/// One screen, and everything on it starts where the reader left it last
/// time — except the passage, which starts where they are in the Qur'an: the
/// set they came from, or the next one unread.
///
/// It is also where the prayer is written down. The prayer screen writes
/// nothing (see [PrayerOutcome]), so this screen does, when the reader comes
/// back from it — however they left.
class PrepareScreen extends StatefulWidget {
  const PrepareScreen({super.key, required this.db, this.from});

  final Database db;

  /// The set the reader was holding when they asked to pray, which the
  /// prayer answers for. Null from anywhere else, where the next unread set
  /// takes its place.
  final StudySet? from;

  @override
  State<PrepareScreen> createState() => _PrepareScreenState();
}

/// What the screen needs read before it can show anything.
typedef _Loaded = ({
  ReadingOrder order,
  List<SuraEntry> suras,
  List<StudyAya> fatiha,
  StudySet? next,
  List<StudySet> recent,
});

class _PrepareScreenState extends State<PrepareScreen> {
  _Loaded? _loaded;

  /// The load failed: the database would not answer. Seen when a second copy
  /// of the app replaced the file under this one; a reader must be told, not
  /// left on an empty screen.
  var _trouble = false;
  var _loading = false;

  PrayerPreset? _preset;
  int _rakahs = defaultPrayerPrefs.rakahs;
  StudySet? _first;
  StudySet? _second;
  var _sameAsFirst = false;

  /// What voice-follow needs and whether the phone has it: the microphone
  /// allowed, and the recogniser on disk. Both are settled right here, before
  /// the prayer — the prayer screen itself may not ask for anything.
  var _mic = MicPermission.notAsked;
  var _model = false;
  bool get _voiceReady => _mic == MicPermission.granted && _model;

  /// The reader's own answer to "follow my voice", kept while the phone
  /// cannot follow it: a recogniser not yet downloaded must not cost them the
  /// choice for the day it is.
  var _voiceWanted = defaultPrayerPrefs.voice;

  /// Followed only where the phone can follow: the voice, as the prayer runs.
  bool get _voice => _voiceWanted && _voiceReady;

  /// The one choice the reader makes about how the text moves (ADR 0034).
  /// Voice carries the pace as its fallback, so the old voice-alone reads as
  /// Voice, and a phone that cannot follow yet still moves at the pace.
  _Moves get _moving => _voiceWanted
      ? _Moves.voice
      : _pace
      ? _Moves.steady
      : _Moves.tap;

  void _move(_Moves to) => setState(() {
    _voiceWanted = to == _Moves.voice;
    _pace = to != _Moves.tap;
  });
  var _pace = defaultPrayerPrefs.pace;
  var _wpm = defaultPrayerPrefs.wpm;
  var _gloss = defaultPrayerPrefs.gloss;
  var _around = defaultPrayerPrefs.around;
  var _size = defaultPrayerPrefs.arabicSize;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    // One read at a time: a second tap on Try again would race the first and
    // could write over what the reader changed in between.
    if (_loading) return;
    _loading = true;
    if (_trouble) setState(() => _trouble = false);
    try {
      await _read();
    } on Object {
      if (mounted) setState(() => _trouble = true);
    } finally {
      _loading = false;
    }
  }

  Future<void> _read() async {
    final db = widget.db;
    final order = await readingOrder(db);
    final prefs = await prayerPrefs(db);
    final suras = await suraIndex(db);
    final fatiha = (await ayaSet(db, order, 1001, ayas: 7))!.ayas;
    final next = await nextSet(db, order);
    final recent = <StudySet>[];
    for (final r in await recentPassages(db)) {
      // A passage the chooser offered is inside one sūra; a set the walk
      // proposed across two is not a passage the chooser can name.
      if (r.start ~/ 1000 != r.end ~/ 1000) continue;
      final set = await ayaSet(db, order, r.start, ayas: r.end - r.start + 1);
      if (set != null) recent.add(set);
    }
    final mic = await micPermission(db);
    // Looked for only behind a yes: without the microphone the recogniser
    // is never offered, and the look is real file work.
    final model =
        mic == MicPermission.granted &&
        (await VoiceModel.beside(await getDatabasesPath())).ready;
    // Al-Fātiḥa is recited in every rakʿah already, so a set of it — the one
    // the reader was studying, say — is no passage: it would recite it twice
    // and every word would stand in two places. The chooser refuses it too.
    final first = [widget.from, next]
        .where((s) => s != null && s.ayas.every((a) => a.surahId != 1))
        .firstOrNull;
    final second = await passageAfter(db, first, order, suras);
    if (!mounted) return;
    setState(() {
      _loaded = (
        order: order,
        suras: suras,
        fatiha: fatiha,
        next: next,
        recent: recent,
      );
      _mic = mic;
      _model = model;
      _preset = PrayerPreset.values.asNameMap()[prefs.preset];
      _rakahs = prefs.rakahs;
      _first = first;
      _second = second;
      _sameAsFirst = false;
      _voiceWanted = prefs.voice;
      // A reader who chose the voice alone, before Voice carried the pace,
      // would otherwise be left tapping word by word until the recogniser
      // arrives.
      _pace = prefs.pace || prefs.voice;
      _wpm = prefs.wpm;
      _gloss = prefs.gloss;
      _around = prefs.around;
      _size = prefs.arabicSize;
    });
  }

  PrayerPlan get _plan => PrayerPlan(
    preset: _preset,
    rakahs: _rakahs,
    first: _first,
    second: _second,
    sameAsFirst: _sameAsFirst,
    credited: widget.from ?? _loaded?.next,
  );

  PrayerPrefs get _prefs => (
    preset: _preset?.name,
    rakahs: _rakahs,
    voice: _voiceWanted,
    pace: _pace,
    wpm: _wpm,
    gloss: _gloss,
    around: _around,
    arabicSize: _size,
  );

  /// The same, as the prayer runs it: with the voice only where it can be.
  PrayerPrefs get _running => (
    preset: _preset?.name,
    rakahs: _rakahs,
    voice: _voice,
    pace: _pace,
    wpm: _wpm,
    gloss: _gloss,
    around: _around,
    arabicSize: _size,
  );

  void _choosePreset(PrayerPreset preset) => setState(() {
    if (_preset == preset) {
      _preset = null;
      return;
    }
    _preset = preset;
    _rakahs = preset.rakahs;
  });

  Future<void> _choose(int r) async {
    // One chooser at a time: the suggestion is read before the chooser is
    // pushed, and a second tap in that moment would stack a second one.
    if (_choosing) return;
    _choosing = true;
    try {
      await _chooseFor(r);
    } finally {
      _choosing = false;
    }
  }

  var _choosing = false;

  Future<void> _chooseFor(int r) async {
    final loaded = _loaded!;
    // A later rakʿah is offered the ayas after the first's passage as it is
    // now, not as it was when the preparation opened. A database that will
    // not say what follows costs the suggestion, not the chooser.
    StudySet? after;
    if (r > 1) {
      try {
        after = await passageAfter(
          widget.db,
          _first,
          loaded.order,
          loaded.suras,
        );
      } on Object {
        after = null;
      }
    }
    if (!mounted) return;
    final choice = await Navigator.of(context).push<PassageChoice>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => PassageChooser(
          db: widget.db,
          order: loaded.order,
          rakah: r,
          suras: loaded.suras,
          wpm: _wpm,
          continuing: loaded.next,
          after: after,
          first: _first,
          recent: loaded.recent,
          current: r == 1
              ? (set: _first, same: false)
              : (set: _sameAsFirst ? null : _second, same: _sameAsFirst),
        ),
      ),
    );
    if (choice == null || !mounted) return;
    setState(() {
      if (r == 1) {
        _first = choice.set;
      } else {
        _sameAsFirst = choice.same;
        _second = choice.set;
      }
    });
  }

  /// Set from the first tap on Begin, so a second one before the prayer is up
  /// does not start a second prayer — written down twice, and popped twice.
  var _starting = false;

  Future<void> _begin() async {
    if (_starting) return;
    _starting = true;
    final loaded = _loaded!;
    final plan = _plan;
    final outcome = PrayerOutcome();
    // Kept before the prayer as well as after it: a prayer the app never
    // comes back from still leaves the next one prepared the same way.
    await setPrayerPrefs(widget.db, _prefs);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PrayerScreen(
          db: widget.db,
          plan: plan,
          fatiha: loaded.fatiha,
          prefs: _running,
          outcome: outcome,
        ),
      ),
    );
    await _keep(plan, outcome);
    if (mounted) Navigator.of(context).pop();
  }

  /// Writes down the prayer the reader came back from.
  ///
  /// A prayer that never comes back is not written. That is the price of the
  /// prayer screen writing nothing, and it is the side to be wrong on: the
  /// count is allowed to be short, never invented.
  Future<void> _keep(PrayerPlan plan, PrayerOutcome outcome) async {
    final db = widget.db;
    if (outcome.size case final size?) _size = size;
    await setPrayerPrefs(db, _prefs);
    final recited = <String, StudySet>{};
    for (var r = 1; r <= outcome.reached && r <= plan.rakahs; r++) {
      final set = plan.passageFor(r);
      if (set != null) recited[set.id] = set;
    }
    for (final set in recited.values) {
      await notePassageRecited(db, set);
    }
    if (plan.credited case final set? when recited.containsKey(set.id)) {
      await recordSetPrayed(db, set);
    }
  }

  Future<void> _preview() async {
    final loaded = _loaded!;
    final outcome = PrayerOutcome();
    var r = 1;
    // The preview runs at the pace whether or not the pace is chosen: there is
    // no voice to follow before the prayer, so the pace stands in for it.
    final prefs = (
      preset: _prefs.preset,
      rakahs: _rakahs,
      voice: false,
      pace: _pace || _voice,
      wpm: _wpm,
      gloss: _gloss,
      around: _around,
      arabicSize: _size,
    );
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) {
          final n = Nocturne.of(context);
          final l = AppLocalizations.of(context)!;
          return FractionallySizedBox(
            heightFactor: 0.78,
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
              child: Column(
                children: [
                  if (_rakahs > 1)
                    ColoredBox(
                      color: n.surface,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(18, 10, 18, 8),
                        child: Row(
                          spacing: 6,
                          children: [
                            for (var t = 1; t <= 2; t++)
                              PrayerChip(
                                label: l.preview_rakah(t),
                                selected: t == r,
                                onTap: () => setSheet(() => r = t),
                              ),
                          ],
                        ),
                      ),
                    ),
                  Expanded(
                    child: PrayerScreen(
                      key: ValueKey(r),
                      db: widget.db,
                      plan: _plan,
                      fatiha: loaded.fatiha,
                      prefs: prefs,
                      outcome: outcome,
                      preview: r,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (outcome.size case final size? when mounted) {
      setState(() => _size = size);
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = Nocturne.of(context);
    final l = AppLocalizations.of(context)!;
    final loaded = _loaded;
    final name = prayerName(l, _preset);
    return Scaffold(
      backgroundColor: n.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
              child: Row(
                spacing: 6,
                children: [
                  NocturneButton(
                    variant: NocturneButtonVariant.icon,
                    onPressed: () => Navigator.of(context).maybePop(),
                    child: const Icon(Icons.chevron_left, size: 18),
                  ),
                  Text(l.prepare_title, style: const TextStyle(fontSize: 17)),
                ],
              ),
            ),
            Expanded(
              child: loaded == null
                  ? _trouble
                        ? _troubleNote(n, l)
                        : const SizedBox.shrink()
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
                      children: [
                        NocturneKicker(l.prepare_kicker_prayer),
                        const SizedBox(height: 8),
                        _prayerCard(n, l),
                        const SizedBox(height: 22),
                        NocturneKicker(l.prepare_kicker_recite),
                        const SizedBox(height: 6),
                        _timeline(n, l, loaded),
                        const SizedBox(height: 18),
                        NocturneKicker(l.prepare_kicker_moves),
                        const SizedBox(height: 4),
                        _moves(n, l, loaded),
                        const SizedBox(height: 22),
                        NocturneKicker(l.prepare_kicker_screen),
                        const SizedBox(height: 4),
                        _onScreen(n, l),
                      ],
                    ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: n.divider)),
              ),
              child: Row(
                spacing: 8,
                children: [
                  NocturneButton(
                    onPressed: loaded == null ? null : _preview,
                    child: Row(
                      spacing: 8,
                      children: [
                        const Icon(Icons.visibility_outlined, size: 17),
                        Text(l.prepare_preview),
                      ],
                    ),
                  ),
                  Expanded(
                    child: NocturneButton(
                      key: const Key('begin'),
                      variant: NocturneButtonVariant.primary,
                      block: true,
                      onPressed: loaded == null ? null : _begin,
                      child: Text(
                        l.prepare_begin(name),
                        style: const TextStyle(fontSize: 15),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The prayer and its rakʿahs as one thing: the count follows the prayer,
  /// so it sits under it on the same card.
  Widget _prayerCard(Nocturne n, AppLocalizations l) => Container(
    padding: const EdgeInsets.all(3),
    decoration: BoxDecoration(
      color: n.surface,
      borderRadius: BorderRadius.circular(n.radius('lg')),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _presets(n, l),
        Container(
          height: 1,
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          color: n.divider,
        ),
        _rakahStepper(n, l),
      ],
    ),
  );

  Widget _presets(Nocturne n, AppLocalizations l) => Row(
      spacing: 3,
      children: [
        for (final preset in PrayerPreset.values)
          Expanded(
            child: Semantics(
              button: true,
              selected: preset == _preset,
              child: GestureDetector(
                onTap: () => _choosePreset(preset),
                child: Container(
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: preset == _preset
                        ? n.color('accent-900')
                        : Colors.transparent,
                    border: Border.all(
                      color: preset == _preset ? n.accent : Colors.transparent,
                    ),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    prayerName(l, preset),
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: preset == _preset ? n.color('accent-100') : n.text,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
  );

  Widget _rakahStepper(Nocturne n, AppLocalizations l) {
    final preset = _preset;
    final hint = preset == null
        ? l.prepare_rakahs_any
        : _rakahs == preset.rakahs
        ? l.prepare_rakahs_set_by(prayerName(l, preset))
        : l.prepare_rakahs_usually(prayerName(l, preset), preset.rakahs);
    return Padding(
      padding: const EdgeInsets.fromLTRB(11, 0, 5, 0),
      child: PrayerStepper(
        label: l.prepare_rakahs,
        hint: hint,
        value: _rakahs,
        less: l.prepare_fewer_rakahs,
        more: l.prepare_more_rakahs,
        onLess: _rakahs > minRakahs ? () => setState(() => _rakahs--) : null,
        onMore: _rakahs < maxRakahs ? () => setState(() => _rakahs++) : null,
      ),
    );
  }

  /// One line per rakʿah: Al-Fātiḥa in all of them, and in the first two the
  /// passage after it, which is where a tap changes it. Only those two: the
  /// plan carries a passage for two rakʿahs and no more (ADR 0020).
  Widget _timeline(Nocturne n, AppLocalizations l, _Loaded loaded) => Column(
    children: [
      for (var r = 1; r <= _rakahs; r++)
        r <= 2 ? _passageLine(n, l, loaded, r) : _line(n, l, r),
    ],
  );

  Widget _line(
    Nocturne n,
    AppLocalizations l,
    int r, {
    String? passage,
    String? meta,
    bool empty = false,
    bool open = false,
  }) => Container(
    padding: const EdgeInsets.symmetric(vertical: 11),
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: n.divider)),
    ),
    child: Row(
      spacing: 10,
      children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: open ? n.color('accent-700') : n.color('neutral-700'),
            ),
          ),
          child: Text(
            '$r',
            style: TextStyle(
              fontSize: 11,
              color: open ? n.color('accent-300') : n.textAt(0.45),
            ),
          ),
        ),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: l.prepare_fatiha,
                  style: TextStyle(color: n.textAt(0.62)),
                ),
                if (passage != null)
                  TextSpan(
                    text: ' · $passage',
                    style: TextStyle(
                      color: empty ? n.color('accent-300') : n.text,
                    ),
                  ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14),
          ),
        ),
        if (meta != null)
          Text(meta, style: TextStyle(fontSize: 11.5, color: n.textAt(0.55))),
        if (open) Icon(Icons.chevron_right, size: 16, color: n.textAt(0.5)),
      ],
    ),
  );

  Widget _passageLine(Nocturne n, AppLocalizations l, _Loaded loaded, int r) {
    final set = _plan.passageFor(r);
    final same = r == 2 && _sameAsFirst && set != null;
    final words = set == null ? 0 : [for (final a in set.ayas) ...a.words].length;
    return Semantics(
      button: true,
      child: GestureDetector(
        key: Key('passage $r'),
        behavior: HitTestBehavior.opaque,
        onTap: () => _choose(r),
        child: _line(
          n,
          l,
          r,
          open: true,
          empty: set == null,
          passage: set == null
              ? l.prepare_add_passage
              : same
              ? l.prepare_same_as_first
              : passageTitle(set, loaded.suras),
          meta: set == null ? null : aboutTime(l, words, _wpm),
        ),
      ),
    );
  }

  Widget _troubleNote(Nocturne n, AppLocalizations l) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      spacing: 14,
      children: [
        Text(
          l.prepare_trouble,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, height: 1.5, color: n.textAt(0.75)),
        ),
        NocturneButton(onPressed: _load, child: Text(l.prepare_retry)),
      ],
    ),
  );

  /// The phone has gained what voice-follow needs; once it has all of it, the
  /// reader who chose Voice is followed without a second tap. A reader who
  /// chose Steady or Tap keeps their choice.
  void _ready({MicPermission? mic, bool? model}) {
    _mic = mic ?? _mic;
    _model = model ?? _model;
  }

  Widget _moves(Nocturne n, AppLocalizations l, _Loaded loaded) {
    final moving = _moving;
    final note = switch (moving) {
      _Moves.voice when !_voiceReady => l.prepare_voice_waiting(_wpm),
      _Moves.voice => l.prepare_note_both(_wpm),
      _Moves.steady => l.prepare_note_pace(_wpm),
      _Moves.tap => l.prepare_note_neither,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 6),
        NocturneSegmented(
          key: const Key('moves'),
          options: [l.prepare_move_voice, l.prepare_move_steady, l.prepare_move_tap],
          selected: moving.index,
          onChanged: (i) => _move(_Moves.values[i]),
        ),
        // What the phone still needs before it can follow, under the choice
        // that needs it.
        if (moving == _Moves.voice && _mic != MicPermission.granted)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: NocturneButton(
              onPressed: () async {
                final mic = await askForMic(widget.db);
                if (mounted) setState(() => _ready(mic: mic));
              },
              child: Text(l.settingsAllowMicrophone),
            ),
          )
        else if (moving == _Moves.voice && !_model)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: VoiceModelPanel(
              onReady: () => setState(() => _ready(model: true)),
            ),
          ),
        if (moving != _Moves.tap)
          _row(
            n,
            title: l.prepare_wpm(_wpm),
            divided: false,
            trailing: Row(
              spacing: 6,
              children: [
                _small(l.prepare_slower, '−', () {
                  setState(() => _wpm = (_wpm - 5).clamp(15, 90));
                }),
                _small(l.prepare_faster, '+', () {
                  setState(() => _wpm = (_wpm + 5).clamp(15, 90));
                }),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            note,
            style: TextStyle(fontSize: 12, height: 1.5, color: n.textAt(0.66)),
          ),
        ),
      ],
    );
  }

  Widget _onScreen(Nocturne n, AppLocalizations l) => Column(
    children: [
      _row(
        n,
        title: l.prepare_gloss,
        trailing: _Switch(on: _gloss),
        onTap: () => setState(() => _gloss = !_gloss),
      ),
      _row(
        n,
        title: l.prepare_around,
        trailing: _Switch(on: _around),
        onTap: () => setState(() => _around = !_around),
      ),
      _row(
        n,
        title: l.prepare_size,
        sub: l.prepare_size_hint,
        trailing: Text(
          l.prepare_size_px(_size.round()),
          style: TextStyle(fontSize: 13, color: n.textAt(0.7)),
        ),
      ),
      // ponytail: a reminder, not a switch. Android can silence the phone
      // only with a permission granted in system settings, and iOS not at all,
      // so the reader does it themselves before beginning.
      _row(
        n,
        title: l.prepare_silence,
        sub: l.prepare_silence_hint,
        divided: false,
      ),
    ],
  );

  Widget _row(
    Nocturne n, {
    Widget? leading,
    required String title,
    String? sub,
    Widget? trailing,
    VoidCallback? onTap,
    bool divided = true,
  }) => Semantics(
    button: onTap != null,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          border: divided ? Border(bottom: BorderSide(color: n.divider)) : null,
        ),
        child: Row(
          spacing: 12,
          children: [
            ?leading,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 14)),
                  if (sub != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      sub,
                      style: TextStyle(fontSize: 11.5, color: n.textAt(0.58)),
                    ),
                  ],
                ],
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    ),
  );

  Widget _small(String label, String sign, VoidCallback onPressed) => Semantics(
    label: label,
    button: true,
    excludeSemantics: true,
    child: NocturneButton(
      variant: NocturneButtonVariant.icon,
      onPressed: _pace ? onPressed : null,
      child: Text(sign, style: const TextStyle(fontSize: 15)),
    ),
  );
}

/// The design's switch, which is drawn rather than Material's.
class _Switch extends StatelessWidget {
  const _Switch({required this.on});

  final bool on;

  @override
  Widget build(BuildContext context) {
    final n = Nocturne.of(context);
    return Semantics(
      toggled: on,
      child: Container(
        width: 40,
        height: 24,
        decoration: BoxDecoration(
          color: on ? n.color('accent-700') : n.color('neutral-800'),
          borderRadius: BorderRadius.circular(12),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 150),
          alignment: on ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 18,
            height: 18,
            margin: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: on ? n.color('accent-100') : n.color('neutral-500'),
            ),
          ),
        ),
      ),
    );
  }
}

/// How the text moves through the prayer: one of three, never a mix.
enum _Moves { voice, steady, tap }
