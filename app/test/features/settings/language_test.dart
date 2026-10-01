import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:wird/data/db.dart';

import '../../corpus.dart';
import '../../fonts.dart';
import '../../wird.dart';

void main() {
  late Database db;

  setUpAll(loadBundledFonts);
  setUp(() async => db = await testCorpus());

  /// The whole app, not the screen alone: the language is chosen on Settings
  /// and drawn by MaterialApp above the navigator, so a test that pumps the
  /// screen by itself cannot see the thing this setting does.
  Future<void> openSettings(WidgetTester tester) async {
    await pumpPhone(tester, await wholeApp(db));
    await goTo(tester, 'Settings');
  }

  // The failure: the reader taps Français and the app stays in English,
  // because the choice reached the database and nothing rebuilt above the
  // navigator. The setting reads as broken and there is no way to tell it from
  // a missing translation.
  testWidgets('the screen stays English after the reader asks for French',
      (tester) async {
    await openSettings(tester);
    expect(find.text('LANGUAGE'), findsOneWidget);

    await tester.tap(find.text('Français'));
    await tester.pumpAndSettle();

    expect(find.text('LANGUE'), findsOneWidget);
    expect(find.text('LANGUAGE'), findsNothing);
    expect(await languagePref(db), 'fr');
  });

  // The failure: the choice lives only in the widget, so the next launch comes
  // up in whatever the phone is set to and the reader picks again every time.
  testWidgets('a language picked is gone on the next launch', (tester) async {
    await setLanguagePref(db, 'fr');

    await pumpPhone(tester, await wholeApp(db));
    await tester.pumpAndSettle();

    expect(
      find.text('OÙ ALLER'),
      findsOneWidget,
      reason: 'the app opened in the language the reader left it in',
    );
  });
}
