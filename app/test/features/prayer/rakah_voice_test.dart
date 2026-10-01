import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';
import 'package:wird/data/sets.dart';
import 'package:wird/data/speech.dart';
import 'package:wird/features/prayer/prayer_cursor.dart';
import 'package:wird/features/prayer/prayer_plan.dart';
import 'package:wird/features/prayer/prayer_voice.dart';

import '../../corpus.dart';
import '../../microphone.dart';
import 'sets.dart';

/// The voice across rakʿahs: one microphone and one model for the whole
/// prayer, pointed at each rakʿah in turn. The recogniser is a list of what
/// it would have written, one answer per batch of a loud reader.
void main() {
  final slice = heardChunk.inMilliseconds * heardSampleRate ~/ 1000;

  Float32List loud(int batches) {
    final audio = Float32List(batches * slice);
    for (var i = 0; i < audio.length; i++) {
      audio[i] = i.isEven ? 0.1 : -0.1;
    }
    return audio;
  }

  late List<StudyAya> fatiha;
  late StudySet asr;

  setUpAll(() async {
    RecordPlatform.instance = FakeMic();
    final db = await testCorpus();
    fatiha = (await setOf(db, [for (var a = 1; a <= 7; a++) 1000 + a])).ayas;
    asr = await alAsr(db);
  });

  /// A voice that has just finished rakʿah one and been pointed at rakʿah two,
  /// answering each batch with the next of [said].
  Future<({PrayerVoice voice, PrayerCursor second})> betweenRakahs(
    List<String> said,
  ) async {
    var n = 0;
    final first = rakahOf(fatiha, asr);
    final voice = await PrayerVoice.drain(
      PrayerCursor(29 + 13),
      first.heard,
      Float32List(0),
      hear: (_) async => (text: said[n++ % said.length], ended: false),
    );
    final next = rakahOf(fatiha, asr);
    final second = PrayerCursor(29 + 13);
    voice.follow(second, next.heard, unseenAt: next.basmalaAt);
    return (voice: voice, second: second);
  }

  test('praise said while bowing begins the next rakʿah', () async {
    for (final praise in [
      'الحمد لله',
      // The same, the way the recogniser spells a reader saying it.
      'لحَمدُلِللَااه',
      'رَببَناوَلَكَلحَمد',
      'ربنا ولك الحمد',
      'سمع الله لمن حمده ربنا ولك الحمد',
      'سبحان ربي العظيم',
    ]) {
      final r = await betweenRakahs([praise]);
      await r.voice.feed(loud(1));
      expect(r.second.at, 0, reason: praise);
      expect(r.second.sure, isFalse, reason: praise);
    }
  });

  test('reciting Al-Fātiḥa leaves the next rakʿah waiting', () async {
    // What the recogniser wrote for a reader at the end of 1:2, off
    // `fatiha_reader_heard`.
    final r = await betweenRakahs([
      'ااهِيَلرَحمَاانِرَحِۦۦۦۦم لحَمدُلِللَااهِرَببِلعَاالَمِۦۦۦۦن',
    ]);
    await r.voice.feed(loud(1));
    expect(r.second.at, 7);
    expect(r.second.sure, isTrue);
  });

  test('a basmala before the passage drags the reciter back to Al-Fātiḥa, or '
      'the passage after it lands on the wrong word', () async {
    final rakah = rakahOf(fatiha, asr);
    final cursor = PrayerCursor(29 + 13, at: 28);
    var n = 0;
    final said = ['بسم الله', 'الرحيم والعصر إن الإنسان'];
    final voice = await PrayerVoice.drain(
      cursor,
      rakah.heard,
      Float32List(0),
      hear: (_) async => (text: said[n++], ended: false),
      unseenAt: rakah.basmalaAt,
    );
    await voice.feed(loud(1));
    expect(cursor.at, 28, reason: 'the basmala moved the prayer');
    await voice.feed(loud(1));
    // Al-ʿAṣr 1 is word 29 on screen, and إن الإنسان are 103:2's first two.
    // Unmapped, the basmala's four words would put it at 33 or beyond.
    expect(cursor.at, inInclusiveRange(29, 31));
  });
}
