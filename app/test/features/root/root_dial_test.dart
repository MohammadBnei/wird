import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:wird/data/root_repo.dart';
import 'package:wird/features/root/root_dial.dart';
import 'package:wird/theme/nocturne.dart';

import '../../corpus.dart';
import '../../fonts.dart';

/// A root with five derivatives — the ring the design itself draws.
const fiveDerivatives = 'عقل';

void main() {
  late Database db;
  late RootReading reading;

  setUpAll(loadBundledFonts);
  setUp(() async {
    db = await testCorpus();
    reading = (await rootReading(db, fiveDerivatives))!;
  });

  /// The dial with the index held outside it, the way the screen holds it.
  Future<int Function()> dial(WidgetTester tester) async {
    var index = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: nocturneTheme(),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => RootDial(
              reading: reading,
              index: index,
              onIndex: (i) => setState(() => index = i),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return () => index;
  }

  Finder label(int i) => find.text(reading.derivatives[i].text);

  test('the ring spins backwards through every other form when the dial '
      'passes the last derivative and comes round to the first', () {
    expect(nearestPosition(4, 0, 5), 5);
    expect(nearestPosition(0, 4, 5), -1);
    expect(nearestPosition(5, 1, 5), 6);
    // Nothing to travel: the dial is already showing it.
    expect(nearestPosition(2, 2, 5), 2);
  });

  test('a derivative and the one behind it land in different places, so the '
      'ring drifts a little further out of true with every step', () {
    for (var i = 0; i < 4; i++) {
      final held = satelliteOffset(i, 0, 5);
      final stepped = satelliteOffset(i + 1, 1, 5);
      expect((stepped - held).distance, lessThan(0.001));
    }
  });

  testWidgets('a derivative’s name is carried round the ring lying on '
      'its side instead of staying upright', (tester) async {
    await dial(tester);
    final upright = [
      for (var i = 0; i < reading.derivatives.length; i++)
        tester.getSize(label(i)),
    ];

    await tester.tap(find.bySemanticsLabel('Next'));
    await tester.pumpAndSettle();

    for (var i = 0; i < reading.derivatives.length; i++) {
      expect(
        tester.getSize(label(i)),
        upright[i],
        reason: 'the label turned with the ring instead of staying flat',
      );
    }
  });

  testWidgets('the ring turns but leaves a different derivative under the '
      'marker than the one the dial says it is showing', (tester) async {
    final index = await dial(tester);
    await tester.tap(find.bySemanticsLabel('Next'));
    await tester.pumpAndSettle();

    expect(index(), 1);
    final tops = [
      for (var i = 0; i < reading.derivatives.length; i++)
        tester.getCenter(label(i)).dy,
    ];
    expect(tops[1], lessThan(tops.where((t) => t != tops[1]).reduce(min)));
  });

  testWidgets('swiping the ring does nothing, so the one gesture the screen '
      'invites the reader to make is dead', (tester) async {
    final index = await dial(tester);
    // Between the centre disc and the ring, clear of every label, so the
    // swipe is tested against the ring and not against a satellite's tap.
    final open =
        tester.getCenter(find.byType(TweenAnimationBuilder<double>)) -
        const Offset(90, 0);

    await tester.flingFrom(open, const Offset(-120, 0), 600);
    await tester.pumpAndSettle();
    expect(index(), 1);

    await tester.flingFrom(open, const Offset(120, 0), 600);
    await tester.pumpAndSettle();
    expect(index(), 0);
  });

  testWidgets('tapping a derivative on the ring leaves the dial pointing '
      'somewhere else', (tester) async {
    final index = await dial(tester);
    await tester.tap(label(3), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(index(), 3);
  });
}

double min(double a, double b) => a < b ? a : b;
