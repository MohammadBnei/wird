import 'package:flutter/material.dart';

import '../../app.dart';
import '../../data/mic.dart';
import '../../data/sets.dart';
import '../../theme/nocturne.dart';
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  Future<void> _load() async {
    final wird = Wird.of(context);
    final next = await nextSet(wird.db, wird.prefs.order);
    if (mounted) setState(() => _next = next);
  }

  Future<void> _resize(StudySet set, int by) async {
    await setDragSpan(
      Wird.of(context).db,
      set.ayas.first.id,
      set.ayas.length + by,
    );
    await _load();
  }

  String _micCaption(MicPermission mic) => switch (mic) {
    MicPermission.notAsked =>
      'Voice-follow needs the microphone. Off by default; never asked for '
          'during a prayer.',
    MicPermission.granted =>
      'Microphone allowed. Voice-follow stays off until you turn it on.',
    MicPermission.denied =>
      'Microphone refused. The prayer screen advances on a tap, as it always '
          'does.',
    MicPermission.unavailable =>
      'This build cannot reach the microphone. The prayer screen advances on '
          'a tap.',
  };

  @override
  Widget build(BuildContext context) {
    final n = Nocturne.of(context);
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
              Text('Settings', style: Theme.of(context).textTheme.displaySmall),
              _section(n, 'READING'),
              NocturneSegmented(
                options: const ['Gloss', 'Translit', 'Both', 'Neither'],
                selected: prefs.display,
                onChanged: prefs.setDisplay,
              ),
              SizedBox(height: n.space('1')),
              _caption(n, 'What is printed under each Arabic word.'),
              SizedBox(height: n.space('3')),
              NocturneSegmented(
                options: const ['Chronological', 'Muṣḥaf'],
                selected: prefs.order.index,
                onChanged: (i) async {
                  await prefs.setOrder(ReadingOrder.values[i]);
                  await _load();
                },
              ),
              SizedBox(height: n.space('1')),
              _caption(
                n,
                'The chronology orders sūras; ayas inside a sūra stay in '
                'written order.',
              ),
              SizedBox(height: n.space('3')),
              Row(
                children: [
                  // The design's panel printed the size in pixels, which is
                  // the number a designer turns and not one a reader has any
                  // use for. Where the thumb sits is the whole answer.
                  Text(
                    'Arabic',
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
              _caption(n, 'How large the Arabic is set on the reading screen.'),
              _section(n, 'HOW MUCH YOU TAKE AT ONCE'),
              _width(n),
              _section(n, 'MICROPHONE'),
              // Voice-follow is a later phase and off by default. The
              // microphone is asked for here and only here: the in-prayer
              // screen may not raise a dialog, so it can never be the screen
              // that asks.
              NocturneButton(
                onPressed: prefs.askForTheMic,
                child: const Text('Allow microphone'),
              ),
              SizedBox(height: n.space('1')),
              _caption(n, _micCaption(prefs.mic)),
              // Writes the server would not take are named here and only
              // here. It draws its own heading and stays silent when there
              // are none, so a reader with a healthy outbox sees nothing.
              ParkedWrites(db: wird.db),
              // Last, because it is the one thing on this screen a reader
              // never has to do. Nothing above it — or anywhere else in the
              // app — waits on an account.
              _section(n, 'ACCOUNT'),
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
  Widget _width(Nocturne n) {
    final set = _next;
    if (set == null) {
      return _caption(n, 'Every aya is understood, so no set is waiting.');
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
              set.ayas.length == 1 ? '1 aya' : '${set.ayas.length} ayas',
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
        _caption(
          n,
          'A wider set may cross an aya you already understood. It is '
          'recited with the rest and stays counted where it is.',
        ),
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
