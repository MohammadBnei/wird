import 'dart:async';

import 'package:flutter/services.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';

/// A player that behaves like the real one in the single way that matters to
/// the word row: `play()` answers when the clip ENDS, not when it starts. A
/// fake that answers immediately cannot show the second tap racing the first.
class FakePlayers extends JustAudioPlatform {
  FakePlayers({this.refuses = false, this.offline = false});

  /// An audio platform that will not take the clip, the way a codec it does
  /// not have or a build with no plugin behind it answers.
  final bool refuses;

  /// A phone with no network: a file on disk loads, a URL does not, the way
  /// the real player fails to open a source it cannot reach.
  final bool offline;
  final players = <FakePlayer>[];

  @override
  Future<AudioPlayerPlatform> init(InitRequest request) async {
    final player = FakePlayer(request.id)
      ..refuses = refuses
      ..offline = offline;
    players.add(player);
    return player;
  }

  @override
  Future<DisposePlayerResponse> disposePlayer(
    DisposePlayerRequest request,
  ) async => DisposePlayerResponse();

  @override
  Future<DisposeAllPlayersResponse> disposeAllPlayers(
    DisposeAllPlayersRequest request,
  ) async => DisposeAllPlayersResponse();

  FakePlayer get only => players.single;
}

class FakePlayer extends AudioPlayerPlatform {
  FakePlayer(super.id);

  final _events = StreamController<PlaybackEventMessage>.broadcast();
  final loaded = <String>[];
  bool refuses = false;
  bool offline = false;
  Completer<PlayResponse>? _sounding;

  /// Where each load was asked to start, in the order they came.
  final starts = <Duration?>[];

  /// Set, every load waits on it: the files are still being opened, the way
  /// a streamed aya keeps a real player loading for seconds.
  Completer<void>? gate;

  var _position = Duration.zero;
  var _index = 0;

  /// The player has got to [position] in the [index]th file, as a real one
  /// reports it while it plays.
  void reach(Duration position, {int index = 0}) {
    _position = position;
    _index = index;
    _events.add(_ready);
  }

  bool get sounding => _sounding != null;

  /// The clip runs out, the way a file does.
  void finish() {
    final done = _sounding;
    _sounding = null;
    done?.complete(PlayResponse());
  }

  @override
  Stream<PlaybackEventMessage> get playbackEventMessageStream => _events.stream;

  @override
  Future<LoadResponse> load(LoadRequest request) async {
    if (refuses) throw PlatformException(code: 'abort');
    final source = request.audioSourceMessage.toMap().toString();
    if (offline && source.contains(RegExp('https?://'))) {
      throw PlatformException(code: 'unreachable');
    }
    loaded.add(source);
    starts.add(request.initialPosition);
    _position = request.initialPosition ?? Duration.zero;
    _index = request.initialIndex ?? 0;
    if (gate case final gate?) await gate.future;
    // The real plugin reports readiness after the load call returns, and
    // just_audio's setAudioSource does not answer until it does.
    Timer(Duration.zero, () => _events.add(_ready));
    return LoadResponse(duration: const Duration(seconds: 3));
  }

  PlaybackEventMessage get _ready => PlaybackEventMessage(
    processingState: ProcessingStateMessage.ready,
    updateTime: DateTime.now(),
    updatePosition: _position,
    bufferedPosition: Duration.zero,
    duration: const Duration(seconds: 3),
    icyMetadata: null,
    currentIndex: _index,
    androidAudioSessionId: null,
  );

  @override
  Future<PlayResponse> play(PlayRequest request) =>
      (_sounding ??= Completer<PlayResponse>()).future;

  @override
  Future<PauseResponse> pause(PauseRequest request) async {
    finish();
    return PauseResponse();
  }

  @override
  Future<SeekResponse> seek(SeekRequest request) async => SeekResponse();

  @override
  Future<SetVolumeResponse> setVolume(SetVolumeRequest request) async =>
      SetVolumeResponse();

  @override
  Future<SetSpeedResponse> setSpeed(SetSpeedRequest request) async =>
      SetSpeedResponse();

  @override
  Future<SetLoopModeResponse> setLoopMode(SetLoopModeRequest request) async =>
      SetLoopModeResponse();

  @override
  Future<SetShuffleModeResponse> setShuffleMode(
    SetShuffleModeRequest request,
  ) async => SetShuffleModeResponse();
}
