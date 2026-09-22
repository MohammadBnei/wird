import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wird/gallery.dart';
import 'package:wird/theme/nocturne.dart';

import 'fonts.dart';

void main() {
  setUpAll(loadBundledFonts);

  testWidgets('a Nocturne widget drifts from the design system in a variant '
      'or state that no screen test covers', (tester) async {
    // Focus highlights are hidden under the touch strategy the test binding
    // starts in, and the focus ring is one of the states on show here.
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(theme: nocturneTheme(), home: const NocturneGallery()),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(NocturneGallery),
      matchesGoldenFile('goldens/gallery.png'),
    );
  });
}
