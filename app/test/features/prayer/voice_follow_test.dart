import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';
import 'package:sqflite/sqflite.dart';
import 'package:wird/data/mic.dart';
import 'package:wird/data/speech.dart';
import 'package:wird/features/prayer/prayer_cursor.dart';
import 'package:wird/features/prayer/prayer_voice.dart';
import 'package:wird/features/prayer/voice_follow.dart';

import '../../corpus.dart';
import '../../microphone.dart';

/// Ḥuṣarī reciting Al-ʿAlaq 1-5 — the same everyayah files the app plays —
/// heard by whisper-base-ar-quran in 4-second windows every 750 ms. The word
/// timings are the ones bundled in corpus.db, which is what lets "where the
/// reciter actually was" be read off the recording instead of guessed at.
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
    // Uthmani on the left, what whisper wrote for the same word on the right.
    expect(recitationKey('ٱلْإِنسَـٰنَ'), recitationKey('الْإِنْسَانَ'));
    expect(recitationKey('ٱقْرَأْ'), recitationKey('اقْرَأْ'));
    expect(recitationKey('ٱلَّذِى'), recitationKey('الَّذِي'));
    expect(recitationKey('بِٱسْمِ'), recitationKey('بِاسْمِ'));
  });

  test('silence and a hallucinated word leave the prayer where it is', () {
    // طه is what the recogniser returned for the pause between two ayas.
    final keys = recitationKeys(_recitation().words);
    for (final noise in ['', '   ', 'طه', 'Bismillah', '...']) {
      expect(locate(keys, 7, noise), isNull, reason: 'heard "$noise"');
    }
  });

  test('a word the reciter has not reached does not pull the prayer to it', () {
    final keys = recitationKeys(_recitation().words);
    expect(locate(keys, 1, 'خَلَقَ الْإِنْسَانَ')?.position, isNotNull);
    // قلم is a syllable of the fifteenth word, heard while the reciter is on
    // the second. A reciter does not cross thirteen words in a breath.
    expect(locate(keys, 1, 'قلم قلم'), isNull);
  });

  test('a repeated word advances to the near copy, never the far one', () {
    // خَلَقَ closes 96:1 and opens 96:2; ٱقْرَأْ opens 96:1 and again 96:3. A
    // matcher that took the later copy would jump the reader an aya ahead.
    final keys = recitationKeys(_recitation().words);
    expect(locate(keys, 3, 'الَّذِي خَلَقَ')?.position, 4);
    expect(locate(keys, 0, 'اقْرَأْ'), isNull);
  });

  test('a window from behind the cursor does not come back a reading on', () {
    // The reader brushed the go-on zone, so the prayer stands on word 8 while
    // the reciter is still finishing 5-7 and the buffered seconds still
    // describe them. Read straight through, word 7 is also position 27.
    final keys = recitationKeys(_recitation().words);
    expect(locate(keys, 8, 'خَلَقَ الْإِنْسَانَ مِنْ'), isNull);
  });

  test(
    'a cursor one word ahead of the reciter is not carried a reading on',
    () {
      // _onToTheNextAya lands on the first word of the next aya while the
      // reciter is still on the last of this one, so one word ahead is the
      // ordinary state after every tap, not an unlucky one.
      final keys = recitationKeys(_recitation().words);
      expect(locate(keys, 6, 'رَبِّكَ الَّذِي خَلَقَ'), isNull);
    },
  );

  test('a reciter who runs on into the next reading is still followed', () {
    // The case the wrap exists for, and the reason the reach is a distance
    // rather than the end of the reading: the next reading's first word is one
    // position on, not twenty.
    final keys = recitationKeys(_recitation().words);
    expect(locate(keys, 19, 'مَا لَمْ يَعْلَمْ اقْرَأْ')?.position, 20);
    expect(locate(keys, 19, 'لَمْ يَعْلَمْ اقْرَأْ بِاسْمِ')?.position, 21);
  });

  test(
    'real recitation never carries the prayer past where the reciter is',
    () {
      final grade = _grade(followHeard);
      // ignore: avoid_print
      print(
        'voice-follow, Ḥuṣarī on Al-ʿAlaq 1-5: ${grade.windows} windows, '
        '${grade.advances} advances of which ${grade.ahead} wrong, '
        '${grade.stood} stood still, in step with the reciter in '
        '${grade.inStep}, worst lag ${grade.worstLag} words.',
      );

      // The number that decides whether this may ever be on by default.
      expect(grade.ahead, 0, reason: grade.wrong.join('\n'));
      // A follower that never advances is safe and useless, so it has to have
      // walked the whole set and arrived at its last word.
      expect(grade.ended, _recitation().words.length - 1);
      expect(grade.worstLag, lessThanOrEqualTo(2));
      expect(grade.inStep, greaterThanOrEqualTo(grade.windows - 4));
    },
  );

  test(
    'a microphone taken away since Settings leaves nothing listening',
    () async {
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

      expect(
        await PrayerVoice.start(db, PrayerCursor(20), ['ٱقْرَأْ']),
        isNull,
      );
      expect(mic.opened, isEmpty);
    },
  );

  test('the recitation is easy enough that any matcher would score well on '
      'it', () {
    // The grading above is only worth reading if it can tell a matcher that
    // listens from one that does not. This is the one that does not: it walks
    // a word on every window, whatever it heard.
    final grade = _grade(
      (cursor, keys, heard) => cursor.follow(cursor.position + 1),
    );
    expect(grade.ahead, greaterThan(grade.windows ~/ 2));
    expect(grade.inStep, lessThan(10));
  });
}

/// Walks the whole recording through [advance] and counts what it did to the
/// prayer, against where the reciter actually was at each window.
({
  int windows,
  int advances,
  int ahead,
  int stood,
  int inStep,
  int worstLag,
  int ended,
  List<String> wrong,
})
_grade(void Function(PrayerCursor, List<String>, String) advance) {
  final recitation = _recitation();
  final keys = recitationKeys(recitation.words);
  final cursor = PrayerCursor(keys.length);

  /// Which word the recording is on at a given moment. Between two ayas the
  /// reciter is still on the last word of the one just finished.
  int recitingAt(int ms) {
    var word = 0;
    for (var i = 0; i < recitation.spans.length; i++) {
      if (recitation.spans[i].startMs <= ms) word = i;
    }
    return word;
  }

  var advances = 0, ahead = 0, stood = 0, inStep = 0, worstLag = 0;
  final wrong = <String>[];
  for (final window in recitation.windows) {
    final was = cursor.position;
    advance(cursor, keys, window.heard);
    final reciter = recitingAt(window.atMs);
    final lag = reciter - cursor.position;
    if (lag > worstLag) worstLag = lag;
    if (lag.abs() <= 1) inStep++;
    if (cursor.position == was) {
      stood++;
      continue;
    }
    advances++;
    // The window ends at atMs and describes the seconds before it, so a word
    // of lag is the recogniser being honest rather than the app being wrong.
    // Landing beyond the reciter is the failure that matters.
    if (lag < 0) {
      wrong.add(
        '${window.atMs}ms "${window.heard}" landed on ${cursor.position}, '
        'reciter was on $reciter',
      );
      ahead++;
    }
  }
  return (
    windows: recitation.windows.length,
    advances: advances,
    ahead: ahead,
    stood: stood,
    inStep: inStep,
    worstLag: worstLag,
    ended: cursor.position,
    wrong: wrong,
  );
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
