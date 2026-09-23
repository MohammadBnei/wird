import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import '../../nav.dart';

/// Screen 1d — how much of the Qur'an has been understood, not merely read.
class ProgressScreen extends StatelessWidget {
  const ProgressScreen({super.key, required this.db});

  final Database db;

  @override
  Widget build(BuildContext context) => const UnbuiltScreen(
    id: '1d',
    name: 'Progress',
    subject: 'Ayas understood, prayers, and where you are in each sūra.',
  );
}
