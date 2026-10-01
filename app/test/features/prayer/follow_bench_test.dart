import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:wird/data/sets.dart';
import 'package:wird/features/prayer/alignment.dart';
import 'package:wird/features/prayer/prayer_plan.dart';
import 'package:wird/features/prayer/voice_follow.dart';

import '../../corpus.dart';
import 'sets.dart';

/// The bench: every condition voice-follow has to survive, replayed through
/// `locate` in a few seconds and graded against the same requirements.
///
///   R1  the cursor never moves ahead of the reciter or back past where they are
///   R2  the cursor gets as far as the reciter got (`furthest`)
///   R3  a reciter who goes back is followed back (counted as `ahead`: windows
///       spent with the cursor in front of the reciter)
///   R4  speech that is not the set never moves the cursor
///   R5  the cursor keeps up: `behind` counts windows spent with the cursor
///       behind where the reciter surely is. Ratcheted per condition — a
///       change may lower a number, never raise it
///
/// Run: `fvm flutter test test/features/prayer/follow_bench_test.dart`. The
/// table it prints is the before/after a matcher change is judged on.

/// One answer of the recogniser, and where the reciter can be when it came:
/// no further than [hi], no earlier than [lo]. Either bound may be unknown.
typedef Window = ({String heard, int? lo, int? hi});

class Condition {
  Condition(
    this.name,
    this.words,
    this.windows, {
    int? reach,
    this.behind = 0,
    this.known,
  }) : reach = reach ?? words.length - 1;

  final String name;
  final List<String> words;
  final List<Window> windows;

  /// The furthest word the reciter says (R2). 0 for speech that is not the
  /// set, which must never move the cursor (R4).
  final int reach;

  /// The most windows the cursor may spend behind the reciter (R5).
  final int behind;

  /// A failure this condition is known to have, and why it is not fixed yet.
  /// The bench fails when it stops failing, so the note cannot outlive it.
  final String? known;
}

typedef Score = ({
  int windows,
  int moved,
  int wrong,
  int ahead,
  int behind,
  int maxLag,
  int furthest,
  int end,
  List<String> wrongs,
});

Score run(Condition c) {
  final set = Recitation(c.words);
  var at = 0, moved = 0, ahead = 0, behind = 0, maxLag = 0, furthest = 0;
  final wrongs = <String>[];
  for (final (i, w) in c.windows.indexed) {
    final found = locate(set, w.heard);
    if (found != null && found.word != at) {
      moved++;
      if ((w.hi != null && found.word > w.hi!) ||
          (w.lo != null && found.word < w.lo!)) {
        wrongs.add(
          '#$i "${w.heard}" → ${found.word}, reciter in '
          '[${w.lo}, ${w.hi}]',
        );
      }
      at = found.word;
      furthest = max(furthest, at);
    }
    if (w.hi != null && at > w.hi!) ahead++;
    if (w.lo != null && at < w.lo!) behind++;
    if (w.hi != null) maxLag = max(maxLag, w.hi! - at);
  }
  return (
    windows: c.windows.length,
    moved: moved,
    wrong: wrongs.length,
    ahead: ahead,
    behind: behind,
    maxLag: maxLag,
    furthest: furthest,
    end: at,
    wrongs: wrongs,
  );
}

/// A recogniser that hears exactly the muṣḥaf, a few letters at a time, one
/// utterance per aya with the previous aya carried in front, as `carry` does.
/// [script] is the order the reciter says the set's ayas in, each aya being
/// the indices of its words in the set — a repeat is an aya listed twice.
///
/// With [slips] > 0 each letter is misheard with that chance — swapped,
/// dropped or doubled — the way the recogniser spells a real voice.
List<Window> recite(
  List<String> words,
  List<List<int>> script, {
  double slips = 0,
  int seed = 1,
}) {
  final out = <Window>[];
  final random = Random(seed);
  var carried = '';
  for (final aya in script) {
    final said = StringBuffer();
    for (final w in aya) {
      final key = _slip(recitationKey(words[w]), slips, random);
      for (var cut = min(3, key.length); ; cut = min(cut + 3, key.length)) {
        out.add((
          heard: '$carried $said${key.substring(0, cut)}'.trim(),
          lo: w - 3,
          hi: w,
        ));
        if (cut == key.length) break;
      }
      said.write('$key ');
    }
    carried = said.toString().trim();
  }
  return out;
}

const _letters = 'ابتثجحخدذرزسشصضطظعغفقكلمنهوي';

String _slip(String key, double slips, Random random) {
  if (slips == 0) return key;
  final out = StringBuffer();
  for (final c in key.split('')) {
    if (random.nextDouble() >= slips) {
      out.write(c);
      continue;
    }
    switch (random.nextInt(3)) {
      case 0:
        out.write(_letters[random.nextInt(_letters.length)]);
      case 1:
        break;
      default:
        out.write('$c$c');
    }
  }
  return out.isEmpty ? key : out.toString();
}

