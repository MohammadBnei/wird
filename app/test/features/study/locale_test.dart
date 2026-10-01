import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wird/l10n/app_localizations.dart';


/// Whether the locale layer reaches a reader, and whether it can lie.
///
/// Two different questions. The first is that a French device draws French: the
/// delegates are wired, the ARB resolves, and a screen reads a string rather
/// than carrying it. The second is that the two ARB files say the same things —
/// a key present in English and missing in French is invisible until a French
/// reader meets it, and no analyzer or golden catches that.
void main() {
  test('both locales carry the same keys', () {
    Map<String, dynamic> read(String name) =>
        jsonDecode(File('lib/l10n/$name').readAsStringSync())
            as Map<String, dynamic>;
    // `@@locale` and the `@key` description blocks are metadata, not strings a
    // reader ever sees, and only the template file carries the descriptions.
    Set<String> keys(Map<String, dynamic> arb) =>
        arb.keys.where((k) => !k.startsWith('@')).toSet();

    final en = keys(read('app_en.arb'));
    final fr = keys(read('app_fr.arb'));
    expect(
      en.difference(fr),
      isEmpty,
      reason: 'these keys are English-only, so a French reader gets English: '
          '${en.difference(fr).join(', ')}',
    );
    expect(
      fr.difference(en),
      isEmpty,
      reason: 'these keys exist only in French, so nothing draws them: '
          '${fr.difference(en).join(', ')}',
    );
  });

  testWidgets('each locale draws its own strings', (tester) async {
    Future<void> pumpIn(Locale locale) => tester.pumpWidget(
      Localizations(
        locale: locale,
        delegates: AppLocalizations.localizationsDelegates,
        child: Builder(
          builder: (context) => Text(
            AppLocalizations.of(context)!.study_form,
            textDirection: TextDirection.ltr,
          ),
        ),
      ),
    );

    await pumpIn(const Locale('fr'));
    expect(find.text('Forme'), findsOneWidget);
    expect(find.text('Form'), findsNothing);

    // The other way too, so this would fail if the delegate resolved to one
    // locale whatever it was handed.
    await pumpIn(const Locale('en'));
    expect(find.text('Form'), findsOneWidget);
    expect(find.text('Forme'), findsNothing);
  });
}
