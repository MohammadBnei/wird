import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import 'data/db.dart';
import 'features/study/study_screen.dart';
import 'theme/nocturne.dart';

void main() => runApp(const WirdApp());

class WirdApp extends StatefulWidget {
  const WirdApp({super.key});

  @override
  State<WirdApp> createState() => _WirdAppState();
}

class _WirdAppState extends State<WirdApp> {
  /// First launch copies the 24 MB corpus out of the bundle, so the first
  /// screen waits on a file copy rather than on a network call.
  late final Future<Database> _db = openWird();

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Wird',
    theme: nocturneTheme(),
    home: FutureBuilder<Database>(
      future: _db,
      builder: (context, snapshot) => switch (snapshot) {
        AsyncSnapshot(hasData: true, :final data?) => StudyScreen(db: data),
        AsyncSnapshot(hasError: true, :final error?) => Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('The corpus would not open.\n\n$error'),
            ),
          ),
        ),
        _ => const Scaffold(body: SizedBox.shrink()),
      },
    ),
  );
}
