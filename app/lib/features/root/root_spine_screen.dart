import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import '../../nav.dart';

/// Screen 2b — the same root read as a spine, for roots with too many
/// derivatives for a dial.
class RootSpineScreen extends StatelessWidget {
  const RootSpineScreen({super.key, required this.db, required this.letters});

  final Database db;
  final String letters;

  @override
  Widget build(BuildContext context) =>
      UnbuiltScreen(id: '2b', name: 'Root spine', subject: letters);
}
