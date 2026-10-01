import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import '../../app.dart';
import '../../data/db.dart';
import '../../data/mic.dart';
import '../../data/senses.dart';
import '../../data/sets.dart';
import '../../data/speech.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/nocturne.dart';
import 'voice_check.dart';
import '../../widgets/nocturne_button.dart';
import '../../widgets/nocturne_rule.dart';
import '../../widgets/nocturne_segmented.dart';
import 'account_panel.dart';
import 'parked_writes.dart';

/// What the reader sets and forgets.
///
/// These controls used to share one collapsed panel on the reading screen with
/// the doors to every other screen and with the button that starts a prayer:
/// preferences, navigation and the app's central act in one drawer, because
/// that panel was the only place the design left free. The three are three
/// different things and they now have three homes — navigation in the shell's
/// drawer, the prayer on the screen the app opens to, and preferences here.
///
/// What a preference must do is outlast the screen it was set from, which is
/// why they are held by the application rather than by a State object.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  /// The set the walk has ready. The width control below changes how much of
  /// the Qur'an the next prayer carries, so it needs the aya that set starts
  /// at.
  StudySet? _next;

  /// Who recites the audio the app plays. It came off the reading screen's
  /// transport, where it sat beside the play button and read as that button's
  /// state — which it is not: it never changes while a set is open, and the
  /// state the button does have is whether the recitation is on the phone.
  /// That half stayed on the transport, with the button it disables.
  String? _reciter;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  Future<void> _load() async {
    final wird = Wird.of(context);
    final next = await nextSet(wird.db, wird.prefs.order);
    final reciter = await reciterLabel(wird.db);
    if (mounted) {
      setState(() {
        _next = next;
        _reciter = reciter;
      });
    }
  }

  Future<void> _resize(StudySet set, int by) async {
    await setDragSpan(
      Wird.of(context).db,
      set.ayas.first.id,
      set.ayas.length + by,
    );
    await _load();
  }

  String _micCaption(AppLocalizations l, MicPermission mic) => switch (mic) {
    MicPermission.notAsked => l.settingsMicNotAsked,
    MicPermission.granted => l.settingsMicGranted,
    MicPermission.denied => l.settingsMicDenied,
    MicPermission.unavailable => l.settingsMicUnavailable,
  };

  @override
  Widget build(BuildContext context) {
    final n = Nocturne.of(context);
    final l = AppLocalizations.of(context)!;
    final wird = Wird.of(context);
    final prefs = wird.prefs;
    return Scaffold(
      backgroundColor: n.bg,
      body: ListenableBuilder(
        listenable: prefs,
        builder: (context, _) => SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            n.space('6'),
            n.space('2'),
            n.space('6'),
            n.space('8'),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.settingsTitle,
                style: Theme.of(context).textTheme.displaySmall,
              ),
              _section(n, l.settingsLanguage),
              NocturneSegmented(
                options: [
                  l.settingsLanguageEnglish,
                  l.settingsLanguageFrench,
                ],
                // The language being read, which is the reader's choice or
                // their phone's until they make one. There is no third option
                // for "my phone's": a reader picking their own language is not
                // choosing between a language and a way of choosing one, and
                // the phone's is already the one they can see selected.
                selected:
                    Localizations.localeOf(context).languageCode == 'fr' ? 1 : 0,
                onChanged: (i) =>
                    prefs.setLocale(Locale(i == 1 ? 'fr' : 'en')),
              ),
              SizedBox(height: n.space('1')),
              _caption(n, l.settingsLanguageCaption),
              SizedBox(height: n.space('3')),
              _section(n, l.settingsReading),
              NocturneSegmented(
                options: [
                  l.settingsWordGloss,
                  l.settingsWordTranslit,
                  l.settingsWordBoth,
                  l.settingsWordNeither,
                ],
                selected: prefs.display,
                onChanged: prefs.setDisplay,
              ),
              SizedBox(height: n.space('1')),
              _caption(n, l.settingsWordCaption),
              SizedBox(height: n.space('3')),
              NocturneSegmented(
                options: [
                  l.settingsAyaTranslationShown,
                  l.settingsAyaTranslationHidden,
                ],
                selected: prefs.ayaTranslation ? 0 : 1,
                onChanged: (i) => prefs.setAyaTranslation(i == 0),
              ),
              SizedBox(height: n.space('1')),
              _caption(n, l.settingsAyaTranslationCaption),
              SizedBox(height: n.space('3')),
              NocturneSegmented(
                options: [
                  l.settingsOrderChronological,
                  l.settingsOrderMushaf,
                ],
                selected: prefs.order.index,
                onChanged: (i) async {
                  await prefs.setOrder(ReadingOrder.values[i]);
                  await _load();
                },
              ),
              SizedBox(height: n.space('1')),
              _caption(n, l.settingsOrderCaption),
              SizedBox(height: n.space('3')),
              Row(
                children: [
                  // The design's panel printed the size in pixels, which is
                  // the number a designer turns and not one a reader has any
                  // use for. Where the thumb sits is the whole answer.
                  Text(
                    l.settingsArabic,
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
                        value: prefs.arabicSize,
                        onChanged: prefs.setArabicSize,
                      ),
                    ),
                  ),
                ],
              ),
              _caption(n, l.settingsArabicCaption),
              _section(n, l.settingsSetWidth),
              _width(n, l),
              _section(n, l.settingsRecitation),
              // Read-only: the corpus ships the paths for one reciter and
              // there is nothing here to choose between. It is said once,
              // here, rather than under the play button, where a name that
              // never changes read as the transport's own state.
              //
              // Who recites is all this says. It used to add that nothing
              // would play — a claim this query cannot see: the name comes
              // from `recitations` while what plays is decided by ayah_audio,
              // and either table can be populated without the other. Whether
              // a set is playable is said on the screen that knows, under the
              // button it disables.
              _caption(
                n,
                _reciter == null
                    ? l.settingsNoReciter
                    : l.settingsRecitedBy(_reciter!),
              ),
              // The senses sit with what a root means, not with the voice: the
              // recogniser below is a feature a reader turns on, and this is
              // the app's own content arriving. It is drawn unconditionally —
              // a reader who never comes here still gets their first pack from
              // `Flusher`, but a correction has nowhere else to be pressed.
              _section(n, l.settingsSenses),
              SensePanel(db: wird.db),
              _section(n, l.settingsMicrophone),
              // Voice-follow is a later phase and off by default. The
              // microphone is asked for here and only here: the in-prayer
              // screen may not raise a dialog, so it can never be the screen
              // that asks.
              if (prefs.mic != MicPermission.granted)
                // Asking is offered until a yes closes it, and the guard
                // above is the whole condition. It used to be disabled on
                // `unavailable` as well — but that is what askForMic writes
                // when the request THREW, and a caught exception is not a fact
                // about the hardware: a plugin not yet registered, a recorder
                // busy elsewhere, a build that could not ask at all land
                // there. Disabling on it made one bad moment permanent, and an
                // upgrade carried the verdict forward, because the build
                // before voice-follow answered `unavailable` by design and
                // mic_consent outlives a reinstall.
                NocturneButton(
                  onPressed: prefs.askForTheMic,
                  child: Text(l.settingsAllowMicrophone),
                ),
              SizedBox(height: n.space('1')),
              _caption(n, _micCaption(l, prefs.mic)),
              // The recogniser is settled here too, and for the same reason:
              // a 160 MB download is not something to discover mid-prayer.
              if (prefs.mic == MicPermission.granted)
                VoiceModelPanel(
                  // The set the walk would hand the prayer, so the check can
                  // say where the matcher puts the reciter in it rather than
                  // only what was heard.
                  words: [
                    for (final aya in _next?.ayas ?? const <StudyAya>[])
                      for (final word in aya.words) word.text,
                  ],
                ),
              // Writes the server would not take are named here and only
              // here. It draws its own heading and stays silent when there
              // are none, so a reader with a healthy outbox sees nothing.
              ParkedWrites(db: wird.db),
              // Last, because it is the one thing on this screen a reader
              // never has to do. Nothing above it — or anywhere else in the
              // app — waits on an account.
              _section(n, l.settingsAccount),
              AccountPanel(db: wird.db),
            ],
          ),
        ),
      ),
    );
  }

  /// The set's width is the reader's, not the walk's: five ayas inside the
  /// word budget is what the walk proposes, and this is where the reader says
  /// otherwise. It is held against the aya the next set starts at, so a width
  /// set here applies to the portion the reader is about to pray and not to
  /// every set they will ever be handed.
  Widget _width(Nocturne n, AppLocalizations l) {
    final set = _next;
    if (set == null) {
      return _caption(n, l.settingsNoSetWaiting);
    }
    final understood = set.ayas.every((a) => a.understood);
    // The explanation sits under the stepper rather than beside it: three
    // lines of prose 8px from a control read as one thing, and the reader
    // cannot tell which of the two they are meant to act on.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          spacing: n.space('3'),
          children: [
            NocturneButton(
              key: const Key('narrow set'),
              variant: NocturneButtonVariant.icon,
              onPressed: understood || set.ayas.length == 1
                  ? null
                  : () => _resize(set, -1),
              child: const Icon(Icons.remove),
            ),
            Text(
              l.settingsSetAyas(set.ayas.length),
              style: TextStyle(fontSize: 11, color: n.textAt(0.55)),
            ),
            NocturneButton(
              key: const Key('widen set'),
              variant: NocturneButtonVariant.icon,
              onPressed: understood || set.ayas.length >= setMaxDragAyas
                  ? null
                  : () => _resize(set, 1),
              child: const Icon(Icons.add),
            ),
          ],
        ),
        SizedBox(height: n.space('1')),
        _caption(n, l.settingsSetWidthCaption),
      ],
    );
  }

  Widget _section(Nocturne n, String label) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SizedBox(height: n.space('6')),
      Text(
        label,
        style: TextStyle(
          fontSize: 10,
          height: 1.2,
          letterSpacing: 0.11 * 10,
          color: n.accent,
        ),
      ),
      const NocturneRule(fade: 30),
    ],
  );

  Widget _caption(Nocturne n, String text) => Text(
    text,
    style: TextStyle(fontSize: 10.5, height: 1.4, color: n.textAt(0.5)),
  );
}

