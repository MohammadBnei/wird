import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:wird/data/audio.dart';
import 'package:wird/data/sets.dart';
import 'package:wird/features/study/study_screen.dart';
import 'package:wird/nav.dart';

import '../../corpus.dart';
import '../../fonts.dart';
import '../../offline.dart';
import '../../wird.dart';

/// Whether a French reader is read the Qurʼan in French.
///
/// The thing under test is not the translation — that is quran.com's — it is
/// that the reading screen asks for one at all, only in a language the reader
/// has, and says plainly that the per-word glosses underneath are not in it.
/// There is no French word-by-word rendering anywhere, so a screen that quietly
/// mixed the two would be the dishonest outcome rather than the missing one.
void main() {
  late Database db;
  late AudioCache audio;

  setUpAll(loadBundledFonts);
  // Both the corpus copy and the cache directory are real file work, which
  // never completes inside the fake-async zone a widget test body runs in.
  setUp(() async {
    db = await testCorpus();
    audio = await emptyCache();
  });

  test('the corpus carries a French rendering for every aya or none', () async {
    final all = await db.rawQuery(
      'SELECT (SELECT COUNT(*) FROM ayahs) AS ayas, '
      "(SELECT COUNT(*) FROM ayah_translations WHERE lang = 'fr') AS fr",
    );
    final ayas = all.single['ayas']! as int;
    final fr = all.single['fr']! as int;
    expect(
      fr == 0 || fr == ayas,
      isTrue,
      reason: 'a reading that is French for part of the Qurʼan and English for '
          'the rest is worse than one that is honestly English throughout; '
          '$fr of $ayas',
    );
  });

  test('a language with no rendering is asked for and answered with nothing',
      () async {
    // Not an error and not a gap: the screen draws no paragraph at all.
    expect(await translationsFor(db, [96001], 'de'), isEmpty);
    expect(await translationsFor(db, const [], 'fr'), isEmpty);
    expect(await translationsFor(db, [96001], 'fr'), isNotEmpty);
  });

  testWidgets('a French reader is read the aya in French, and told the glosses '
      'are not', (tester) async {
    await pumpPhone(
      tester,
      await wirdAround(
        db,
        StudyScreen(db: db),
        route: Routes.study,
        cache: audio,
        locale: const Locale('fr'),
      ),
    );
    await tester.pumpAndSettle();

    final rendered = (await translationsFor(db, [96001], 'fr'))[96001]!;
    expect(find.text(rendered), findsOneWidget);
    // The honesty half, said once rather than under every aya.
    expect(find.textContaining('mot à mot'), findsOneWidget);
  });

  testWidgets('an English reader is shown no translation and no notice',
      (tester) async {
    await pumpPhone(
      tester,
      await wirdAround(db, StudyScreen(db: db), route: Routes.study, cache: audio),
    );
    await tester.pumpAndSettle();

    final rendered = (await translationsFor(db, [96001], 'fr'))[96001]!;
    expect(find.text(rendered), findsNothing);
    expect(find.textContaining('mot à mot'), findsNothing);
  });
}
