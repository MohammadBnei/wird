import 'package:record/record.dart';

/// A microphone that answers, which a test binding otherwise never does.
///
/// `record` asks the platform whether it may listen, and under `testWidgets`
/// there is no platform on the other end: the call never comes back and the
/// test hangs rather than failing. So the tests stand this behind it, the way
/// `player.dart` stands a fake platform behind just_audio.
///
/// [allows] is the reader's answer to the system prompt. [absent] is the
/// device that has no microphone at all, which throws where a refusal answers.
class FakeMic extends RecordPlatform {
  FakeMic({this.allows = true, this.absent = false});

  final bool allows;
  final bool absent;

  /// Every recorder the app built, so a test can prove the prayer screen did
  /// not open one.
  final opened = <String>[];

  @override
  Future<void> create(String recorderId) async {
    if (absent) throw StateError('no microphone on this device');
    opened.add(recorderId);
  }

  @override
  Future<bool> hasPermission(String recorderId, {bool request = true}) async {
    if (absent) throw StateError('no microphone on this device');
    return allows;
  }

  @override
  Future<void> dispose(String recorderId) async {
    opened.remove(recorderId);
  }

  /// The rest of the platform is not reached by anything under test, and a
  /// forwarder that throws says so louder than fifteen empty overrides.
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
