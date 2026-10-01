import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wird/app.dart';
import 'package:wird/data/audio.dart';
import 'package:wird/features/root/root_screen.dart';
import 'package:wird/features/study/study_screen.dart';
import 'package:wird/nav.dart';

import '../../corpus.dart';
import '../../fonts.dart';
import '../../offline.dart';
import '../../wird.dart';

/// The two ends of screen 1a fold away, so a reader who wants the Qur'an gets
/// the screen. What must survive each fold is what these tests are for: a
/// folded header still answers "where am I", a folded root panel still names
/// the root and still carries the act that moves the reader on, and neither
/// fold is forgotten the moment the screen is rebuilt.
void main() {
  late Database db;
  late AudioCache audio;

  setUpAll(loadBundledFonts);
  setUp(() async {
    db = await testCorpus();
    audio = await emptyCache();
  });

  Future<void> openStudy(WidgetTester tester, {int? target}) async => pumpPhone(
    tester,
    await wirdAround(
      db,
      StudyScreen(db: db, target: target),
      route: Routes.study,
      cache: audio,
    ),
  );

  testWidgets('screen 1a still opens on the five-row masthead the reader '
      'could not see past', (tester) async {
    await openStudy(tester);

    expect(find.textContaining('REVELATION'), findsNothing);
    expect(find.text('No aya marked understood yet'), findsNothing);
  });

  testWidgets('the reader\'s bar stops saying where in the Qur\'an the reader '
      'is', (tester) async {
    await openStudy(tester);

    expect(find.textContaining("Al-'Alaq"), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('position'))).data,
      startsWith('96:1 · word 1/'),
    );
  });

  testWidgets('the reader\'s bar drops the prayer, leaving no way into the act '
      'the reading is for', (tester) async {
    await openStudy(tester);

    expect(
      tester.widget<TextButton>(find.byKey(const Key('pray'))).onPressed,
      isNotNull,
    );
  });

  testWidgets('a display setting changed after a fold writes the fold away', (
    tester,
  ) async {
    final prefs = await Prefs.read(db);
    expect(prefs.headerOpen, isFalse, reason: 'the header arrives folded');
    expect(prefs.rootOpen, isTrue, reason: 'the root panel arrives open');

    await prefs.setHeaderOpen(true);
    await prefs.setDisplay(3);

    expect((await Prefs.read(db)).headerOpen, isTrue);
  });

  testWidgets(
    'the root letters in the sheet stop reaching the root screen, which '
    'nothing else in the reader opens',
    (tester) async {
      await openStudy(tester);

      await tester.tap(find.byKey(const ValueKey('open-root')));
      await tester.pumpAndSettle();

      expect(find.byType(RootScreen), findsOneWidget);
    },
  );
}