/// Which of the six things is true of the senses on this phone right now.
///
/// One enum rather than [VoiceModelPanel]'s four fields: that panel's states
/// are a download's, and they overlap — partly arrived, arrived, cancelled.
/// These six are exclusive, so the switch below is exhaustive and the compiler
/// is what keeps a state from having no caption.
enum _Senses {
  asking,
  onOffer,
  installing,
  current,
  unreachable,
  notThisCorpus,
}

/// The senses, which are fetched rather than bundled, and the one button that
/// brings them down.
///
/// Modelled on [VoiceModelPanel]: one button, one caption saying why that is
/// the button, no switch. What differs is who may act unasked. Nobody
/// downloads 160 MB of weights on a reader's behalf, while a phone with no
/// senses at all is an app whose screens describe content it does not have —
/// so `Flusher` fetches the first pack itself, silently, and this panel is for
/// everything after: ADR 0010's payoff is a wrong sense fixed in minutes, and
/// this is where the reader takes the fix.
///
/// There is deliberately no percentage and no Stop. `installSenses` buffers
/// and validates the whole body before it writes a row, which is what makes a
/// truncated answer harmless; a cancel button over a few hundred kilobytes
/// would be a control whose only effect is to make the reader press again.
class SensePanel extends StatefulWidget {
  const SensePanel({super.key, required this.db, this.over});

