import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import '../../data/sets.dart';
import '../../nav.dart';

/// Screen 1b — the set recited inside the prayer.
class PrayerScreen extends StatelessWidget {
  const PrayerScreen({super.key, required this.db, required this.set});

  final Database db;
  final StudySet set;

  @override
  Widget build(BuildContext context) =>
      UnbuiltScreen(id: '1b', name: 'In the prayer', subject: set.title);
}
