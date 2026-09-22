import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wird/theme/nocturne.dart';

const cssPath = '../docs/design/nocturne-styles.css';

/// The `:root` declarations of the design system, keyed like
/// `color/accent-2-800` and `space/4`, with comments removed so the prose
/// inside them cannot be read as a declaration.
Map<String, String> cssTokens(String css) {
  final body = css.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
  final root = body.substring(body.indexOf(':root'));
  final declarations = RegExp(
    r'--(color|space|radius|shadow)-([a-z0-9-]+)\s*:\s*([^;]+);',
  );
  return {
    for (final m in declarations.allMatches(
      root.substring(0, root.indexOf('}')),
    ))
      '${m[1]}/${m[2]}': m[3]!.trim(),
  };
}

/// The colors the CSS states outright. `color-mix(… , transparent)` is a hex
/// at a percentage of alpha; anything else is left to the existence check.
Color? literalColor(String value) {
  final hex = RegExp(r'^#([0-9a-fA-F]{6})$').firstMatch(value);
  if (hex != null) return Color(0xFF000000 | int.parse(hex[1]!, radix: 16));
  final mix = RegExp(
    r'^color-mix\(in srgb,\s*#([0-9a-fA-F]{6})\s+(\d+)%,\s*transparent\)$',
  ).firstMatch(value);
  if (mix == null) return null;
  final alpha = (int.parse(mix[2]!) * 255 / 100).round();
  return Color(alpha << 24 | int.parse(mix[1]!, radix: 16));
}

void main() {
  final nocturne = nocturneTheme().extension<Nocturne>()!;
  final tokens = cssTokens(File(cssPath).readAsStringSync());

  test('a token added to the design system leaves screens unable to paint it', () {
    expect(tokens, isNotEmpty, reason: '$cssPath declared no tokens at all');
    final counterparts = {
      for (final k in nocturne.colors.keys) 'color/$k',
      for (final k in nocturne.spaces.keys) 'space/$k',
      for (final k in nocturne.radii.keys) 'radius/$k',
      for (final k in nocturne.shadows.keys) 'shadow/$k',
    };
    expect(tokens.keys.toSet().difference(counterparts), isEmpty);
  });

  test('a retuned CSS color, space or radius would ship as a stale value', () {
    final stale = <String, String>{};
    tokens.forEach((name, value) {
      final kind = name.split('/').first;
      final key = name.split('/').last;
      final Object? dart;
      final Object? css;
      switch (kind) {
        case 'color':
          dart = nocturne.colors[key]?.toARGB32();
          css = literalColor(value)?.toARGB32();
        case 'space':
          dart = nocturne.spaces[key];
          css = double.tryParse(value.replaceAll('px', ''));
        case 'radius':
          dart = nocturne.radii[key];
          css = double.tryParse(value.replaceAll('px', ''));
        default:
          return; // A CSS shadow list is not a Flutter shadow list.
      }
      if (css != null && dart != css) stale[name] = '$value is $dart in Dart';
    });
    expect(stale, isEmpty);
  });
}
