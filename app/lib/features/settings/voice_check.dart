import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:sqflite/sqflite.dart';

import '../../data/speech.dart';
import '../../features/prayer/alignment.dart';
import '../../features/prayer/prayer_cursor.dart';
import '../../theme/nocturne.dart';

/// Whether voice-follow works on this phone, answered without praying.
///
/// Until this existed the only way to find out was to start a prayer, and the
/// prayer screen is the one place nothing may appear — so a reader whose
/// recogniser would not load, or whose microphone delivered nothing, saw a
/// screen that did not move and had no way to learn why. Four builds were
/// handed to a reader on that basis.
///
/// It shows what the recogniser hears and nothing else: no cursor, no set, no
/// matching. If the words below are roughly what was said, voice-follow has
/// what it needs, and anything still wrong is in the matching rather than in
/// the model, the microphone or the download.
class VoiceCheck extends StatefulWidget {
  const VoiceCheck({super.key, this.model, this.words = const []});

  final VoiceModel? model;

  /// The set the prayer would be following, so this screen answers the
  /// question the prayer screen cannot: not only what was heard, but where the
  /// matcher put the reciter in it.
  final List<String> words;

  static const heard = Key('what the recogniser heard');

  @override
  State<VoiceCheck> createState() => _VoiceCheckState();
}

enum _Stage { opening, listening, noModel, noMicrophone }

class _VoiceCheckState extends State<VoiceCheck> {
  Recogniser? _recogniser;
  AudioRecorder? _mic;
  StreamSubscription<Uint8List>? _audio;

  final _waiting = <double>[];
  var _handing = false;

  _Stage _stage = _Stage.opening;
  String _heard = '';
  int _samples = 0;
  Duration _slowest = Duration.zero;

  late final Recitation _set = Recitation(widget.words);
  late final PrayerCursor _cursor = PrayerCursor(
    widget.words.isEmpty ? 1 : widget.words.length,
  );
  var _moves = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    final model =
        widget.model ?? await VoiceModel.beside(await getDatabasesPath());
    final recogniser = await Recogniser.open(model);
    if (recogniser == null) {
      if (mounted) setState(() => _stage = _Stage.noModel);
      return;
    }
    final mic = AudioRecorder();
    if (!await mic.hasPermission()) {
      await recogniser.close();
      await mic.dispose();
      if (mounted) setState(() => _stage = _Stage.noMicrophone);
      return;
    }
    final audio = await mic.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: heardSampleRate,
        numChannels: 1,
        autoGain: false,
        noiseSuppress: false,
      ),
    );
    if (!mounted) {
      await recogniser.close();
      await mic.dispose();
      return;
    }
    setState(() {
      _recogniser = recogniser;
      _mic = mic;
      _stage = _Stage.listening;
      _audio = audio.listen(_keep, onError: (_) {});
    });
  }

  void _keep(Uint8List chunk) {
    final floats = pcm16ToFloat(chunk);
    _waiting.addAll(floats);
    _samples += floats.length;
    unawaited(_handOver());
  }

  Future<void> _handOver() async {
    final recogniser = _recogniser;
    if (_handing || recogniser == null || _waiting.isEmpty) return;
    _handing = true;
    try {
      while (_waiting.isNotEmpty && mounted) {
        final samples = Float32List.fromList(_waiting);
        _waiting.clear();
        final began = DateTime.now();
        final heard = await recogniser.hear(samples);
        final took = DateTime.now().difference(began);
        if (!mounted) return;
        if (heard.isNotEmpty && !_set.isEmpty) {
          final was = _cursor.at;
          final at = locate(_set, heard);
          if (at != null) _cursor.moveTo(at.word);
          if (_cursor.at != was) _moves++;
        }
        setState(() {
          if (took > _slowest) _slowest = took;
          if (heard.isNotEmpty) _heard = heard;
        });
      }
    } on Object {
      // The panel says what it has. Nothing here is worth failing over.
    } finally {
      _handing = false;
    }
  }

  @override
  void dispose() {
    unawaited(_audio?.cancel());
    unawaited(_recogniser?.close());
    unawaited(_mic?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = Nocturne.of(context);
    return Scaffold(
      backgroundColor: n.color('bg'),
      appBar: AppBar(
        backgroundColor: n.color('bg'),
        title: const Text('Can this phone hear you?'),
      ),
      body: Padding(
        padding: EdgeInsets.all(n.space('4')),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_whatIsHappening(), style: TextStyle(color: n.color('neutral-500'))),
            if (widget.words.isNotEmpty) ...[
              SizedBox(height: n.space('2')),
              // Which set the prayer would be following. A reader reciting one
              // passage while the walk proposes another would see a screen
              // that never moves, and nothing else here would say why.
              Text(
                'the set: ${widget.words.take(5).join(' ')}…',
                textDirection: TextDirection.rtl,
                style: TextStyle(color: n.color('accent-400')),
              ),
            ],
            SizedBox(height: n.space('4')),
            if (_stage == _Stage.listening) ...[
              Expanded(
                child: SingleChildScrollView(
                  reverse: true,
                  child: Text(
                    key: VoiceCheck.heard,
                    _heard.isEmpty ? '…' : _heard,
                    textDirection: TextDirection.rtl,
                    style: TextStyle(color: n.color('text'), fontSize: 24),
                  ),
                ),
              ),
              // Not decoration: a reader who sees no words needs to know
              // whether the microphone is delivering nothing or the recogniser
              // is making nothing of it, and those look identical above.
              if (!_set.isEmpty)
                Text(
                  'the prayer would be on word ${_cursor.at + 1} of '
                  '${widget.words.length}, after $_moves moves',
                  style: TextStyle(color: n.color('accent-400')),
                ),
              Text(
                '${(_samples / heardSampleRate).toStringAsFixed(1)}s of voice, '
                'slowest answer ${_slowest.inMilliseconds}ms',
                style: TextStyle(color: n.color('neutral-500')),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _whatIsHappening() => switch (_stage) {
    _Stage.opening => 'Starting the recogniser…',
    _Stage.listening => 'Recite, and the words you say should appear below.',
    _Stage.noModel =>
      'The recogniser did not start. The download may be incomplete, or this '
          'phone may not be able to load it. Voice-follow stays off and the '
          'prayer screen answers your tap, as it always has.',
    _Stage.noMicrophone =>
      'The microphone was refused, so there is nothing to hear.',
  };
}
