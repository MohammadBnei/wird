import 'dart:io';

import 'package:wird/data/audio.dart';

/// Refuses every download and remembers it was asked, so a test that claims
/// the recitation survives the radio going off cannot quietly pass on a
/// machine that still has one.
class RadioOff {
  final attempts = <String>[];

  Future<List<int>> call(String url) {
    attempts.add(url);
    throw const SocketException('the radio is off');
  }
}

/// Serves an MP3 of a fixed size for whatever is asked for.
class FakeCdn {
  FakeCdn({this.bytes = 1024});

  final int bytes;
  final served = <String>[];

  Future<List<int>> call(String url) async {
    served.add(url);
    return List.filled(bytes, 0);
  }
}

Future<Directory> tempAudioDir() =>
    Directory.systemTemp.createTemp('wird-audio');

/// A cache that holds nothing and can fetch nothing: screen 1a on a phone
/// that has never been online.
Future<AudioCache> emptyCache() async =>
    AudioCache(await tempAudioDir(), fetch: RadioOff().call);
