import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wird/theme/glow.dart';
import 'package:wird/theme/nocturne.dart';
import 'package:wird/widgets/lit_aya.dart';

void main() {
  // A long aya whose root word comes near its end: in one line from the
  // start, the line would end long before it.
  final long = [
    for (var i = 1; i <= 40; i++) (id: i, text: 'w$i', lit: i == 37),
  ];

  Future<String> drawn(WidgetTester tester, Widget aya) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: nocturneTheme(),
        home: Scaffold(body: SizedBox(width: 300, child: aya)),
      ),
    );
    return tester.widget<RichText>(find.byType(RichText)).text.toPlainText();
  }

  testWidgets("the root's word in a long other aya is cut off the row", (
    tester,
  ) async {
    final line = await drawn(
      tester,
      LitAya.window(long, glow: Glow.reading, style: const TextStyle()),
    );

    expect(line, contains('w37'));
    expect(line, startsWith('… '), reason: 'the aya goes on before the window');
    expect(line, endsWith(' …'), reason: 'and after it');
    expect(line, isNot(contains('w1 ')));
  });

  testWidgets('a whole aya drops words or marks the wrong one', (tester) async {
    final aya = await drawn(
      tester,
      LitAya(long, glow: Glow.reading, style: const TextStyle()),
    );

    expect(aya.split(' '), hasLength(40));
    final glowing = <String>[];
    tester.widget<RichText>(find.byType(RichText)).text.visitChildren((span) {
      if (span is TextSpan && (span.style?.shadows?.isNotEmpty ?? false)) {
        glowing.add(span.text!.trim());
      }
      return true;
    });
    expect(glowing, ['w37']);
  });
}
