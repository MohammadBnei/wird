import 'dart:io';

import 'package:flutter/services.dart';
import 'package:wird/theme/nocturne.dart';

/// Loads the bundled faces into the test binding. Without this the whole
/// suite paints in the test placeholder font and proves nothing about type.
Future<void> loadBundledFonts() async {
  const files = {
    Nocturne.bodyFamily: 'assets/fonts/Inter-Variable.ttf',
    Nocturne.arabicFamily: 'assets/fonts/ScheherazadeNew-Regular.ttf',
  };
  for (final entry in files.entries) {
    final bytes = await File(entry.value).readAsBytes();
    await (FontLoader(entry.key)
          ..addFont(Future.value(ByteData.view(bytes.buffer))))
        .load();
  }
}
