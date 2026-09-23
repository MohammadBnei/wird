import 'package:flutter/material.dart';
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

const rootless = StudyWord(
  id: 96001004,
  text: 'ٱلَّذِى',
  translit: 'alladhī',
  gloss: 'the One Who',
);

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
                child: WordTile(
                  face: face,
                  voice: voice ?? face.voice(),
                  open: open,
                  prefs: prefs,
                  onOpen: (_) {},
                  onHear: (_) {},
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
}
