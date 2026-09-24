import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import 'app.dart';
import 'data/db.dart';
import 'data/flush.dart';
import 'nav.dart';
import 'theme/nocturne.dart';

void main() => runApp(const WirdApp());

/// What the app needs before it can route anywhere: the corpus, what the
/// reader has already chosen, and the thing that carries their queue to the
/// server when the app comes back to the foreground.
typedef Bootstrap = ({Database db, Prefs prefs, Flusher flusher});

Future<Bootstrap> _open(Future<Database> corpus) async {
  final db = await corpus;
  return (db: db, prefs: await Prefs.read(db), flusher: flusherFor(db));
}

class WirdApp extends StatefulWidget {
  const WirdApp({super.key, this.corpus});

  /// The corpus, already open. Supplied by the test that has to prove the
  /// frame shown while it opens hands over to the navigator without taking
  /// the app down.
  final Future<Database>? corpus;

  @override
  State<WirdApp> createState() => _WirdAppState();
}

class _WirdAppState extends State<WirdApp> {
  /// First launch copies the 24 MB corpus out of the bundle, so the first
  /// screen waits on a file copy rather than on a network call.
  late final Future<Bootstrap> _ready = _open(widget.corpus ?? openWird());

  @override
  Widget build(BuildContext context) => FutureBuilder<Bootstrap>(
    future: _ready,
    builder: (context, snapshot) => switch (snapshot) {
      AsyncSnapshot(hasData: true, :final data?) => wirdApp(
        data.db,
        prefs: data.prefs,
        flusher: data.flusher,
      ),
      AsyncSnapshot(hasError: true, :final error?) => _beforeTheCorpus(
        Text('The corpus would not open.\n\n$error'),
      ),
      _ => _beforeTheCorpus(const SizedBox.shrink()),
    },
  );

  /// Every screen reads the corpus, so until it opens there is nothing to
  /// route to and these frames are a bare app rather than the navigator.
  Widget _beforeTheCorpus(Widget body) => MaterialApp(
    // Keyed apart from the navigator's app: without that, Flutter updates one
    // MaterialApp into the other and the route built around this `home` is
    // rebuilt against an app that no longer has one.
    key: const ValueKey('opening the corpus'),
    title: 'Wird',
    theme: nocturneTheme(),
    home: Scaffold(
      body: Center(
        child: Padding(padding: const EdgeInsets.all(24), child: body),
      ),
    ),
  );
}
