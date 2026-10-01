import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Literals that are the same in every locale, and why.
const _allowed = {
  // The app's own name.
  'Wird',
};

/// Where a string reaches the screen: the first argument of a `Text`, or one
/// of the named arguments a widget draws or reads aloud. A string literal
/// directly after either is one no ARB can translate.
final _drawn = RegExp(
  r'''(?:\bText\(\s*|\b(?:label|title|why|tooltip|semanticsLabel|hintText):\s*)('(?:[^'\\\n]|\\.)*'|"(?:[^"\\\n]|\\.)*")''',
);

final _letter = RegExp(r'\p{L}', unicode: true);

/// Interpolations carry data (a sūra's name, a number), not words to translate.
final _interpolation = RegExp(r'\$\{[^}]*\}|\$\w+');

void main() {
  test('a string drawn outside the ARB leaves a French reader in English', () {
    final found = <String>[];
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => !f.path.startsWith('lib/l10n/'))
        // The developer's widget gallery, never shown to a reader.
        .where((f) => f.path != 'lib/gallery.dart');
    for (final file in files) {
      // Comments blanked rather than dropped, so offsets still give lines.
      final source = file.readAsStringSync().replaceAllMapped(
        RegExp(r'^\s*//.*$', multiLine: true),
        (m) => ' ' * m[0]!.length,
      );
      for (final match in _drawn.allMatches(source)) {
        final quoted = match[1]!;
        final text = quoted.substring(1, quoted.length - 1);
        if (_allowed.contains(text)) continue;
        if (!_letter.hasMatch(text.replaceAll(_interpolation, ''))) continue;
        final line = '\n'
            .allMatches(source.substring(0, match.end - quoted.length))
            .length;
        found.add('${file.path}:${line + 1}: $quoted');
      }
    }
    expect(found, isEmpty, reason: 'move these into lib/l10n/app_*.arb');
  });
}
