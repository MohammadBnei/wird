import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import 'root_screen.dart';

/// Screen 2b — the same root read as a spine: the dial taken away, every
/// derivative down the page. Screen 3a falls back to it on its own for a root
/// too large for the ring; this route is how a reader asks for it outright.
class RootSpineScreen extends StatelessWidget {
  const RootSpineScreen({super.key, required this.db, required this.letters});

  final Database db;
  final String letters;

  @override
  Widget build(BuildContext context) =>
      RootScreen(db: db, letters: letters, alwaysSpine: true);
}
