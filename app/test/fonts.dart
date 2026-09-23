import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wird/theme/nocturne.dart';

/// The icon face the Material widgets draw from. It is not in the bundle —
/// `uses-material-design` pulls it out of the SDK at build time — so a test
/// binding that only loads the bundle renders every icon as the notdef box,
/// and a golden of a burger, a stop button or a back chevron is a picture of
/// a hollow square that nobody can tell from a design motif.
File get _iconFace => File(
  '${Platform.environment['FLUTTER_ROOT']}'
  '/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
);

/// Loads the bundled faces into the test binding. Without this the whole
/// suite paints in the test placeholder font and proves nothing about type.
Future<void> loadBundledFonts() async {
  final files = {
    Nocturne.bodyFamily: File('assets/fonts/Inter-Variable.ttf'),
    Nocturne.arabicFamily: File('assets/fonts/ScheherazadeNew-Regular.ttf'),
    Icons.menu.fontFamily!: _iconFace,
  };
  for (final entry in files.entries) {
    final bytes = await entry.value.readAsBytes();
    await (FontLoader(
      entry.key,
    )..addFont(Future.value(ByteData.view(bytes.buffer)))).load();
  }
}
