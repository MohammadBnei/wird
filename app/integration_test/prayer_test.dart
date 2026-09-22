import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite/sqflite.dart';

import 'journey.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Database corpus;

  journey(
    'prays two sets back to back',
    body: (tester) async {
      await launchFresh(tester);
      corpus = await openCorpusBeside();

      final first = ayasOnScreen(tester);
      expect(
        first,
        contains(96001),
        reason: 'the revelation order begins at Al-ʿAlaq 96:1, and a reader '
            'starting Wird for the first time was handed something else',
      );

      await tester.tap(markSetUnderstood(tester));
      await waitFor(
        tester,
        () => ayasOnScreen(tester).intersection(first).isEmpty,
        'the second set: the set that was understood was the last one the '
            'reader ever got, which is the offline promise dying after '
            'exactly one set',
      );

      final second = ayasOnScreen(tester);
      expect(second, isNotEmpty);

      // Reading the second set, not merely receiving it: its words have to
      // carry roots and open the panel the way the first set's did.
      final word = await aWordToTap(tester, corpus);
      await tester.tap(find.byKey(ValueKey(word.id)));
      await waitFor(
        tester,
        () => find.text(word.display).evaluate().isNotEmpty,
        'the root of a word in the second set',
      );

      await tester.tap(markSetUnderstood(tester));
      await waitFor(
        tester,
        () => ayasOnScreen(tester).intersection(first.union(second)).isEmpty,
        'the third set: the walk stalls and starts re-serving ayas already '
            'marked understood',
      );
    },
  );

  journey(
    'prays with the network off',
    body: (tester) async {
      // Warm what there is to warm: the first launch is the one that copies
      // the corpus out of the bundle, and it is the only part of the loop
      // that could ever have wanted a socket.
      await launchFresh(tester);
      corpus = await openCorpusBeside();
      final warm = ayasOnScreen(tester);

      await withNetworkDenied(() async {
        await relaunch(tester);
        expectNoSpinnerAndNoApology(tester, 'when the app opens with no signal');

        final first = ayasOnScreen(tester);
        expect(
          first,
          equals(warm),
          reason: 'with the radio off the reader is handed a different set '
              'than the one the app was showing a moment earlier',
        );

        final word = await aWordToTap(tester, corpus);
        await tester.tap(find.byKey(ValueKey(word.id)));
        await waitFor(
          tester,
          () => find.text(word.display).evaluate().isNotEmpty,
          'the root panel, which needs the network to answer and so is empty '
              'in the room the prayer happens in',
        );
        expectNoSpinnerAndNoApology(tester, 'after opening a root offline');

        await tester.tap(markSetUnderstood(tester));
        await waitFor(
          tester,
          () => ayasOnScreen(tester).intersection(first).isEmpty,
          'the next set, which never arrives with the radio off — the whole '
              'reason sets are generated on the device',
        );
        expect(ayasOnScreen(tester), isNotEmpty);
        expectNoSpinnerAndNoApology(tester, 'on the second set, offline');
      });
    },
  );

  journey(
    'taps a word and reaches its root',
    body: (tester) async {
      await launchFresh(tester);
      corpus = await openCorpusBeside();

      final ayas = find.descendant(
        of: find.byType(SingleChildScrollView),
        matching: find.byType(Scrollable),
      );
      final position = tester.state<ScrollableState>(ayas).position;
      if (position.maxScrollExtent > 0) {
        await tester.drag(ayas, const Offset(0, -80));
        await tester.pumpAndSettle();
      }
      final scrolledTo = position.pixels;

      // Chosen after the scroll: the reader taps what is under their thumb
      // now, not what was there before they moved the aya.
      final target = await aWordToTap(tester, corpus);
      final tile = find.byKey(ValueKey(target.id));
      final before = tester.element(tile);
      final neighbours = wordsOnScreen(tester);

      await tester.tap(tile);
      await waitFor(
        tester,
        () => find.text(target.display).evaluate().isNotEmpty,
        'the root of the word that was tapped: an underlined word does not '
            'reach its root',
      );

      expect(
        wordsOnScreen(tester),
        equals(neighbours),
        reason: 'the aya blanked when the root panel swapped',
      );
      expect(
        tester.element(tile),
        same(before),
        reason: 'the aya was rebuilt from scratch behind the root panel, which '
            'is the flash the reader sees mid-tap',
      );
      expect(
        position.pixels,
        equals(scrolledTo),
        reason: 'the aya jumped back to the top when the root opened, losing '
            'the place the reader had scrolled to',
      );
    },
  );
}
