import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import '../../nav.dart';

/// Screen 1c — one aya, its sources side by side, on a tablet.
class DeepDiveScreen extends StatelessWidget {
  const DeepDiveScreen({
    super.key,
    required this.db,
    required this.ayahId,
    required this.letters,
  });

  final Database db;

  /// surah * 1000 + aya, the corpus's own key.
  final int ayahId;

  /// The root lit inside that aya.
  final String letters;

  @override
  Widget build(BuildContext context) => UnbuiltScreen(
    id: '1c',
    name: 'Deep dive',
    subject: '${ayahId ~/ 1000}:${ayahId % 1000} · $letters',
  );
}
