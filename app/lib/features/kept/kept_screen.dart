import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import '../../nav.dart';

/// Screen 1e — the ayas, roots and notes the reader kept.
class KeptScreen extends StatelessWidget {
  const KeptScreen({super.key, required this.db});

  final Database db;

  @override
  Widget build(BuildContext context) => const UnbuiltScreen(
    id: '1e',
    name: 'Kept',
    subject: 'Ayas, roots and notes you kept.',
  );
}
