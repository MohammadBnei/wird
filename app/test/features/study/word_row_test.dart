import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wird/app.dart';
import 'package:wird/data/sets.dart';
import 'package:wird/features/study/word_row.dart';
import 'package:wird/theme/nocturne.dart';

import '../../corpus.dart';
import '../../fonts.dart';

const rooted = StudyWord(
  id: 96001001,
  text: 'ٱقْرَأْ',
  translit: 'iqraʾ',
  gloss: 'Read',
  root: 'ق ر أ',
);

/// The word on screen 1a whose kasratayn the rule was drawn straight
/// through. Arabic inks anywhere from 0.27 em to 1.22 em below the baseline
/// across the corpus, against the 0.60 em the line box the rule hangs from
/// allows, so no fixed line clears the deep words without floating a finger's
/// width under the ordinary ones.
const straddling = StudyWord(
  id: 96001002,
  text: 'عَلَقٍ',
  gloss: 'a clinging substance',
  root: 'ع ل ق',
);

const rootless = StudyWord(
  id: 96001004,
  text: 'ٱلَّذِى',
  translit: 'alladhī',
  gloss: 'the One Who',
);

final tileKey = GlobalKey();

void main() {
  late Prefs prefs;
  late Nocturne n;

  setUpAll(loadBundledFonts);
  setUp(() async => prefs = await Prefs.read(await testCorpus()));

  /// One word as the set draws it, on the phone the app is judged on.
  Future<void> show(
    WidgetTester tester,
    StudyWord word, {
    bool hearable = false,
    bool open = false,
    WordVoice? voice,
  }) async {
    final face = WordFace(word, hearable: hearable);
    await tester.pumpWidget(
      MaterialApp(
        theme: nocturneTheme(),
        home: Builder(
          builder: (context) {
            n = Nocturne.of(context);
            return Scaffold(
              body: Center(
                child: RepaintBoundary(
                  key: tileKey,
                  // The page behind the tile, so a capture of the boundary
                  // carries the colours a reader sees rather than the tile's
                  // own translucency over nothing.
                  child: ColoredBox(
                    color: Nocturne.of(context).bg,
                    child: WordTile(
                      face: face,
                      voice: voice ?? face.voice(),
                      open: open,
                      prefs: prefs,
                      onOpen: (_) {},
                      onHear: (_) {},
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The rule under the word's Arabic.
  BorderSide line(WidgetTester tester) {
    final box = tester.widget<Container>(
      find
          .ancestor(
            of: find.byType(Text).first,
            matching: find.byType(Container),
          )
          .first,
    );
    return ((box.decoration! as BoxDecoration).border! as Border).bottom;
  }

  /// Whatever the tile paints around the word itself.
  BoxDecoration tile(WidgetTester tester) =>
      tester.widget<Container>(find.byType(Container).first).decoration!
          as BoxDecoration;

  Color glossColour(WidgetTester tester) =>
      tester.widget<Text>(find.text('Read')).style!.color!;

  testWidgets('a phone with no recitation downloaded shows a page of plain '
      'Arabic, with nothing to say which words open a root', (tester) async {
    await show(tester, rooted);

    expect(
      line(tester).color,
      isNot(Colors.transparent),
      reason: 'the first run is the run that has to teach the gesture',
    );
  });

  testWidgets('a word with nothing under it is underlined anyway, so the rule '
      'stops meaning that a tap opens something', (tester) async {
    await show(tester, rootless, hearable: true);

    expect(line(tester).color, Colors.transparent);
  });

  testWidgets('the mark on the open word floods the accent across the word '
      'and its neighbour, and cuts the leading hamza', (tester) async {
    await show(tester, rooted, open: true);
    final drawn = tile(tester);

    expect(
      drawn.boxShadow,
      anyOf(isNull, isEmpty),
      reason: 'a blur paints through a transparent box and spills onto the '
          'next word',
    );
    expect(
      drawn.border,
      isNull,
      reason: 'a box sized to the text metrics crosses the marks that sit '
          'above and below the line',
    );
  });

  testWidgets('the open word cannot be picked out of the page, so the reader '
      'cannot tell which word the panel below belongs to', (tester) async {
    await show(tester, rooted, open: true);
    final lit = (line(tester).color, glossColour(tester));
    await show(tester, rooted);

    expect(lit, (n.accent, n.color('accent-300')));
    expect(line(tester).color, isNot(n.accent));
    expect(glossColour(tester), isNot(n.color('accent-300')));
  });

  testWidgets('the word sounding now loses its fill to the root the reader '
      'happens to have open', (tester) async {
    await show(tester, rooted, hearable: true, voice: WordVoice.sounding);

    expect(tile(tester).color, n.accent.withValues(alpha: 0.16));
    expect(
      line(tester).color,
      isNot(n.accent),
      reason: 'sounding is not open, and the rule speaks only for the root',
    );
  });

  /// The tile's pixels, as painted.
  Future<(Uint8List, int)> pixels(WidgetTester tester) async {
    final boundary =
        tileKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    // The engine answers outside the fake-async zone a widget test body runs
    // in; awaited inside it, the picture never arrives.
    late Uint8List px;
    late int width;
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      px = data!.buffer.asUint8List();
      width = image.width;
      image.dispose();
    });
    return (px, width);
  }

  testWidgets('the rule under a rooted word is drawn through the marks that '
      'hang below the line, so a kasratayn reads as part of the underline', (
    tester,
  ) async {
    const word = straddling;
    await show(tester, word);
    final (px, width) = await pixels(tester);
    final rows = px.length ~/ 4 ~/ width;

    // The rule is a solid two-pixel border over the page, so its pixels are
    // exactly that blend. An antialiased glyph edge can land on the same
    // colour, so the rule is found as the rows carrying a run of it.
    final rule = Color.alphaBlend(n.textAt(0.20), n.bg);
    bool isRule(int x, int y) {
      final at = (y * width + x) * 4;
      return px[at] == (rule.r * 255).round() &&
          px[at + 1] == (rule.g * 255).round() &&
          px[at + 2] == (rule.b * 255).round();
    }

    bool isInk(int x, int y) {
      final at = (y * width + x) * 4;
      return (px[at] + px[at + 1] + px[at + 2]) / (3 * 255) > 0.6;
    }

    final perRow = [
      for (var y = 0; y < rows; y++)
        [
          for (var x = 0; x < width; x++)
            if (isRule(x, y)) x,
        ].length,
    ];
    final drawn = perRow.reduce((a, b) => a > b ? a : b);
    final band = [
      for (var y = 0; y < rows; y++)
        if (perRow[y] > drawn ~/ 2) y,
    ];

    expect(drawn, greaterThan(10), reason: 'the rule is drawn at all');

    // Where the word crosses the rule, the rule gives way — the skip-ink a
    // browser does for a descender. A rule pixel in a column the Arabic
    // inks through, or inks within a pixel of, is the rule drawn into the
    // Arabic.
    final through = <int>[];
    for (var x = 0; x < width; x++) {
      final inked = [
        for (var y = band.first - 1; y <= band.last + 1; y++)
          if (y >= 0 && y < rows && isInk(x, y)) y,
      ];
      if (inked.isEmpty) continue;
      if (band.any((y) => isRule(x, y))) through.add(x);
    }

    expect(
      through,
      isEmpty,
      reason:
          'the rule is painted at columns $through where '
          '${word.text} inks through it',
    );
  });
}
