import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:wird/data/root_repo.dart';
import 'package:wird/features/deepdive/deep_dive_screen.dart';
import 'package:wird/features/report/report.dart';
import 'package:wird/features/root/root_screen.dart';
import 'package:wird/features/study/root_sheet.dart';

import '../../corpus.dart';
import '../../fonts.dart';
import '../../wird.dart';

/// Two senses written the way the server stores them: several glosses joined
/// by '; ', which the screens split into numbered lines.
const _en = 'to show mercy; the womb';
const _fr = 'faire miséricorde; la matrice';

/// Whether a reader's verdict on a root's sense leaves the phone, and whether it
/// takes anything else with it.
///
/// The senses are written from lexicography and checked against the Qurʼan for
/// contradiction, and neither can see whether a sense is complete — ر ح م shipped
/// without "womb" past a gate scoring six terms. So the reader is the reviewer,
/// and a verdict that never reaches anybody is a button that does nothing.
void main() {
  late Database db;
  setUpAll(loadBundledFonts);
  setUp(() async {
    db = await testCorpus();
    await db.delete('outbox');
  });

  Future<Map<String, Object?>> only() async {
    final rows = await db.query('outbox');
    expect(rows, hasLength(1), reason: 'one verdict, one queued op');
    return jsonDecode(rows.single['body']! as String) as Map<String, Object?>;
  }

  test('a verdict is queued rather than sent, and names the root', () async {
    await judgeSense(
      db,
      root: 'رحم',
      sense: _en,
      good: false,
      context: await reportContext(db, screen: 'study', locale: 'en'),
    );
    final body = await only();
    // The root is the one thing this may carry that sendReport's own doc says
    // stays on the phone. It is here because a verdict with no subject is a
    // number nobody can act on, and because the reader pressed a button about
    // this root.
    expect(body['body'], 'sense bad: رحم');
    expect(body['kind'], 'improvement');
    // sense_version is what says WHICH sense was judged: the senses arrive over
    // HTTP, so two readers on the same corpus can be shown two different
    // sentences and both report the same corpus_version.
    expect(body['sense_version'], isA<String>());
    expect(body['corpus_version'], isA<int>());
    expect(body['screen'], 'study');
  });

  test('a good verdict and a bad one are told apart', () async {
    await judgeSense(
      db,
      root: 'صبر',
      sense: _en,
      good: true,
      context: const {},
    );
    expect((await only())['body'], 'sense good: صبر');
  });

  test('nothing but the verdict, the root and the build travels', () async {
    await judgeSense(
      db,
      root: 'صبر',
      sense: _en,
      good: true,
      context: await reportContext(db, screen: 'study', locale: 'en'),
    );
    final body = await only();
    expect(
      body.keys.toSet(),
      {'kind', 'body', 'app_version', 'platform', 'screen', 'corpus_version',
        'sense_version', 'locale', 'sense_hash', 'created_at'},
      reason: 'a new key here is reader data leaving the phone; add it on '
          'purpose or not at all',
    );
  });

  // The failure: a verdict says "bad" and the server cannot tell which of the
  // two languages, or which draft, the reader was looking at — so a redraft
  // inherits the old sentence's thumbs, and the French is blamed for the
  // English. The hash is of the exact stored string, before the screen splits
  // it, because that is what the server hashes.
  test('a verdict names the sentence it judged and the language it was drawn '
      'in, so a redraft is not blamed for its predecessor', () async {
    await judgeSense(
      db,
      root: 'رحم',
      sense: _fr,
      good: false,
      context: await reportContext(db, screen: 'study', locale: 'fr'),
    );
    final body = await only();
    expect(body['locale'], 'fr');
    expect(
      body['sense_hash'],
      sha256.convert(utf8.encode(_fr)).toString().substring(0, 12),
    );
  });

  // The failure: the app and the server hash the same sentence differently —
  // a normalisation on one side, an encoding on the other — and no verdict
  // ever matches the sentence it was cast on. The Go suite asserts the same
  // constant for the same string.
  test('the device hashes a sentence differently from the server', () {
    expect(senseHash('to bind; عقل — lier'), '66b51edc2622');
  });

  test('a report that is not a verdict claims no sentence', () async {
    await sendReport(
      db,
      kind: ReportKind.bug,
      body: 'the audio stops',
      context: await reportContext(db, screen: 'study', locale: 'en'),
    );
    expect((await only())['sense_hash'], '');
  });

  group('the thumbs', () {
    const root = 'رحم';

    Future<void> seed(String en, {String? fr}) async {
      await seedSenses(db, {root: en});
      if (fr != null) {
        await db.update(
          'root_notes',
          {'note_fr': fr},
          where: 'root_letters = ? AND word_id IS NULL',
          whereArgs: [root],
        );
      }
    }

    Future<void> mount(WidgetTester tester, {Locale locale = const Locale('en')}) async {
      final reading = (await rootReading(db, root, readIn: locale))!;
      await pumpPhone(
        tester,
        await wirdAround(
          db,
          Scaffold(
            body: Center(
              child: JudgeSense(db: db, reading: reading, screen: 'study'),
            ),
          ),
          locale: locale,
        ),
      );
    }

    final thumbs = find.byKey(const Key('judge sense good'));
    final thanks = find.text('Noted — thank you.');

    // The failure: a reader who judged a sense opens the root again and is
    // asked again, and either answers twice — noise in the one signal this
    // exists to collect — or learns the first answer went nowhere.
    testWidgets('a sense already judged asks again when the root is reopened',
        (tester) async {
      await seed(_en);
      await mount(tester);
      await tester.tap(thumbs);
      await tester.pumpAndSettle();
      expect(thanks, findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await mount(tester);
      expect(thanks, findsOneWidget);
      expect(thumbs, findsNothing);
    });

    // The failure: the memory is keyed by root alone, so a redrafted sense —
    // the very thing a bad verdict asks for — can never be judged.
    testWidgets('a redrafted sense stays answered with the old verdict',
        (tester) async {
      await seed(_en);
      await mount(tester);
      await tester.tap(thumbs);
      await tester.pumpAndSettle();

      await tester.pumpWidget(const SizedBox.shrink());
      await db.delete('root_notes');
      await seed('to show mercy; the womb; kinship');
      await mount(tester);
      expect(thumbs, findsOneWidget);
    });

    testWidgets('a verdict on the English hides the thumbs on the French',
        (tester) async {
      await seed(_en, fr: _fr);
      await mount(tester);
      await tester.tap(thumbs);
      await tester.pumpAndSettle();

      await tester.pumpWidget(const SizedBox.shrink());
      await mount(tester, locale: const Locale('fr'));
      expect(thumbs, findsOneWidget);
    });

    // The failure: the thanks is drawn before the write, so a verdict that
    // never reached the queue is thanked for, and the thumbs that could have
    // sent it again are gone.
    testWidgets('a verdict that could not be queued is thanked for and lost',
        (tester) async {
      await seed(_en);
      // The outbox refuses every insert, as a full disk would.
      await db.execute(
        'CREATE TEMP TRIGGER outbox_full BEFORE INSERT ON main.outbox '
        "BEGIN SELECT RAISE(ABORT, 'database or disk is full'); END",
      );
      addTearDown(() => db.execute('DROP TRIGGER IF EXISTS temp.outbox_full'));
      await mount(tester);
      await tester.tap(thumbs);
      await tester.pumpAndSettle();

      expect(thanks, findsNothing);
      expect(thumbs, findsOneWidget);
      expect(find.text('Not saved — try again'), findsOneWidget);
      expect(await db.query('sense_verdicts'), isEmpty,
          reason: 'remembered but never queued hides the thumbs for good');
    });

    // The failure: the root screen draws the sense with no thumbs beside it,
    // so the reader most likely to have read it closely has no way to say so.
    testWidgets('a sense on the root screen cannot be judged', (tester) async {
      await seed(_en);
      tester.view.physicalSize = const Size(402, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      unmountAtTearDown(tester);
      await tester.pumpWidget(
        await wirdAround(db, RootScreen(db: db, letters: root)),
      );
      await tester.pumpAndSettle();

      await tester.tap(thumbs);
      await tester.pumpAndSettle();

      final body = await only();
      expect(body['screen'], 'root');
      expect(body['body'], 'sense good: $root');
      expect(body['sense_hash'], senseHash(_en));
    });

    // The failure: the reader turns to the French while an English verdict is
    // still being written, and that write's answer — here a failure — is
    // drawn against the French sentence they have not judged.
    testWidgets("a write still in flight answers for the sentence the reader "
        'has moved on to', (tester) async {
      await seed(_en, fr: _fr);
      final english = (await rootReading(db, root, readIn: const Locale('en')))!;
      final french = (await rootReading(db, root, readIn: const Locale('fr')))!;
      Future<Widget> around(RootReading reading, Locale locale) => wirdAround(
        db,
        Scaffold(
          body: Center(
            child: JudgeSense(db: db, reading: reading, screen: 'study'),
          ),
        ),
        locale: locale,
      );
      final inEnglish = await around(english, const Locale('en'));
      final inFrench = await around(french, const Locale('fr'));
      await db.execute(
        'CREATE TEMP TRIGGER outbox_full BEFORE INSERT ON main.outbox '
        "BEGIN SELECT RAISE(ABORT, 'database or disk is full'); END",
      );
      addTearDown(() => db.execute('DROP TRIGGER IF EXISTS temp.outbox_full'));
      await pumpPhone(tester, inEnglish);

      // Another write holds the database, so the verdict waits behind it.
      final gate = Completer<void>();
      final holding = db.transaction((_) => gate.future);
      await tester.tap(thumbs);
      await tester.pump();
      await tester.pumpWidget(inFrench);
      gate.complete();
      await holding;
      await tester.pumpAndSettle();

      expect(find.text('Non enregistré — réessayez'), findsNothing);
      expect(thumbs, findsOneWidget);
    });

    // The failure: the deep dive draws the sense with no thumbs, or files the
    // verdict under a screen name nobody can find it by.
    testWidgets('a sense on the deep dive cannot be judged', (tester) async {
      await seedSenses(db, {'عقل': 'to bind; to understand'});
      tester.view.physicalSize = const Size(402, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      unmountAtTearDown(tester);
      await tester.pumpWidget(
        await wirdAround(
          db,
          DeepDiveScreen(db: db, ayahId: 2044, letters: 'عقل'),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(thumbs);
      await tester.pumpAndSettle();

      final body = await only();
      expect(body['screen'], 'deep-dive');
      expect(body['body'], 'sense good: عقل');
    });
  });
}
