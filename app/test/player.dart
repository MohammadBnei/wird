import 'dart:async';

import 'package:flutter/services.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';

/// A player that behaves like the real one in the single way that matters to
/// the word row: `play()` answers when the clip ENDS, not when it starts. A
/// fake that answers immediately cannot show the second tap racing the first.
class FakePlayers extends JustAudioPlatform {
  FakePlayers({this.refuses = false});

  /// An audio platform that will not take the clip, the way a codec it does
  /// not have or a build with no plugin behind it answers.
  final bool refuses;
  final players = <FakePlayer>[];

  @override
  Future<AudioPlayerPlatform> init(InitRequest request) async {
    final player = FakePlayer(request.id)..refuses = refuses;
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
  Completer<PlayResponse>? _sounding;

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
    loaded.add(request.audioSourceMessage.toMap().toString());
    // The real plugin reports readiness after the load call returns, and
    // just_audio's setAudioSource does not answer until it does.
    Timer(Duration.zero, () => _events.add(_ready));
    return LoadResponse(duration: const Duration(seconds: 3));
  }

  PlaybackEventMessage get _ready => PlaybackEventMessage(
    processingState: ProcessingStateMessage.ready,
    updateTime: DateTime.now(),
    updatePosition: Duration.zero,
    bufferedPosition: Duration.zero,
    duration: const Duration(seconds: 3),
    icyMetadata: null,
    currentIndex: 0,
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
