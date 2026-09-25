import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';
import 'package:sqflite/sqflite.dart';
import 'package:wird/data/mic.dart';
import 'package:wird/data/speech.dart';
import 'package:wird/features/prayer/alignment.dart';
import 'package:wird/features/prayer/prayer_cursor.dart';
import 'package:wird/features/prayer/prayer_voice.dart';
import 'package:wird/features/prayer/voice_follow.dart';

import '../../corpus.dart';
import '../../microphone.dart';

/// Ḥuṣarī reciting Al-ʿAlaq 1-5 — the same everyayah files the app plays —
/// heard by the streaming transducer the app ships, fed as the phone feeds it.
/// The word timings are the ones bundled in corpus.db, which is what lets
/// "where the reciter actually was" be read off the recording instead of
/// guessed at.
({
  List<String> words,
  List<({int startMs, int endMs})> spans,
  List<({int atMs, String heard})> windows,
})
_recitation() {
  final json = jsonDecode(
    File('test/fixtures/alaq_husari_heard.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final words = (json['words'] as List).cast<Map<String, dynamic>>();
  return (
    words: [for (final w in words) w['text'] as String],
    spans: [
      for (final w in words)
        (startMs: w['startMs'] as int, endMs: w['endMs'] as int),
    ],
    windows: [
      for (final w in (json['windows'] as List).cast<Map<String, dynamic>>())
        (atMs: w['atMs'] as int, heard: w['heard'] as String),
    ],
  );
}

void main() {
  test('the muṣḥaf and the recogniser spell one word one way', () {
    // Uthmani on the left, what a recogniser wrote for the same word on the
    // right. Both sides have to arrive at the same letters or nothing below
    // can work.
    expect(recitationKey('ٱلْإِنسَـٰنَ'), recitationKey('الإنسان'));
    expect(recitationKey('ٱقْرَأْ'), recitationKey('اقرا'));
    // The dagger alif is spelled out, so the muṣḥaf's ٱلرَّحْمَـٰنِ and a
    // recogniser's الرحمن differ by the one letter the muṣḥaf writes above the
    // line. That is a percentage, not a mismatch, and _alike is what absorbs
    // it — which is why the comparison is over letters and not over words.
    expect(recitationKey('ٱلرَّحْمَـٰنِ'), 'الرحمان');
    expect(recitationKey('الرحمن'), 'الرحمن');
  });

  test('silence and a hallucinated word carry the prayer somewhere', () {
    final set = Recitation(_recitation().words);
    expect(locate(set, ''), isNull);
    expect(locate(set, '   '), isNull);
    // What the recogniser answered a pause between ayas with, taken from the
    // owner's own recorded prayer.
    expect(locate(set, 'طه'), isNull);
    expect(locate(set, 'اللهم صل على محمد'), isNull);
  });

  test('a phrase the set says twice is guessed at instead of refused', () {
    // خَلَقَ closes 96:1 and opens 96:2; ٱقْرَأْ opens 96:1 and again 96:3. A
    // window naming two places equally well names neither: the reciter carries
    // on, the next window is unambiguous, and the screen catches up. Lateness
    // is the error this is allowed to make, because it fixes itself and a
    // wrong place does not.
    final set = Recitation(_recitation().words);
    expect(locate(set, 'اقْرَأْ'), isNull);
    expect(locate(set, 'خَلَقَ'), isNull);
    // Not only exact repeats. This sūra says ٱلَّذِى خَلَقَ and ٱلَّذِى عَلَّمَ,
    // seven letters differing in two, and a window holding one of them cannot
    // honestly say which. Refusing is the whole of the guard: moving would put
    // the screen three ayas from the reciter, and nobody can reach the phone
    // to bring it back.
    expect(locate(set, 'الَّذِي خَلَقَ'), isNull);
    // Said with something around it that the sūra says only once, it moves.
    expect(locate(set, 'مِنْ عَلَقٍ')?.word, 8);
    expect(locate(set, 'وَرَبُّكَ الْأَكْرَمُ')?.word, 11);
  });

  test('real recitation carries the prayer somewhere the reciter is not', () {
    final recitation = _recitation();
    final set = Recitation(recitation.words);
    final cursor = PrayerCursor(recitation.words.length);

    int recitingAt(int ms) {
      var word = 0;
      for (var i = 0; i < recitation.spans.length; i++) {
        if (recitation.spans[i].startMs <= ms) word = i;
      }
      return word;
    }

    var moves = 0, inStep = 0, worst = 0;
    final wrong = <String>[];
    for (final window in recitation.windows) {
      final was = cursor.at;
      final at = locate(set, window.heard);
      if (at != null) cursor.moveTo(at.word);
      if (cursor.at != was) moves++;
      final reciter = recitingAt(window.atMs);
      // Distance, not direction. The cursor may move either way now, so the
      // question is how far from the reciter it is, not which side of them.
      final off = (reciter - cursor.at).abs();
      if (off > worst) worst = off;
      if (off <= 1) inStep++;
      if (cursor.at > reciter) {
        wrong.add(
          '${window.atMs}ms "${window.heard}" landed on ${cursor.at}, '
          'the reciter was on $reciter',
        );
      }
    }

    // ignore: avoid_print
    print(
      'voice-follow, Ḥuṣarī on Al-ʿAlaq 1-5: ${recitation.windows.length} '
      'windows, $moves moves, ${wrong.length} ahead of the reciter, in step '
      'with them in $inStep, worst $worst words away.',
    );

    // The number that decides whether this may ever be on by default: the
    // screen must never be somewhere the reciter has not reached.
    expect(wrong, isEmpty, reason: wrong.join('\n'));
    // A follower that never moves is safe and useless, so it has to have
    // walked the set and arrived at its last word.
    expect(cursor.at, recitation.words.length - 1);
    expect(worst, lessThanOrEqualTo(2));
    expect(
      inStep,
      greaterThanOrEqualTo((recitation.windows.length * 0.85).round()),
    );
  });

  test('a microphone taken away since Settings leaves nothing listening', () async {
    // Granted in Settings and revoked in the OS afterwards, which is the one
    // case `request: false` is written for. By the time the recorder says no
    // the recogniser is open and nothing upstream has been handed it, so an
    // answer of null that walked out past it would leave it behind for the
    // length of the app.
    final db = await testCorpus();
    await setMicPermission(db, MicPermission.granted);
    await _aModelOnDisk();
    final mic = FakeMic(allows: false);
    RecordPlatform.instance = mic;

    expect(await PrayerVoice.start(db, PrayerCursor(20), ['ٱقْرَأْ']), isNull);
    expect(mic.opened, isEmpty);
  });

  test('the recitation is easy enough that any matcher would score well on '
      'it', () {
    // The grading above is only worth reading if it can tell a matcher that
    // listens from one that does not. This is the one that does not: it walks
    // a word on every window, whatever it heard.
    final recitation = _recitation();
    final cursor = PrayerCursor(recitation.words.length);
    var ahead = 0, inStep = 0;
    for (final window in recitation.windows) {
      cursor.moveTo(cursor.at + 1);
      var reciter = 0;
      for (var i = 0; i < recitation.spans.length; i++) {
        if (recitation.spans[i].startMs <= window.atMs) reciter = i;
      }
      if (cursor.at > reciter) ahead++;
      if ((reciter - cursor.at).abs() <= 1) inStep++;
    }
    expect(ahead, greaterThan(recitation.windows.length ~/ 2));
    expect(inStep, lessThan(recitation.windows.length ~/ 4));
  });
}

/// Enough of a model for [PrayerVoice.start] to get as far as the microphone.
/// The parts are not weights and the recogniser's isolate says so once it has
/// handed back the port — which is after `start` has the recogniser, which is
/// the point: this is the state the prayer is in when the microphone answers.
Future<void> _aModelOnDisk() async {
  final model = await VoiceModel.beside(await getDatabasesPath());
  for (final part in voiceModelParts) {
    model.fileFor(part).writeAsStringSync('');
  }
  addTearDown(() => model.dir.delete(recursive: true));
}