  final Database db;

  /// The senses route, for a test to stand in for. Null in the app, where
  /// `senses.dart` builds its own against the origin the queue uses.
  final Dio? over;

  static const download = Key('download senses');
  static const askAgain = Key('ask again for senses');

  @override
  State<SensePanel> createState() => _SensePanelState();
}

class _SensePanelState extends State<SensePanel> {
  _Senses _state = _Senses.asking;

  @override
  void initState() {
    super.initState();
    unawaited(_ask());
  }

  /// The HEAD, which moves no bytes. It cannot be what the first frame waits
  /// on, so until it answers the panel says it is asking.
  Future<void> _ask() async {
    if (mounted) setState(() => _state = _Senses.asking);
    try {
      final offered = await sensesOnOffer(widget.db, over: widget.over);
      _settle(offered == null ? _Senses.current : _Senses.onOffer);
    } on Object {
      // Any failure to reach the server is one sentence to a reader: a
      // timeout, a captive portal's sign-in page and a 500 differ in nothing
      // they can act on.
      _settle(_Senses.unreachable);
    }
  }

  Future<void> _install() async {
    setState(() => _state = _Senses.installing);
    try {
      // Null is the pack that named no root this corpus records. It rolled the
      // transaction back, so the reader still has what they had, and the one
      // thing the panel must not do is redraw Download over a press that can
      // never succeed.
      final installed = await installSenses(widget.db, over: widget.over);
      _settle(installed == null ? _Senses.notThisCorpus : _Senses.current);
    } on Object {
      _settle(_Senses.unreachable);
    }
  }

