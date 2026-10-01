import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wird/app.dart';
import 'package:wird/data/audio.dart';
import 'package:wird/data/db.dart';
import 'package:wird/data/flush.dart';
import 'package:wird/data/kept_repo.dart';
import 'package:wird/data/outbox.dart';
import 'package:wird/data/sets.dart';
import 'package:wird/data/sync.dart';
import 'package:wird/nav.dart';

import '../corpus.dart';
import '../offline.dart';
import '../wird.dart';

/// The server, one seam closer in than the socket the sync tests use: a
/// widget test runs on a fake clock and a socket does not. What is asserted
/// here is the same as there — which ops left the phone, in how many rounds,
/// and that the outbox in the real database is empty afterwards.
class ServerInTheRoom implements SyncApi {
  final rounds = <List<String>>[];

  List<String> get taken => [for (final round in rounds) ...round];

  @override
  Dio get dio => throw UnsupportedError('this server is not on a socket');

  @override
  Future<List<OpVerdict>> push(List<PendingOp> ops) async {
    rounds.add([for (final op in ops) op.kind]);
    return [for (final op in ops) OpVerdict(op.id, 'applied')];
  }

  @override
  Future<ChangePage> pull(String cursor) async =>
      const ChangePage([], '', false);
}

Future<int> queued(Database db) async =>
    (await db.rawQuery('SELECT COUNT(*) AS n FROM outbox')).single['n']! as int;

/// The app in a pocket and out again, sent down the channel the platform
/// sends it down, so what is under test is the app's own answer to the
/// foreground rather than a method a test called by hand.
Future<void> theAppComesBack() async {
  for (final state in [
    AppLifecycleState.inactive,
    AppLifecycleState.paused,
    AppLifecycleState.resumed,
  ]) {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          'flutter/lifecycle',
          const StringCodec().encodeMessage(state.toString()),
          (_) {},
        );
  }
}

void main() {
  late Database db;
  late AudioCache silent;

  setUp(() async {
    db = await testCorpus();
    await ensureKeptTable(db);
    await db.delete('kept_items');
    await db.execute('DROP TABLE IF EXISTS sync_state');
    silent = await emptyCache();
  });

  Future<Widget> theApp(Flusher flusher) async => wirdApp(
    db,
    prefs: await Prefs.read(db),
    recitation: Recitation(cache: silent),
    flusher: flusher,
  );

  // The failure this round exists for. The outbox, the retry budget, the
  // change cursor and the contract vectors were all built and certified, and
  // no shipped build ever called the flush — so a reader's month of
  // understood ayas, kept notes and counted prayers sat on the phone until
  // they uninstalled it, and the server had never heard of any of it.
  testWidgets("a reader's month of progress never reaches the server because "
      'nothing ever asked it to', (tester) async {
    await markSetUnderstood(db, newOpId(), [96001, 96002, 96003]);
    await keep(db, kind: KeptKind.note, body: 'the pen and what it writes');
    await setReadingOrder(db, ReadingOrder.mushaf);
    expect(await queued(db), 3);

    // The reader opens the app with a signal for the first time in a month.
    final server = ServerInTheRoom();
    await pumpPhone(
      tester,
      await theApp(Flusher(db, server, gap: Duration.zero)),
    );
    await tester.pumpAndSettle();

    expect(
      await queued(db),
      0,
      reason: 'the app opened and asked nobody to carry the queue',
    );
    expect(server.taken, ['ayah_understood', 'kept_upsert', 'prefs_set']);

    // And what they write with the app already open leaves on the next return
    // to the foreground, not next month.
    await keep(db, kind: KeptKind.note, body: 'written at the gate');
    expect(await queued(db), 1);

    await theAppComesBack();
    await tester.pumpAndSettle();

    expect(
      await queued(db),
      0,
      reason: 'the app came back to the foreground and asked for nothing',
    );
  });

  // The other half of the same decision: a flush cheap enough to run on every
  // return is still a radio wake, and a phone is unlocked dozens of times an
  // hour.
  test('every unlock wakes the radio, and the reader watches the battery go',
      () async {
    final server = ServerInTheRoom();
    final flusher = Flusher(db, server);

    await markSetUnderstood(db, newOpId(), [96001]);
    await flusher.flush();
    await markSetUnderstood(db, newOpId(), [68001]);
    await flusher.flush();

    expect(server.rounds, hasLength(1));
    expect(
      await queued(db),
      1,
      reason: 'the second write rides the next flush, once the floor is past',
    );
  });

  // The hazard the flush was always going to have: two of them over one
  // outbox. syncNow's "one attempt per op" set lives inside a single call, so
  // nothing but this guard stops a write being sent twice in one round and
  // spending two of its ten attempts on one answer.
  test('a return to the foreground during a flush sends the queue twice',
      () async {
    await markSetUnderstood(db, newOpId(), [96001, 96002]);
    final server = ServerInTheRoom();
    final flusher = Flusher(db, server, gap: Duration.zero);

    await Future.wait([flusher.flush(), flusher.flush()]);

    expect(server.rounds, hasLength(1));
    expect(await queued(db), 0);
  });
}
