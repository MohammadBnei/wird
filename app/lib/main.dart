import 'package:flutter/material.dart';

import 'gallery.dart';
import 'theme/nocturne.dart';

void main() => runApp(const WirdApp());

class WirdApp extends StatelessWidget {
  const WirdApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Wird',
    theme: nocturneTheme(),
    // The gallery is the only screen built so far; the reading, prayer and
    // root screens replace it as they land.
    home: const NocturneGallery(),
  );
}
