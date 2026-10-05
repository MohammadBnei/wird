// Walks the screens the store listings show and asks scripts/store-screens.sh
// to capture each one. Not a journey: no `_test` suffix, so the gate never
// runs it. Run it through the script, which owns the simulator and the
// capture: this side only reaches each screen and holds still.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wird/features/study/word_row.dart';

import 'journey.dart';

/// Prints the marker the script captures on, then holds the screen still
/// long enough for `simctl io screenshot` to land.
Future<void> shot(WidgetTester tester, String name) async {
  await tester.pumpAndSettle();
  // ignore: avoid_print
  print('WIRD-SHOT $name');
  await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 4)));
  await tester.pump();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // A simulator only runs debug builds; the listing must not say so.
  WidgetsApp.debugAllowBannerOverride = false;

  testWidgets('store screens', (tester) async {
    await launchFresh(tester);
    await shot(tester, '02-the-set');

    final corpus = await openCorpusBeside();
    final word = await aWordToTap(tester, corpus);
    await tester.tap(find.byKey(WordKey(word.id)));
    await tester.pumpAndSettle();
    await shot(tester, '03-the-root');

    await tester.tap(find.byKey(const Key('more row')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('deep dive')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('deep dive')));
    await tester.pumpAndSettle();
    await shot(tester, '04-deep-dive');

    // The deep dive is pushed over the set and has no drawer of its own.
    tester
        .state<NavigatorState>(find.byType(Navigator).first)
        .popUntil((route) => route.isFirst);
    await tester.pumpAndSettle();
    await goThroughTheDrawer(tester, 'Home');
    await shot(tester, '01-home');

    await goThroughTheDrawer(tester, 'The set');
    await waitFor(tester, () => wordsOnScreen(tester).isNotEmpty, 'the set');
    // Pray stays disabled until a word is open: the prayer is about its aya.
    // Tapping an open word would close it, so only open one if none is.
    bool canPray() =>
        tester.widget<TextButton>(find.byKey(const Key('pray'))).onPressed !=
        null;
    for (var i = 0; i < 10 && !canPray(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 500)),
      );
      await tester.pump();
    }
    if (!canPray()) await tester.tap(find.byKey(WordKey(word.id)));
    await waitFor(tester, canPray, 'Pray, once a word is open');
    await tester.tap(find.byKey(const Key('pray')));
    await waitFor(
      tester,
      () => find.byKey(const Key('begin')).evaluate().isNotEmpty,
      "the prayer's preparation",
    );
    await shot(tester, '05-prepare');

    await tester.tap(find.byKey(const Key('begin')));
    await tester.pumpAndSettle();
    await shot(tester, '06-prayer');
  });
}
