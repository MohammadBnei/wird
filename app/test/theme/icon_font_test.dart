import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fonts.dart';

const _frame = Key('frame');

/// One icon glyph, at the size the transport draws its stop.
Widget _glyph(String? family) => Directionality(
  textDirection: TextDirection.ltr,
  child: RepaintBoundary(
    key: _frame,
    child: Center(
      child: Text(
        String.fromCharCode(Icons.menu.codePoint),
        style: TextStyle(fontFamily: family, fontSize: 56),
      ),
    ),
  ),
);

Future<Uint8List> _painted(WidgetTester tester, String? family) async {
  await tester.pumpWidget(_glyph(family));
  final frame = tester.renderObject<RenderRepaintBoundary>(find.byKey(_frame));
  late Uint8List bytes;
  await tester.runAsync(() async {
    final image = await frame.toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    bytes = data!.buffer.asUint8List();
  });
  return bytes;
}

void main() {
  setUpAll(loadBundledFonts);

  testWidgets('the icon face never reached the test binding, so every burger, '
      'stop and chevron in the goldens is the notdef box — a purple square a '
      'reader of those images takes for a design motif', (tester) async {
    final icon = await _painted(tester, Icons.menu.fontFamily);

    // A family that was never loaded is the notdef box itself. An icon that
    // paints the same thing is one.
    final notdef = await _painted(tester, 'NoSuchFamily');
    expect(icon, isNot(notdef));
  });
}
