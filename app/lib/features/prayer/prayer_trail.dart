import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// What happened during one prayer, and why, written down as it happens.
///
/// A prayer cannot be watched. The phone is on the floor, the reader is
/// standing and kneeling, and whatever the screen did wrong is over by the
/// time anyone can ask about it — which is how eight builds reached a reader
/// with nobody able to say what their phone had done. This is the record that
/// answers afterwards.
///
/// One prayer per file: opening a prayer truncates it. That is the whole of
/// the size policy, and it is enough — the question is always about the prayer
/// just prayed, and a trail that grew forever would be a disk leak on a phone
/// for the sake of a question nobody asks.
///
/// **Nothing here may fail in front of someone praying.** Every path swallows
/// what it catches and carries on; a prayer is not interrupted so that its
/// diary can be kept.
class PrayerTrail {
  PrayerTrail._(this._sink, this._began, [this._tape]);

  final IOSink? _sink;

  /// Debug builds only: every sample handed to the recogniser, as raw 32-bit
  /// floats at its sample rate, beside the trail. What the recogniser was
  /// given can then be replayed through it off the device, rather than
  /// guessed at from what it answered.
  final IOSink? _tape;
  final DateTime _began;

  /// The trail beside the database, truncated. Answers a trail that writes
  /// nowhere if the file cannot be opened, so a caller never has to ask.
  static Future<PrayerTrail> beside(String databasesPath) async {
    try {
      final file = File('$databasesPath/prayer-trail.log');
      final sink = file.openWrite();
      final tape = kDebugMode
          ? File('$databasesPath/prayer-audio.f32').openWrite()
          : null;
      final trail = PrayerTrail._(sink, DateTime.now(), tape);
      trail.note('trail', DateTime.now().toIso8601String());
      return trail;
    } on Object {
      return PrayerTrail._(null, DateTime.now());
    }
  }

  /// A trail that keeps nothing, for tests and for callers with nowhere to
  /// write.
  factory PrayerTrail.none() => PrayerTrail._(null, DateTime.now());

  /// One line, stamped with how far into the prayer it happened — which is
  /// the only clock that matters when reading this back.
  void note(String what, String detail) {
    final sink = _sink;
    if (sink == null) return;
    try {
      final at = DateTime.now().difference(_began).inMilliseconds / 1000;
      sink.writeln('${at.toStringAsFixed(1)}s  $what  $detail');
    } on Object {
      // A prayer is not interrupted so that its diary can be kept.
    }
  }

  void tape(Float32List samples) {
    try {
      _tape?.add(
        samples.buffer.asUint8List(
          samples.offsetInBytes,
          samples.lengthInBytes,
        ),
      );
    } on Object {
      // As with the trail: never at the prayer's expense.
    }
  }

  Future<void> close() async {
    try {
      await _tape?.flush();
      await _tape?.close();
      await _sink?.flush();
      await _sink?.close();
    } on Object {
      // Nothing to do about it, and nothing worth failing an exit over.
    }
  }
}
