import 'package:flutter/material.dart';

/// Every token in docs/design/nocturne-styles.css, keyed by the CSS custom
/// property name with its `--color-` / `--space-` / `--radius-` / `--shadow-`
/// prefix stripped. The keys are the contract the drift test checks.
@immutable
class Nocturne extends ThemeExtension<Nocturne> {
  const Nocturne({
    required this.colors,
    required this.spaces,
    required this.radii,
    required this.shadows,
  });

  final Map<String, Color> colors;
  final Map<String, double> spaces;
  final Map<String, double> radii;
  final Map<String, List<BoxShadow>> shadows;

  static const headingFamily = 'Inter';
  static const bodyFamily = 'Inter';

  /// Qur'anic diacritics are mangled by the platform Arabic fonts, so the
  /// Arabic face is bundled and named rather than left to the system.
  static const arabicFamily = 'Scheherazade New';

  /// Headings sit at 500 on Inter's variable weight axis.
  static const headingVariations = [FontVariation('wght', 500)];

  static const _dark = Nocturne(
    colors: {
      'bg': Color(0xFF161826),
      'surface': Color(0xFF232532),
      'text': Color(0xFFE9E9ED),
      'accent': Color(0xFF9184D9),
      // A mono scheme: accent-2 is a machine-derived stand-in kept so both
      // sets resolve. It reads as the same role as the accent.
      'accent-2': Color(0xFFA7A1DB),
      'divider': Color(0x29E9E9ED),
      'neutral-100': Color(0xFFF3F5FE),
      'neutral-200': Color(0xFFE4E7F5),
      'neutral-300': Color(0xFFCFD3E5),
      'neutral-400': Color(0xFFB2B6CA),
      'neutral-500': Color(0xFF9397AB),
      'neutral-600': Color(0xFF75798C),
      'neutral-700': Color(0xFF595D6C),
      'neutral-800': Color(0xFF3F424D),
      'neutral-900': Color(0xFF292B31),
      'accent-100': Color(0xFFF5F4FF),
      'accent-200': Color(0xFFE7E5FE),
      'accent-300': Color(0xFFD2CEFD),
      'accent-400': Color(0xFFB5ABFC),
      'accent-500': Color(0xFF968AE0),
      'accent-600': Color(0xFF796CBF),
      'accent-700': Color(0xFF5D5294),
      'accent-800': Color(0xFF423A6A),
      'accent-900': Color(0xFF2B2741),
      'accent-2-100': Color(0xFFF5F4FF),
      'accent-2-200': Color(0xFFE7E5FE),
      'accent-2-300': Color(0xFFD2CEFD),
      'accent-2-400': Color(0xFFB5AFE8),
      'accent-2-500': Color(0xFF9690C9),
      'accent-2-600': Color(0xFF7972A9),
      'accent-2-700': Color(0xFF5C5783),
      'accent-2-800': Color(0xFF423E5D),
      'accent-2-900': Color(0xFF2B293A),
      'section': Color(0xFF262A60),
      'section-glow': Color(0xFF353B80),
      'section-ghost': Color(0xFF4C5397),
    },
    // Density 0.70 — dense on purpose.
    spaces: {'1': 2.8, '2': 5.6, '3': 8.4, '4': 11.2, '6': 16.8, '8': 22.4},
    radii: {'sm': 4, 'md': 8, 'lg': 14},
    shadows: {
      'sm': [
        BoxShadow(color: Color(0xFF3F424D), spreadRadius: 1),
      ],
      'md': [
        BoxShadow(color: Color(0xFF595D6C), spreadRadius: 1),
        BoxShadow(
          color: Color(0x8C000000),
          offset: Offset(0, 6),
          blurRadius: 18,
        ),
      ],
      'lg': [
        BoxShadow(color: Color(0xFF9397AB), spreadRadius: 1),
        BoxShadow(
          color: Color(0xA6000000),
          offset: Offset(0, 16),
          blurRadius: 40,
        ),
      ],
    },
  );

  Color color(String name) => colors[name]!;
  double space(String step) => spaces[step]!;
  double radius(String step) => radii[step]!;
  List<BoxShadow> shadow(String step) => shadows[step]!;

  Color get bg => color('bg');
  Color get surface => color('surface');
  Color get text => color('text');
  Color get accent => color('accent');
  Color get divider => color('divider');

  /// Muted text: the CSS mixes the text token down rather than picking a ramp
  /// step, so the opacity travels with the token.
  Color textAt(double fraction) => text.withValues(alpha: fraction);

  static Nocturne of(BuildContext context) =>
      Theme.of(context).extension<Nocturne>()!;

  @override
  Nocturne copyWith({
    Map<String, Color>? colors,
    Map<String, double>? spaces,
    Map<String, double>? radii,
    Map<String, List<BoxShadow>>? shadows,
  }) => Nocturne(
    colors: colors ?? this.colors,
    spaces: spaces ?? this.spaces,
    radii: radii ?? this.radii,
    shadows: shadows ?? this.shadows,
  );

  @override
  Nocturne lerp(Nocturne? other, double t) {
    if (other == null) return this;
    return Nocturne(
      colors: {
        for (final e in colors.entries)
          e.key: Color.lerp(e.value, other.colors[e.key], t)!,
      },
      spaces: {
        for (final e in spaces.entries)
          e.key: lerpDouble(e.value, other.spaces[e.key]!, t),
      },
      radii: {
        for (final e in radii.entries)
          e.key: lerpDouble(e.value, other.radii[e.key]!, t),
      },
      shadows: t < 0.5 ? shadows : other.shadows,
    );
  }

  static double lerpDouble(double a, double b, double t) => a + (b - a) * t;
}

/// Nocturne is dark only; there is no light mode.
ThemeData nocturneTheme() {
  const n = Nocturne._dark;
  final body = TextStyle(
    fontFamily: Nocturne.bodyFamily,
    fontSize: 15,
    height: 1.55,
    color: n.text,
  );
  // The CSS tightens headings by -0.015em, which is a fraction of the size.
  TextStyle heading(double size) => body.copyWith(
    fontFamily: Nocturne.headingFamily,
    fontVariations: Nocturne.headingVariations,
    fontSize: size,
    height: 1.12,
    letterSpacing: -0.015 * size,
  );
  return ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: n.bg,
    canvasColor: n.bg,
    fontFamily: Nocturne.bodyFamily,
    colorScheme: ColorScheme.dark(
      primary: n.accent,
      surface: n.surface,
      onSurface: n.text,
    ),
    textTheme: TextTheme(
      displayLarge: heading(42),
      displayMedium: heading(32),
      displaySmall: heading(25),
      headlineMedium: heading(20),
      headlineSmall: heading(16),
      titleMedium: heading(17).copyWith(letterSpacing: 0),
      bodyMedium: body,
      bodySmall: body.copyWith(fontSize: 13),
      labelSmall: body.copyWith(fontSize: 11),
    ),
    extensions: const [n],
  );
}
