import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wird/data/root_repo.dart';
import 'package:wird/features/root/root_sections.dart';

import '../../corpus.dart';
import '../../fonts.dart';
import '../../wird.dart';

/// A reading the way the served pack leaves one: a sentence, a basis paragraph
/// and **no evidence words**, which is every one of the 1,642 drafts.
///
/// Built by hand rather than read back through `rootRepo`, because what is
/// under test is what the section draws for a given reading, and the state that
/// matters — a fetched pack with no evidence — is one no bundled corpus is in.
RootReading reading({
  String? coreSense = 'the root turns on holding fast to something',
  String? senseBasis = 'A draft, written by a machine and read by no person.',
  List<String> senseEvidence = const [],
  bool sensesFetched = true,
}) => RootReading(
  letters: 'صبر',
  display: 'ص ب ر',
  translit: 'ṣ-b-r',
  occurrences: 103,
  surahCount: 45,
  sources: const ['Quranic Arabic Corpus'],
  coreSense: coreSense,
  locale: 'en',
  senseSource: 'Wird',
  senseBasis: senseBasis,
  senseEvidence: senseEvidence,
  sensesFetched: sensesFetched,
  derivatives: const [],
  irab: const {},
);

void main() {
  late Database db;

  setUpAll(loadBundledFonts);
  setUp(() async {
    db = await testCorpus();
  });

  Future<void> draw(WidgetTester tester, RootReading r) async => pumpPhone(
    tester,
    await wirdAround(
      db,
      Scaffold(
        body: SingleChildScrollView(child: CoreSense(reading: r)),
      ),
    ),
  );

  // ADR 0010's one named risk, and the reason this lane exists. The honest
  // sentence — a machine wrote this and no person read it — is drawn in exactly
  // one place, SenseEvidence, which is opened by exactly one tap, which was
  // drawn only when the sense carried evidence words. Every served draft
  // carries none, so the sentence was reachable on no root in the corpus while
  // being shipped against all 1,642.
  testWidgets('a sense with no evidence words says no person checked it, and '
      'the reader can never get to that sentence', (tester) async {
    await draw(tester, reading());

    await tester.tap(find.text("This app's own reading"));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('read by no person'),
      findsOneWidget,
      reason: 'the basis is the whole reason the sheet opens',
    );
    // And the sheet does not draw a heading over an empty list with a count of
    // nought beside it.
    // SectionHeading uppercases, so that is what a reader would see.
    expect(find.text('THE WORDS IT WAS READ FROM'), findsNothing);
    expect(find.text('0 words'), findsNothing);
  });

  // The other half: a bundled sense does carry words, and taking the empty case
  // out must not take the list with it.
  testWidgets('the words a sense was read from are still drawn when it has '
      'some', (tester) async {
    await draw(
      tester,
      reading(senseEvidence: const ['صَبَرُوا۟', 'ٱلصَّٰبِرِينَ']),
    );

    await tester.tap(
      find.textContaining("This app's own reading, borne out by 2"),
    );
    await tester.pumpAndSettle();

    expect(find.text('THE WORDS IT WAS READ FROM'), findsOneWidget);
    expect(find.text('2 words'), findsOneWidget);
    expect(find.text('صَبَرُوا۟'), findsOneWidget);
  });

  // One sentence was doing two jobs. A phone that has never had a signal holds
  // no senses at all, and telling its reader 1,642 times that nobody has
  // written one blames the absence on the work rather than on the download —
  // and is false.
  testWidgets('a phone that has fetched nothing is told nobody wrote a sense', (
    tester,
  ) async {
    await draw(tester, reading(coreSense: null, sensesFetched: false));

    expect(find.textContaining('has not fetched any yet'), findsOneWidget);
    expect(
      find.textContaining('written one root at a time'),
      findsNothing,
      reason: 'nobody having written one is the other state, not this one',
    );
  });

  testWidgets('a root the fetched pack carries no sense for says so, and does '
      'not blame the download', (tester) async {
    await draw(tester, reading(coreSense: null));

    expect(find.textContaining('written one root at a time'), findsOneWidget);
    expect(find.textContaining('has not fetched any yet'), findsNothing);
    // The sentence this replaced stated the corpus-derivation standard, which
    // the served drafts were not written to.
    expect(
      find.textContaining("root's own words in the Qur'an bear it out"),
      findsNothing,
    );
  });
}