/// Speech that is not the set: every window it makes must leave the cursor.
List<Window> notTheSet(List<String> said) {
  final out = <Window>[];
  var now = '';
  for (final w in said) {
    final key = recitationKey(w);
    for (var cut = min(3, key.length); ; cut = min(cut + 3, key.length)) {
      out.add((heard: '$now ${key.substring(0, cut)}'.trim(), lo: 0, hi: 0));
      if (cut == key.length) break;
    }
    now = '$now $key'.trim();
  }
  return out;
}

/// R5's ratchet: the windows behind the reciter each recitation was measured
/// at when the margin became per-set (ADR 0019). Lower one when a change earns
/// it; never raise one. A rakʿah spends one window behind by design: the
/// basmala before its passage is al-Fātiḥa's exact twin and is waited out.
const _behindAtMost = {
  'al-ʿAsr slips 1': 2,
  'al-ʿAsr slips 3': 3,
  'al-Kāfirūn slips 1': 2,
  'al-Kāfirūn slips 3': 12,
  'al-Ikhlāṣ slips 1': 2,
  'al-Ikhlāṣ slips 3': 2,
  'az-Zalzalah slips 1': 2,
  'az-Zalzalah slips 3': 2,
  'al-Qāriʿah slips 1': 2,
  'al-Qāriʿah slips 3': 10,
};

Map<String, dynamic> _fixture(String name) =>
    jsonDecode(File('test/fixtures/$name.json').readAsStringSync())
        as Map<String, dynamic>;

List<String> _words(List<StudyAya> ayas) => [
  for (final a in ayas)
    for (final w in a.words) w.text,
];

/// The ayas of a rakʿah as runs of indices into its heard words.
List<List<int>> _ayas(Rakah r) {
  final out = <List<int>>[];
  var i = 0;
  List<int> next(int n) => [for (var k = 0; k < n; k++) i++];
  for (final a in r.ayas.take(7)) {
    out.add(next(a.words.length));
  }
  if (r.basmalaAt >= 0) out.add(next(4));
  for (final a in r.ayas.skip(7)) {
    out.add(next(a.words.length));
  }
  return out;
}

