import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wird/data/db.dart';
import 'package:wird/data/mic.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  setUp(() async => db = await openWirdAt(inMemoryDatabasePath));
  tearDown(() => db.close());

  test('the button that asks for the microphone can no longer only fail', () {
    // It answered `unavailable` on every phone before the recorder was wired
    // to it, which made voice-follow unreachable rather than off.
    expect(
      askForMic(db, ask: () async => true),
      completion(MicPermission.granted),
    );
  });

  test('a refusal is remembered as the reader\'s and not the device\'s', () {
    // The two say different things in Settings: a refusal can be asked again,
    // a device with no microphone cannot.
    expect(
      askForMic(db, ask: () async => false),
      completion(MicPermission.denied),
    );
    expect(
      askForMic(db, ask: () async => throw StateError('no microphone')),
      completion(MicPermission.unavailable),
    );
  });

  test('the answer outlives the screen that asked for it, so the prayer '
      'never has to', () async {
    await askForMic(db, ask: () async => true);
    expect(await micPermission(db), MicPermission.granted);

    // Asked a second time and refused: the prayer screen reads the latest
    // answer, not the first one.
    await askForMic(db, ask: () async => false);
    expect(await micPermission(db), MicPermission.denied);
  });
}
