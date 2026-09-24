import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:wird/data/db.dart';
import 'package:wird/data/root_repo.dart';
import 'package:wird/features/deepdive/constellation.dart';
import 'package:wird/features/deepdive/deep_dive_screen.dart';
import 'package:wird/features/root/family.dart';
import 'package:wird/features/root/root_dial.dart';
import 'package:wird/features/root/root_screen.dart';

import '../../corpus.dart';
import '../../fonts.dart';
import '../../wird.dart';

/// ʿ-q-l, five derivatives: the family the design's own ring is drawn around,
/// and 2:44, which reads one of them.
const onTheDial = 'عقل';
const ayaOfReason = 2044;

/// ṣ-b-r as 103:3 spells it — thirty-eight forms, of which the design's
/// drawing has room for five.
const ayaOfPatience = 103003;
const patience = 'صبر';

/// The iPad Pro 11-inch in landscape, the real device nearest the design's
/// own frame, and the phone everything is judged on.
const tablet = Size(1194, 834);
const phone = Size(402, 874);

void main() {
  late Database db;

  /// The aya the screen under test answered the screen beneath it with.
  int? answered;

  setUpAll(loadBundledFonts);
  setUp(() async {
    db = await testCorpus();
    answered = null;
  });

  /// The screen under test, pushed the way the reading screen pushes it. A
  /// family is only ever drawn above screen 1a, so a reference answers by
  /// popping its aya down to it rather than by stacking a second reader on
  /// top — ADR-0003.
  Future<void> open(WidgetTester tester, Widget screen, {Size at = phone}) async {
    tester.view.physicalSize = at;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(await wirdAround(db, const SizedBox.shrink()));
    await tester.pumpAndSettle();
    unawaited(
      tester
          .state<NavigatorState>(find.byType(Navigator).first)
          .push<int>(MaterialPageRoute(builder: (_) => screen))
          .then((aya) => answered = aya),
    );
    await tester.pumpAndSettle();
  }

  /// That the reader is on their way to the aya a reference named: the screen
  /// carrying the reference closed, and handed the aya down.
  void expectAnswered(WidgetTester tester, int ayahId) {
    expect(answered, ayahId, reason: ayahRef(ayahId));
  }

  Finder refTo(int ayahId) => find.byWidgetPredicate(
    (widget) => widget is AyaRef && widget.ayahId == ayahId,
  );

  testWidgets('the reference on a kin row is a caption: a reader looking at a '
      "root's family cannot reach the aya any of it is read in", (tester) async {
    final reading = (await rootReading(db, onTheDial))!;
    final kin = reading.derivatives[2];
    // A tall phone, so the spine is laid out rather than below the fold.
    await open(
      tester,
      RootScreen(db: db, letters: onTheDial),
      at: const Size(402, 2600),
    );

    await tester.tap(refTo(kin.ayahId).last);
    await tester.pumpAndSettle();

    expectAnswered(tester, kin.ayahId);
    expect(find.byType(RootScreen), findsNothing);
  });

  testWidgets('a constellation node is a drawing of a word: tapping the form '
      'the reader wants leads nowhere', (tester) async {
    final reading = (await rootReading(db, patience))!;
    await open(
      tester,
      DeepDiveScreen(db: db, ayahId: ayaOfPatience, letters: patience),
      at: tablet,
    );

    final star = tester
        .widget<Constellation>(find.byType(Constellation))
        .stars
        .first;
    final box = tester.getRect(find.byType(Constellation));
    final fit = constellationFit(box.size);
    await tester.tapAt(box.topLeft + fit.origin + star.at * fit.scale);
    await tester.pumpAndSettle();

    expect(reading.derivatives, contains(star.derivative));
    expectAnswered(tester, star.derivative.ayahId);
    expect(find.byType(DeepDiveScreen), findsNothing);
  });

  testWidgets('the phone is handed the tablet drawing shrunk: five of the '
      "root's thirty-eight forms, at a size no caption survives", (
    tester,
  ) async {
    final reading = (await rootReading(db, patience))!;
    expect(reading.derivatives, hasLength(greaterThan(5)));

    await open(
      tester,
      DeepDiveScreen(db: db, ayahId: ayaOfPatience, letters: patience),
      at: phone,
    );

    expect(find.byType(Constellation), findsNothing);
    final rows = tester.widget<KinSpine>(find.byType(KinSpine));
    expect(rows.derivatives, reading.derivatives);
  });

  testWidgets('the form the aya in front of the reader spells is not the one '
      'its family opens on', (tester) async {
    final reading = (await rootReading(db, patience))!;
    final aya = (await ayaReading(db, ayaOfPatience, patience))!;
    final here = reading.spelled(
      [for (final word in aya.words) if (word.lit) word.text].last,
    );

    await open(
      tester,
      DeepDiveScreen(db: db, ayahId: ayaOfPatience, letters: patience),
      at: phone,
    );

    expect(tester.widget<KinSpine>(find.byType(KinSpine)).here, here);
    expect(find.text('THIS AYA'), findsOneWidget);
  });

  testWidgets('a phone reading a family of five is given the rows without the '
      'ring, so nothing says which form is being read', (tester) async {
    await open(
      tester,
      DeepDiveScreen(db: db, ayahId: ayaOfReason, letters: onTheDial),
      at: phone,
    );

    final dial = tester.widget<RootDial>(find.byType(RootDial));
    final reading = (await rootReading(db, onTheDial))!;
    expect(
      reading.derivatives[dial.index],
      reading.spelled(
        [
          for (final word
              in (await ayaReading(db, ayaOfReason, onTheDial))!.words)
            if (word.lit) word.text,
        ].last,
      ),
    );
  });

  testWidgets('every row of the spine spends the same sentence on what two '
      'words say, so the form and the count are buried in it', (tester) async {
    await open(tester, RootScreen(db: db, letters: patience));
    final spine = (await rootReading(db, patience))!.derivatives;

    // Thirty of ṣ-b-r's thirty-eight forms are Form I, so the sentence that
    // used to carry the form and the count was the same one thirty times over.
    expect(find.textContaining('Occurs'), findsNothing);
    expect(find.textContaining('in the Qur’an.'), findsNothing);

    final first = spine.first;
    expect(
      derivativeWeight(first),
      'Form ${first.form} · ${first.occurrences}×',
      reason: 'the two facts that differ are the whole line',
    );
    expect(find.text(derivativeWeight(first)), findsWidgets);
  });

  test('the panel under the aya and the drawing beside it are built by '
      'queries of their own, so one root reads three ways', () async {
    for (final letters in ['قرأ', onTheDial, 'عصر', patience]) {
      final family = (await rootReading(db, letters))!;
      final panel = (await rootDetail(db, letters))!.kin;
      final drawn = [
        for (final star in constellation(family, null)) star.derivative,
      ];

      expect(panel, family.derivatives.take(panel.length), reason: letters);
      expect(
        drawn.every(family.derivatives.contains),
        isTrue,
        reason: letters,
      );
    }
  });
}
