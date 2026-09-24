import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wird/data/mic.dart';
import 'package:wird/features/settings/settings_screen.dart';
import 'package:wird/widgets/nocturne_button.dart';

import '../../corpus.dart';
import '../../fonts.dart';
import '../../wird.dart';

void main() {
  late Database db;

  setUpAll(loadBundledFonts);
  setUp(() async => db = await testCorpus());

  Future<void> settings(WidgetTester tester) async {
    await pumpPhone(tester, await wirdAround(db, const SettingsScreen()));
  }

  Finder allow() => find.widgetWithText(NocturneButton, 'Allow microphone');

  bool enabled(WidgetTester tester, Finder f) =>
      tester.widget<NocturneButton>(f).onPressed != null;

  // `unavailable` is what askForMic writes when the request THREW — a plugin
  // not yet registered, a recorder busy elsewhere, a build that could not ask
  // at all. Treating it as a fact about the hardware made one bad moment
  // permanent: the button went dead and no reader could ever ask again.
  //
  // This is not hypothetical. The build before voice-follow answered
  // `unavailable` unconditionally, by design, and `mic_consent` outlives an
  // `adb install -r` — so upgrading carried that verdict forward and the new
  // request never ran once. A reader on a phone with a working microphone was
  // told the device had none.
  testWidgets('a microphone that could not be reached once can never be '
      'asked for again, on a phone that has one', (tester) async {
    await setMicPermission(db, MicPermission.unavailable);

    await settings(tester);

    expect(allow(), findsOneWidget);
    expect(
      enabled(tester, allow()),
      isTrue,
      reason: 'the only way back from a caught exception is to ask again',
    );
  });

  testWidgets('a reader who refused the microphone cannot change their mind',
      (tester) async {
    await setMicPermission(db, MicPermission.denied);

    await settings(tester);

    expect(enabled(tester, allow()), isTrue);
  });

  // The one answer that is a fact rather than a failure. Asking again after a
  // yes raises the system prompt for nothing, so the button goes entirely.
  testWidgets('the button still offers to ask after the reader has already '
      'said yes', (tester) async {
    await setMicPermission(db, MicPermission.granted);

    await settings(tester);

    expect(allow(), findsNothing);
  });

  testWidgets('a device that could not be reached is described as one that '
      'has no microphone, which is a different thing', (tester) async {
    await setMicPermission(db, MicPermission.unavailable);

    await settings(tester);

    expect(find.textContaining('could not be reached'), findsOneWidget);
    expect(find.textContaining('no microphone to offer'), findsNothing);
  });
}
