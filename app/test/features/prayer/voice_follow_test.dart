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
    // Uthmani on the left, what the recogniser wrote for the same word on the
    // right — its own transcription of Ḥuṣarī, not an invented spelling. Both
    // sides have to arrive at the same letters or nothing below can work.
    //
    // Each of these is a whole class of difference. The nūn of al-insān is
    // nasalised and held, so it comes back as a mark repeated; the hamza of
    // iqraʾ is bare where the muṣḥaf seats it, and its qāf carries a qalqala
    // that is the qāf echoing rather than a letter; the alif of the article is
    // written in the muṣḥaf and elided in connected recitation, which is
    // precisely what the waṣl sign over it says.
    expect(recitationKey('ٱلْإِنسَـٰنَ'), recitationKey('لءِںںںسَاانَ'));
    // The one that does not close, and it is the waṣl: ٱقْرَأْ opens the sūra
    // so its alif is said, and the fold drops every waṣl alif because in
    // connected recitation it is skipped. A letter on the first word of an
    // utterance, which is a percentage of a window rather than a verdict on
    // it — see the note in recitationKey for what was measured.
    expect(recitationKey('ٱقْرَأْ'), 'قرا');
    expect(recitationKey('ءِقڇرَء'), 'اقرا');
    expect(recitationKey('بِٱلْقَلَمِ'), recitationKey('بِلقَلَم'));
    expect(recitationKey('عَلَّمَ'), recitationKey('عَللَمَ'));
    // And the dagger alif, which the muṣḥaf writes above the line and the
    // reciter holds: ar-Raḥmān is four letters longer said than written.
    // The article's own lām stays; what the recogniser wrote here is the
    // word as it sounds inside the basmala, where the lām has run into the rāʾ.
    expect(
      recitationKey('ٱلرَّحْمَـٰنِ').substring(1),
      recitationKey('رَحمَاانِ'),
    );
  });

  test('silence and a hallucinated word carry the prayer somewhere', () {
    final set = Recitation(_recitation().words);
    expect(locate(set, ''), isNull);
    expect(locate(set, '   '), isNull);
    // What the recogniser answered a pause between ayas with, taken from the
    // owner's own recorded prayer, and the duʿāʾ a reader says inside a prayer
    // that is not in the set at all.
    expect(locate(set, 'طه'), isNull);
    expect(locate(set, 'ءَللَهُممَصَللِعَلَاامُحَممَد'), isNull);
  });

  test('a phrase the set says twice is guessed at instead of refused', () {
    // خَلَقَ closes 96:1 and opens 96:2; ٱقْرَأْ opens 96:1 and again 96:3. A
    // window naming two places equally well names neither: the reciter carries
    // on, the next window is unambiguous, and the screen catches up. Lateness
    // is the error this is allowed to make, because it fixes itself and a
    // wrong place does not.
    final set = Recitation(_recitation().words);
    expect(locate(set, 'ءِقڇرَء'), isNull);
    expect(locate(set, 'خَلَقڇ'), isNull);
    // Said with something around it that the sūra says only once, it moves —
    // and ٱلَّذِى, which the sūra says twice, is one of those things once the
    // word after it is in the window too.
    expect(locate(set, 'للَذِۦۦخَلَقڇ')?.word, 4);
    expect(locate(set, 'مِنعَلَقڇ')?.word, 8);
    expect(locate(set, 'وَرَببُكَلءَكرَم')?.word, 11);
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
    // Distance, and only ever behind. Three words is one excursion, at the
    // very end of the sūra where عَلَّمَ ٱلْإِنسَـٰنَ repeats the words of 96:2 and
    // the matcher is right to want another window before it commits.
    expect(worst, lessThanOrEqualTo(3));
    expect(
      inStep,
      greaterThanOrEqualTo((recitation.windows.length * 0.85).round()),
    );
  });

  test('a microphone taken away since Settings leaves nothing listening', () async {
    // Granted in Settings and revoked in the OS afterwards, which is the one
    // case `request: false` is written for.
    //
    // UNTIL THE MICROPHONE WAS OPENED FIRST, THIS PASSED VACUOUSLY. The model
    // files below are empty, so `Recogniser.open` could not build a recogniser
    // and `start` returned before `AudioRecorder` was ever constructed:
    // `hasPermission` was never reached and `opened` was empty because nothing
    // had opened. Now the recorder IS built, and is asked, and says no — so
    // `opened` being empty is the disposal doing its job rather than the code
    // never arriving.
    //
    // It is also the one order in which `FakeMic` can carry this at all: the
    // throw lands before `_listen()`, and `startStream` is not overridden, so a
    // test that reached the stream would fail on `noSuchMethod` instead. The
    // ordering itself — that the audio before the model loads is kept — is
    // device evidence, off the trail's two note lines. Nothing here proves it.
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
