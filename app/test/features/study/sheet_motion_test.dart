import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wird/features/study/study_screen.dart';
import 'package:wird/nav.dart';

import '../../corpus.dart';
import '../../fonts.dart';
import '../../wird.dart';

void main() {
  late Database db;

  setUpAll(loadBundledFonts);
  setUp(() async => db = await testCorpus());

  Future<void> openStudy(WidgetTester tester) async => pumpPhone(
    tester,
    await wirdAround(db, StudyScreen(db: db, target: 2001), route: Routes.study),
  );

  double surahHeight(WidgetTester tester) =>
      tester.getSize(find.byType(CustomScrollView)).height;

  Finder sheetHandle() => find.byKey(const Key('sheet handle'));

  testWidgets('folding the sheet snaps the sūra to the whole screen, and the '
      'root vanishes before the sheet has moved', (tester) async {
    await openStudy(tester);
    final open = surahHeight(tester);

    await tester.drag(sheetHandle(), const Offset(0, 300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    final moving = surahHeight(tester);
    expect(find.byKey(const Key('next word')), findsOneWidget);

    await tester.pumpAndSettle();
    final folded = surahHeight(tester);
    expect(moving, greaterThan(open));
    expect(moving, lessThan(folded));
    expect(find.byKey(const Key('next word')), findsNothing);
  });

  testWidgets('expanding the sheet swaps the sūra for the open aya in one '
      'frame', (tester) async {
    await openStudy(tester);

    await tester.tap(sheetHandle());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    final aya = tester.widget<Opacity>(
      find
          .ancestor(
            of: find.byKey(const Key('open aya')),
            matching: find.byType(Opacity),
          )
          .first,
    );
    expect(aya.opacity, inExclusiveRange(0, 1));
    expect(find.byType(CustomScrollView), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('closing the expanded sheet puts the reader back where the sūra '
      'was opened, not where they had scrolled to', (tester) async {
    await openStudy(tester);
    final list = find.descendant(
      of: find.byType(CustomScrollView),
      matching: find.byType(Scrollable),
    );
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
    await tester.pumpAndSettle();
    final scrolled = tester.state<ScrollableState>(list.first).position.pixels;
    expect(scrolled, greaterThan(0));

    await tester.tap(sheetHandle());
    await tester.pumpAndSettle();
    await tester.tap(sheetHandle());
    await tester.pumpAndSettle();

    expect(
      tester.state<ScrollableState>(list.first).position.pixels,
      scrolled,
    );
  });

  testWidgets("a drag up on the sheet's handle does nothing, so the counts "
      'and other ayas open only to a tap', (tester) async {
    await openStudy(tester);
    expect(find.byKey(const Key('open aya')), findsNothing);

    await tester.drag(sheetHandle(), const Offset(0, -200));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('open aya')), findsOneWidget);
    await tester.drag(sheetHandle(), const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('open aya')),
      findsOneWidget,
      reason: 'a second drag up keeps it open rather than toggling it shut',
    );
  });
}
