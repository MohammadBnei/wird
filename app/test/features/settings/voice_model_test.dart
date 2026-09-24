import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wird/data/speech.dart';
import 'package:wird/features/settings/settings_screen.dart';

import '../../corpus.dart';
import '../../fonts.dart';
import '../../wird.dart';

/// The host the model is fetched from, answered on this side of the socket:
/// it has the route and serves nothing, which is what a reader meets when the
/// recogniser has not been published yet.
class NothingServed implements HttpClientAdapter {
  var asked = 0;

  Dio get client => Dio()..httpClientAdapter = this;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    asked++;
    return ResponseBody.fromString('no such object', 404);
  }
}

void main() {
  late Database db;
  late NothingServed host;

  setUpAll(loadBundledFonts);
  setUp(() async {
    db = await testCorpus();
    host = NothingServed();
  });

  /// The panel with the model stood in for: a directory no download ever
  /// reached, and a host that will not serve one.
  Future<void> openThePanel(WidgetTester tester) async {
    await pumpPhone(
      tester,
      await wirdAround(
        db,
        Scaffold(
          body: VoiceModelPanel(
            model: VoiceModel(
              Directory('${Directory.systemTemp.path}/wird-voice-unwritten'),
              origin: 'https://models.test/voice/',
              http: host.client,
            ),
          ),
        ),
      ),
    );
  }

  // The panel dropped what fetch answered, so a host that will never serve
  // the model redrew the same button under the same never-downloaded caption.
  // The reader, told nothing had happened, pressed Download again. And again.
  testWidgets('a host that will not serve the recogniser leaves the panel '
      'saying nothing has been tried', (tester) async {
    await openThePanel(tester);

    await tester.tap(find.byKey(VoiceModelPanel.download));
    await tester.pumpAndSettle();

    expect(host.asked, 1, reason: 'the press has to reach the host');
    expect(find.textContaining('not serving the recogniser'), findsOneWidget);
    expect(
      find.textContaining("A Qur'an recogniser that runs on the phone"),
      findsNothing,
      reason: 'the caption of a phone that was never asked is now a lie',
    );
  });
}
