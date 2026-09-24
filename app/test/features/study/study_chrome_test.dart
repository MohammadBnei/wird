import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wird/app.dart';
import 'package:wird/data/audio.dart';
import 'package:wird/features/root/root_screen.dart';
import 'package:wird/features/study/study_screen.dart';

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

  Future<void> openStudy(WidgetTester tester, {int? target}) => pumpPhone(
    tester,
    await wirdAround(db, StudyScreen(db: db, target: target), cache: audio),
  );

  Future<void> tapHeader(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('toggle header')));
    await tester.pumpAndSettle();
  }

  Future<void> tapRootPanel(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('toggle root panel')));
    await tester.pumpAndSettle();
  }

  testWidgets('screen 1a still opens on the five-row masthead the reader '
      'could not see past', (tester) async {
    await openStudy(tester);

    expect(find.textContaining('REVELATION'), findsNothing);
    expect(find.text('No aya marked understood yet'), findsNothing);
  });

  testWidgets('the folded header stops saying where in the Qur\'an the reader '
      'is', (tester) async {
    await openStudy(tester);

    expect(find.textContaining("Al-'Alaq 1–5"), findsOneWidget);
    expect(find.text('العلق'), findsOneWidget);
  });

  testWidgets('the folded header takes the prayer with it, leaving no way '
      'into the act the reading is for', (tester) async {
    await openStudy(tester);

    expect(find.text('Pray this set'), findsOneWidget);
  });

  testWidgets('a folded header hides that the reader is visiting an aya, '
      'leaving nothing to lead them back to the walk', (tester) async {
    await openStudy(tester, target: 2255);

    expect(find.textContaining('VISITING'), findsOneWidget);
    expect(find.text('Back to the walk'), findsOneWidget);
  });

  testWidgets('the header the reader unfolded folds itself again the moment '
      'they mark the set', (tester) async {
    await openStudy(tester);
    await tapHeader(tester);
    expect(find.textContaining('REVELATION'), findsOneWidget);

    await tester.tap(find.text('Mark set understood'));
    await tester.pumpAndSettle();

    expect(find.textContaining('REVELATION'), findsOneWidget);
  });

  testWidgets('the fold the reader chose is undone by walking to another '
      'screen and back', (tester) async {
    await pumpPhone(tester, await wholeApp(db, cache: audio));
    await goTo(tester, 'The set');
    await tapHeader(tester);
    expect(find.textContaining('REVELATION'), findsOneWidget);

    await goTo(tester, 'Your passage');
    await goTo(tester, 'The set');

    expect(find.textContaining('REVELATION'), findsOneWidget);
  });

  testWidgets('the fold the reader chose is undone by closing the app',
      (tester) async {
    await openStudy(tester);
    await tapHeader(tester);

    // What a cold start reads, not what the screen is still holding.
    expect((await Prefs.read(db)).headerOpen, isTrue);
  });

  testWidgets('a display setting changed after a fold writes the fold away',
      (tester) async {
    final prefs = await Prefs.read(db);
    expect(prefs.headerOpen, isFalse, reason: 'the header arrives folded');
    expect(prefs.rootOpen, isTrue, reason: 'the root panel arrives open');

    await prefs.setHeaderOpen(true);
    await prefs.setDisplay(3);

    expect((await Prefs.read(db)).headerOpen, isTrue);
  });

  testWidgets('folding the root panel takes "Mark set understood" with it, '
      'and with it the way through the Qur\'an', (tester) async {
    await openStudy(tester);
    await tapRootPanel(tester);

    await tester.tap(find.text('Mark set understood'));
    await tester.pumpAndSettle();

    expect((await db.query('ayah_understood')).length, 5);
  });

  testWidgets('the folded root panel stops saying which root is open',
      (tester) async {
    await openStudy(tester);
    await tapRootPanel(tester);

    expect(find.text('ق ر أ'), findsOneWidget);
    expect(
      find.text('A kin opens the aya it is first met in.'),
      findsNothing,
      reason: 'the gloss and the kin are what the fold sheds',
    );
  });

  testWidgets('tapping the folded root panel leaves screen 1a for the root '
      'screen rather than unfolding the panel', (tester) async {
    await openStudy(tester);
    await tapRootPanel(tester);

    await tapRootPanel(tester);

    expect(find.byType(RootScreen), findsNothing);
    expect(find.text('A kin opens the aya it is first met in.'), findsOneWidget);
  });

  testWidgets('the root line stops reaching the root screen now that the fold '
      'handle sits beside it', (tester) async {
    await openStudy(tester);

    await tester.tap(find.byKey(const ValueKey('open-root')));
    await tester.pumpAndSettle();

    expect(find.byType(RootScreen), findsOneWidget);
  });
}