void main() {
  late List<Condition> conditions;

  setUpAll(() async {
    final db = await testCorpus();
    final fatiha = (await setOf(db, [
      for (var a = 1; a <= 7; a++) 1000 + a,
    ])).ayas;
    final fatihaWords = _words(fatiha);
    Future<Rakah> rakah(int sura, int ayas) async => rakahOf(
      fatiha,
      await setOf(db, [for (var a = 1; a <= ayas; a++) sura * 1000 + a]),
    );

    conditions = [];

    // Studio reciters on al-Fātiḥa: aya bounds in the audio say how far the
    // reciter can have got.
    for (final reciter in ['Alafasy', 'Abdul', 'Minshawy']) {
      final f = _fixture('fatiha_${reciter}_heard');
      final bounds = (f['ayas'] as List).cast<Map<String, dynamic>>();
      int hi(int ms) {
        var words = 0;
        for (var i = 0; i < bounds.length; i++) {
          words += fatiha[i].words.length;
          if ((bounds[i]['endMs'] as int) >= ms) break;
        }
        return words - 1;
      }

      conditions.add(
        Condition('$reciter 1:1-7', fatihaWords, [
          for (final w in (f['windows'] as List).cast<Map<String, dynamic>>())
            (heard: w['heard'] as String, lo: null, hi: hi(w['atMs'] as int)),
        ]),
      );
    }

    // Ḥuṣarī on al-ʿAlaq, timed word by word.
    {
      final f = _fixture('alaq_husari_heard');
      final timed = (f['words'] as List).cast<Map<String, dynamic>>();
      final words = _words(
        (await setOf(db, [for (var a = 1; a <= 5; a++) 96000 + a])).ayas,
      );
      expect(words.length, timed.length, reason: 'fixture and corpus differ');
      int hi(int ms) =>
          max(0, timed.lastIndexWhere((w) => (w['startMs'] as int) <= ms));
      conditions.add(
        Condition('Husari 96:1-5', words, [
          for (final w in (f['windows'] as List).cast<Map<String, dynamic>>())
            (heard: w['heard'] as String, lo: null, hi: hi(w['atMs'] as int)),
        ]),
      );
    }

    // The owner into Wird's own microphone, and the walk-two trail: the set
    // the screen showed is 1:1-5, and nothing says where the reader was.
    final fiveAyas = fatihaWords.take(17).toList();
    conditions.add(
      Condition('owner 1:1-5', fiveAyas, [
        for (final w
            in (_fixture('fatiha_reader_heard')['windows'] as List)
                .cast<Map<String, dynamic>>())
          (heard: w['heard'] as String, lo: null, hi: null),
      ]),
    );
    // The reader got as far as 1:3 (word 9) by 29.5 s, then began again
    // because the screen had not followed. Where they surely were, read off
    // what the recogniser wrote, with a word or two of slack: past the
    // basmala once al-Ḥamd is under way, past al-Ḥamd's opening once 1:3 is.
    int? surely(double s) => switch (s) {
      >= 22.8 && < 23.8 => 3,
      >= 23.8 && < 28.6 => 4,
      >= 28.6 && < 31.0 => 6,
      >= 52.1 => 4,
      _ => null,
    };
    conditions.add(
      Condition('mac trail 1:1-5', fiveAyas, reach: 9, behind: 0, [
        for (final line in File(
          'test/fixtures/fatiha_macos_trail.txt',
        ).readAsLinesSync())
          if (RegExp(r'^([\d.]+)s\s+heard\s+(.*?) \|').firstMatch(line)
              case final m?)
            (heard: m[2]!, lo: surely(double.parse(m[1]!)), hi: null),
      ]),
    );

    // Perfect recitations of real rakʿahs, the unseen basmala included.
    for (final (name, sura, n) in [
      ('al-ʿAsr', 103, 3),
      ('al-Kāfirūn', 109, 6),
      ('al-Ikhlāṣ', 112, 4),
      ('az-Zalzalah', 99, 8),
      ('al-Qāriʿah', 101, 11),
    ]) {
      final r = await rakah(sura, n);
      conditions.add(
        Condition(
          'rakah + $name',
          r.heard,
          recite(r.heard, _ayas(r)),
          behind: 1,
        ),
      );
      // The same, heard the way the recogniser hears a real voice.
      for (final seed in [1, 2, 3]) {
        conditions.add(
          Condition(
            '$name slips $seed',
            behind: _behindAtMost['$name slips $seed'] ?? 1,
            r.heard,
            recite(r.heard, _ayas(r), slips: 0.15, seed: seed),
          ),
        );
      }
    }

    {
      final r = await rakah(103, 3);
      final a = _ayas(r);
      // A reciter who repeats 1:2 after 1:4, then carries on.
      conditions.add(
        Condition(
          'repeat 1:2',
          r.heard,
          recite(r.heard, [...a.take(4), a[1], ...a.skip(4)]),
          known:
              'R1: the aya just finished is carried in front of the first '
              'letters of the repeat, and the two read as the word after it',
        ),
      );
      // One word of 1:5 skipped.
      conditions.add(
        Condition(
          'word dropped',
          r.heard,
          recite(r.heard, [
            for (final (i, aya) in a.indexed)
              i == 4 ? aya.skip(1).toList() : aya,
          ]),
          behind: 1,
        ),
      );
      // Speech that is not the set: al-Ikhlāṣ without its basmala, then the
      // bowing praise, said against a rakʿah of al-ʿAsr.
      final ikhlas = _words(
        (await setOf(db, [for (var a = 1; a <= 4; a++) 112000 + a])).ayas,
      );
      conditions.add(
        Condition('another sūra', r.heard, notTheSet(ikhlas), reach: 0),
      );
      conditions.add(
        Condition(
          'bowing praise',
          r.heard,
          notTheSet(
            'سبحان ربي العظيم سمع الله لمن حمده ربنا ولك الحمد'.split(' '),
          ),
          reach: 0,
        ),
      );
    }
  });

  test('the bench', () {
    final rows = <String>[
      'condition            windows  moved  wrong  ahead behind  maxLag  '
          'furthest/reach',
    ];
    final failures = <String>[];
    for (final c in conditions) {
      final s = run(c);
      rows.add(
        '${c.name.padRight(20)} ${'${s.windows}'.padLeft(7)} '
        '${'${s.moved}'.padLeft(6)} ${'${s.wrong}'.padLeft(6)} '
        '${'${s.ahead}'.padLeft(6)} ${'${s.behind}'.padLeft(6)} '
        '${'${s.maxLag}'.padLeft(7)}  '
        '${s.furthest}/${c.reach}${c.known == null ? '' : '  known'}',
      );
      final failed = [
        for (final w in s.wrongs) 'R1: $w',
        if (c.reach == 0 && s.furthest != 0) 'R4: moved to ${s.furthest}',
        // Within the last few words: a short last word may never be named.
        if (s.furthest < c.reach - 3)
          'R2: got to ${s.furthest}, the reciter to ${c.reach}',
        if (s.behind > c.behind)
          'R5: ${s.behind} windows behind the reciter, at most ${c.behind}',
      ];
      if (c.known == null) {
        failures.addAll([for (final f in failed) '${c.name} $f']);
      } else if (failed.isEmpty) {
        failures.add('${c.name} passes now: drop `known`');
      }
    }
    // ignore: avoid_print
    print(rows.join('\n'));
    expect(failures, isEmpty, reason: failures.join('\n'));
  });
}
