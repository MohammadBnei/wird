import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import '../../nav.dart';

/// Screen 3a — one root on its dial, and as deep a reading as the sources go.
class RootScreen extends StatelessWidget {
  const RootScreen({super.key, required this.db, required this.letters});

  final Database db;

  /// The root's letters joined, the way the corpus keys them.
  final String letters;

  @override
  Widget build(BuildContext context) =>
      UnbuiltScreen(id: '3a', name: 'Root word', subject: letters);
}
