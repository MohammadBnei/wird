import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wird/data/audio.dart';
import 'package:wird/features/about/about_screen.dart';
import 'package:wird/features/study/study_screen.dart';
import 'package:wird/nav.dart';
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
    await tester.pumpWidget(
      MaterialApp(
        theme: nocturneTheme(),
        onGenerateRoute: (settings) => screenRoute(settings, db),
        home: home,
      ),
    );
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

  testWidgets('Tanzil, the fonts and the recitation go unattributed '
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

  testWidgets('the word timings ship with no credit to the person who made '
      'them, which is the only permission Wird has to bundle them',
      (tester) async {
    // Iterating `sources` cannot catch an absent entry, and that is how this
    // screen once passed a green gate while crediting nobody for the timings.
    // CC BY 4.0 grants the bundle on four conditions, so name all four.
    await phone(tester, const AboutScreen());

    // Scroll to the notice rather than the name: a ListView does not build
    // what is off-screen, so reaching the card is not the same as showing
    // everything on it.
    await tester.scrollUntilVisible(
      find.text('Copyright (c) 2016 Collin Fair'),
      200,
    );

    expect(find.text('quran-align'), findsOneWidget);
    expect(find.text('Copyright (c) 2016 Collin Fair'), findsOneWidget);
    expect(
      find.text('Creative Commons Attribution 4.0 International'),
      findsWidgets,
    );

    final timings = sources.firstWhere((s) => s.name == 'quran-align');
    expect(timings.url, 'https://creativecommons.org/licenses/by/4.0/');
    expect(timings.terms, contains('zero-based'),
        reason: 'CC BY 4.0 also requires that changes be indicated, and the '
            'published timings were reindexed for this schema');
  });

  testWidgets('the screen still tells a reader the recitation cannot be '
      'played, long after it could', (tester) async {
    await phone(tester, const AboutScreen());

    for (final stale in const ['not cleared', 'Neither ships with this app']) {
      expect(find.textContaining(stale), findsNothing, reason: stale);
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