  void _settle(_Senses state) {
    if (mounted) setState(() => _state = state);
  }

  @override
  Widget build(BuildContext context) {
    final n = Nocturne.of(context);
    final l = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: n.space('3')),
        if (_state == _Senses.onOffer)
          NocturneButton(
            key: SensePanel.download,
            onPressed: _install,
            child: Text(l.settingsDownloadSenses),
          )
        else if (_state == _Senses.unreachable)
          NocturneButton(
            key: SensePanel.askAgain,
            variant: NocturneButtonVariant.ghost,
            onPressed: _ask,
            child: Text(l.settingsSensesAskAgain),
          ),
        SizedBox(height: n.space('1')),
        Text(
          _whyThisButton(l),
          style: TextStyle(fontSize: 10.5, height: 1.4, color: n.textAt(0.5)),
        ),
      ],
    );
  }

  String _whyThisButton(AppLocalizations l) => switch (_state) {
    _Senses.asking => l.settingsSensesAsking,
    _Senses.onOffer => l.settingsSensesOnOffer,
    _Senses.installing => l.settingsSensesInstalling,
    _Senses.current => l.settingsSensesCurrent,
    _Senses.unreachable => l.settingsSensesUnreachable,
    _Senses.notThisCorpus => l.settingsSensesNotThisCorpus,
  };
}

/// The recogniser voice-follow listens with: whether it is on the phone, and
/// the one button that changes that.
///
/// There is no separate "turn voice-follow on" switch. Downloading a hundred
/// and sixty megabytes is the clearest yes a reader can give, and Remove is
/// the no. A reader who wants the microphone but not the model simply never
/// presses Download, and the prayer screen advances on a tap the way it has
/// since before any of this existed.
class VoiceModelPanel extends StatefulWidget {
  const VoiceModelPanel({
    super.key,
    this.model,
    this.words = const [],
    this.onReady,
  });

  /// Called once the recogniser is on disk, found there or just downloaded.
  final VoidCallback? onReady;

  /// The one thing the phone supplies and a test stands in for: the model
  /// beside the database, and the host it is fetched from.
  final VoiceModel? model;

  /// The set the reader's prayer would follow, passed through to the check.
  final List<String> words;

  static const download = Key('download recogniser');
  static const stop = Key('stop recogniser download');
  static const remove = Key('remove recogniser');
  static const check = Key('check recogniser');

  @override
  State<VoiceModelPanel> createState() => _VoiceModelState();
}

