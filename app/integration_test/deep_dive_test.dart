import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'journey.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  journey(
    'opens a word’s constellation on a tablet',
    body: (tester) async {
      // The iPad Pro 11-inch (M4) in landscape, which is the real device
      // nearest the design's 1180×794 frame. It is pinned here rather than
      // taken from the target, so the three-pane reading is what this journey
      // walks wherever it runs.
      tester.view.physicalSize = const Size(1194, 834);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await launchFresh(tester);
      final corpus = await openCorpusBeside();

      // The root panel on screen 1a opens on the first word of the set that
      // carries a root, and "Constellation" opens that root.
      String? root;
      for (final id in wordsOnScreen(tester).toList()..sort()) {
        root = await rootDisplayOf(corpus, id);
        if (root != null) break;
      }
      expect(
        root,
        isNotNull,
        reason: 'no word of the first set carries a root to open',
      );

      await tester.tap(find.text('Constellation'));
      await tester.pumpAndSettle();

      expect(
        find.text('ROOT CONSTELLATION'),
        findsOneWidget,
        reason:
            'a tablet-sized window opened the phone reading instead of the '
            'three panes the design draws for it',
      );
      expect(
        find.text(root!),
        findsOneWidget,
        reason:
            'the constellation opened on a root other than the one the '
            'reader was looking at',
      );
      expectNoSpinnerAndNoApology(tester, 'on the deep dive');
    },
  );
}
