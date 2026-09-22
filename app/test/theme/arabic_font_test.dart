import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wird/theme/nocturne.dart';

import '../fonts.dart';

const aya = 'وَالْعَصْرِ'; // 103:1

Widget _aya(String family) => Directionality(
  textDirection: TextDirection.rtl,
  child: Center(
    child: Text(aya, style: TextStyle(fontFamily: family, fontSize: 34)),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Real file reads cannot complete inside testWidgets' fake async zone.
  setUpAll(loadBundledFonts);

  test('the Arabic face is missing from the bundle, so ayas ship in a '
      'substitute that mangles their diacritics', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('family: ${Nocturne.arabicFamily}'));
    final asset = RegExp(r'asset: (assets/fonts/ScheherazadeNew[^\s]*\.ttf)')
        .firstMatch(pubspec);
    expect(asset, isNotNull, reason: 'no Scheherazade New face is declared');
    expect(File(asset![1]!).existsSync(), isTrue);
  });

  testWidgets('a vowelled aya is painted by a substituted font rather than '
      'the bundled Scheherazade New', (tester) async {
    await tester.pumpWidget(_aya(Nocturne.arabicFamily));
    final rendered = tester.renderObject<RenderParagraph>(find.byType(Text));
    expect(
      (rendered.text.style as TextStyle).fontFamily,
      Nocturne.arabicFamily,
    );
    final arabic = tester.getSize(find.byType(Text));
    expect(arabic.width, greaterThan(40));

    // A face that never loaded is substituted, and then measures exactly as
    // a family that was never bundled at all.
    await tester.pumpWidget(_aya('NoSuchFamily'));
    expect(tester.getSize(find.byType(Text)).width, isNot(arabic.width));
  });
}