class _VoiceModelState extends State<VoiceModelPanel> {
  VoiceModel? _model;
  CancelToken? _fetching;
  VoiceModelTrouble? _trouble;
  bool _ready = false;
  int _received = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_find());
  }

  @override
  void dispose() {
    // A reader who walks away from Settings has stopped asking for the model.
    _fetching?.cancel();
    super.dispose();
  }

  /// Where the model would be, which is real file work and so cannot be what
  /// the first frame waits on. Until it answers the panel says what is true of
  /// every phone that has never downloaded it.
  Future<VoiceModel?> _find() async {
    try {
      final model =
          _model ??
          widget.model ??
          await VoiceModel.beside(await getDatabasesPath());
      if (mounted) {
        setState(() {
          _model = model;
          _ready = model.ready;
          _received = model.bytesOnDisk;
        });
        if (model.ready) widget.onReady?.call();
      }
      return model;
    } on Object {
      // No directory to put a model in is the same answer as no model.
      return null;
    }
  }

  Future<void> _download() async {
    final model = await _find();
    if (model == null || !mounted) return;
    final cancel = CancelToken();
    setState(() {
      _fetching = cancel;
      _trouble = null;
    });
    final trouble = await model.fetch(
      cancel: cancel,
      onProgress: (received, _) {
        if (mounted) setState(() => _received = received);
      },
    );
    if (mounted) {
      setState(() {
        _fetching = null;
        _trouble = trouble;
        _ready = model.ready;
        _received = model.bytesOnDisk;
      });
      if (model.ready) widget.onReady?.call();
    }
  }

  Future<void> _remove() async {
    await _model?.remove();
    if (mounted) {
      setState(() {
        _ready = false;
        _received = 0;
      });
    }
  }

  /// The download's size in megabytes. The unit itself belongs to the string
  /// the reader reads — it is MB in English and Mo in French — so only the
  /// number is handed over.
  int get _megabytes => (voiceModelBytes / 1000000).round();

  @override
  Widget build(BuildContext context) {
    final n = Nocturne.of(context);
    final l = AppLocalizations.of(context)!;
    final done = (_received / voiceModelBytes * 100).clamp(0, 99).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: n.space('3')),
        if (_fetching != null)
          NocturneButton(
            key: VoiceModelPanel.stop,
            variant: NocturneButtonVariant.ghost,
            onPressed: () => _fetching?.cancel(),
            child: Text(l.settingsStopDownload(done)),
          )
        else if (_ready) ...[
          NocturneButton(
            key: VoiceModelPanel.check,
            variant: NocturneButtonVariant.ghost,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => VoiceCheck(
                model: _model,
                words: widget.words,
              ),
              ),
            ),
            child: Text(l.settingsCheckRecogniser),
          ),
          SizedBox(height: n.space('1')),
          NocturneButton(
            key: VoiceModelPanel.remove,
            variant: NocturneButtonVariant.ghost,
            onPressed: _remove,
            child: Text(l.settingsRemoveRecogniser),
          ),
        ]
        else
          NocturneButton(
            key: VoiceModelPanel.download,
            onPressed: _download,
            child: Text(l.settingsDownloadRecogniser(_megabytes)),
          ),
        SizedBox(height: n.space('1')),
        Text(
          _whyThisButton(l),
          style: TextStyle(fontSize: 10.5, height: 1.4, color: n.textAt(0.5)),
        ),
      ],
    );
  }

  String _whyThisButton(AppLocalizations l) {
    if (_fetching != null) return l.settingsRecogniserDownloading;
    if (_ready) return l.settingsRecogniserReady;
    return switch (_trouble) {
      VoiceModelTrouble.notServed => l.settingsRecogniserNotServed,
      VoiceModelTrouble.interrupted => l.settingsRecogniserInterrupted,
      null when _received > 0 => l.settingsRecogniserPartial,
      null => l.settingsRecogniserAbsent,
    };
  }
}
