import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wird/data/audio.dart';
import 'package:wird/features/about/about_screen.dart';
import 'package:wird/features/study/study_screen.dart';
import 'package:wird/theme/nocturne.dart';

import '../../corpus.dart';
import '../../fonts.dart';
import '../../offline.dart';

/// Substrings a source must put on screen for the grant it is used under to
/// hold. Read against the screen, not against the constant it renders from,
/// so deleting the entry fails the test rather than moving it.
const _corpus = 'Quranic Arabic Corpus';
const _corpusLink = 'corpus.quran.com';
const _corpusNotice = 'Copyright (C) 2011 Kais Dukes';

void main() {
  late Database db;
  late AudioCache audio;

  setUpAll(loadBundledFonts);
  // Copying the corpus and making the cache directory is real file work, which
  // never completes inside the fake-async zone a widget test body runs in.
  setUp(() async {
    db = await testCorpus();
    audio = await emptyCache();
  });

  Future<void> phone(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: nocturneTheme(), home: home));
    await tester.pumpAndSettle();
  }

  testWidgets('the app uses the Quranic Arabic Corpus without naming it, '
      'linking it, or carrying its copyright notice — the three conditions '
      'the corpus grants its use on', (tester) async {
    await phone(tester, const AboutScreen());

    expect(find.text(_corpus), findsOneWidget);
    expect(find.text(_corpusLink), findsOneWidget);
    expect(find.textContaining(_corpusNotice), findsOneWidget);
  });

  testWidgets('the corpus link is printed as dead text, so a reader cannot '
      'reach corpus.quran.com to see what has changed', (tester) async {
    await phone(tester, const AboutScreen());

    await tester.tap(find.text(_corpusLink));
    await tester.pumpAndSettle();

    expect(find.textContaining('https://corpus.quran.com'), findsOneWidget);
  });

  testWidgets('Tanzil, the fonts and the uncleared recitation go unattributed '
      'while the corpus is credited', (tester) async {
    await phone(tester, const AboutScreen());

    for (final source in sources) {
      await tester.scrollUntilVisible(find.text(source.name), 200);
      expect(
        find.text(source.name),
        findsOneWidget,
        reason: '${source.name} provides ${source.provides} and is used under '
            '${source.licence}',
      );
      expect(find.text(source.licence), findsWidgets);
    }
  });

  testWidgets('the attribution lives only in the repository, so nobody using '
      'the app ever sees it', (tester) async {
    await phone(tester, StudyScreen(db: db, audioCache: audio));
    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sources and licences'));
    await tester.pumpAndSettle();

    expect(find.text(_corpus), findsOneWidget);
    expect(find.text(_corpusLink), findsOneWidget);
  });
}
