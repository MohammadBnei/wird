import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wird/features/settings/settings_screen.dart';

import '../../corpus.dart';
import '../../fonts.dart';
import '../../wird.dart';

/// The senses route, answered on this side of the socket.
///
/// A widget test runs on a fake clock and a real socket never answers inside
/// one — the same seam `voice_model_test.dart` takes for the recogniser's host.
/// What is under test is what the panel does with an answer, so the answers are
/// dictated rather than computed.
class ServedSenses implements HttpClientAdapter {
  ServedSenses(this.pack);

  Map<String, dynamic> pack;

  /// Every request that arrived, reachable or not: [heads] and [gets] count
  /// only the ones this host answered.
  var asked = 0;

  var heads = 0;
  var gets = 0;

  /// False is the whole class of failures a reader can do nothing about: no
  /// route to the host, a timeout, a 500.
  var reachable = true;

  Dio get client =>
      Dio(BaseOptions(baseUrl: 'https://senses.test'))
        ..httpClientAdapter = this;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    asked++;
    if (!reachable) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'no route to the server',
      );
    }
    final headers = {
      Headers.contentTypeHeader: [Headers.jsonContentType],
      'etag': ['"${pack['version']}"'],
    };
    // A HEAD is how the check asks without paying for the body, so it answers
    // with headers and nothing else — which is what the real route does.
    if (options.method == 'HEAD') {
      heads++;
      return ResponseBody.fromString('', 200, headers: headers);
    }
    gets++;
    return ResponseBody.fromString(jsonEncode(pack), 200, headers: headers);
  }
}

/// A pack naming roots this corpus really records, so the install is not
/// refused for naming none of them.
Map<String, dynamic> pack(String version, {String root = 'أبد'}) => {
  'version': version,
  'source': 'Wird',
  'basis': 'A draft, written by a machine and read by no person.',
  'senses': [
    {'root': root, 'en': 'the root turns on time without end'},
  ],
};

Future<int> servedSenses(Database db) async =>
    (await db.rawQuery(
          'SELECT COUNT(*) AS n FROM root_notes WHERE word_id IS NULL',
        )).single['n']!
        as int;

void main() {
  late Database db;

  setUpAll(loadBundledFonts);
  setUp(() async {
    db = await testCorpus();
  });

  // This file installs packs, and `root_notes` is a SHIPPED table that
  // `testCorpus` does not empty between tests — so a committed rewrite here
  // outlives the test that made it. Every test below wants rewritten senses,
  // which is why they live together and why nothing here asserts on the 523 the
  // bundle carries.
  Future<ServedSenses> openThePanel(
    WidgetTester tester, {
    bool reachable = true,
  }) async {
    final host = ServedSenses(pack('1-abc'))..reachable = reachable;
    await pumpPhone(
      tester,
      await wirdAround(
        db,
        Scaffold(
          body: SensePanel(db: db, over: host.client),
        ),
      ),
    );
    return host;
  }

  // The gate `the_app_calls_what_it_ships` is satisfied by *a* caller, and this
  // is the one a reader presses. `Flusher` is the one that saves the reader who
  // never comes here.
  testWidgets('a pack on offer is never offered to the reader', (tester) async {
    final host = await openThePanel(tester);

    expect(host.heads, 1, reason: 'the check must be a HEAD, not a download');
    expect(host.gets, 0, reason: 'nothing moves until the reader presses');
    expect(find.byKey(SensePanel.download), findsOneWidget);
    expect(
      find.textContaining('nothing downloads until you press'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(SensePanel.download));
    await tester.pumpAndSettle();

    expect(host.gets, 1);
    expect(
      await servedSenses(db),
      1,
      reason: 'the pack replaces what was there',
    );
    expect(find.byKey(SensePanel.download), findsNothing);
    expect(
      find.textContaining('read by no person'),
      findsOneWidget,
      reason: 'the one screen that talks about the whole pack says what it is',
    );
  });

  // A phone that already holds the offered version is told so, and is not shown
  // a button whose only effect is to download what it has.
  testWidgets('a phone holding the served pack is offered it again', (
    tester,
  ) async {
    await db.insert('sense_pack', {
      'id': 1,
      'version': '1-abc',
      'fetched_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    final host = await openThePanel(tester);

    expect(host.heads, 1);
    expect(host.gets, 0);
    expect(find.byKey(SensePanel.download), findsNothing);
    expect(
      find.textContaining('has the senses the server is serving'),
      findsOneWidget,
    );
  });

  // The dead end the panel would otherwise be. A check that could not reach the
  // server left no button at all, so the only retry was leaving Settings and
  // coming back — which nothing on the screen said.
  testWidgets('a reader whose check failed has no way to ask again', (
    tester,
  ) async {
    final host = await openThePanel(tester, reachable: false);

    expect(find.byKey(SensePanel.download), findsNothing);
    expect(find.byKey(SensePanel.askAgain), findsOneWidget);
    expect(find.textContaining('did not answer'), findsOneWidget);
    expect(
      find.textContaining('still here'),
      findsOneWidget,
      reason: 'a reader who cannot reach the server has lost nothing',
    );

    host.reachable = true;
    await tester.tap(find.byKey(SensePanel.askAgain));
    await tester.pumpAndSettle();

    expect(host.asked, 2, reason: 'the press has to reach the host again');
    expect(host.heads, 1, reason: 'and the second ask is still only a HEAD');
    expect(find.byKey(SensePanel.download), findsOneWidget);
  });
}
