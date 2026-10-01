import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wird/l10n/app_localizations.dart';
import 'package:wird/features/study/word_row.dart';
import 'package:wird/data/db.dart';
import 'package:wird/data/mic.dart';
import 'package:wird/data/sets.dart';
import 'package:wird/features/prayer/prayer_cursor.dart';
import 'package:wird/features/prayer/prayer_plan.dart';
import 'package:wird/features/prayer/prayer_screen.dart';
import 'package:wird/theme/nocturne.dart';

import '../../corpus.dart';
import '../../microphone.dart';
import 'sets.dart';

/// A reader who asked to be followed by voice, with no pace behind it: the
/// text moves only when it is told to, so a test is not racing a timer.
const voiceNoPace = (
  preset: null,
  rakahs: 1,
  voice: true,
  pace: false,
  wpm: 40,
  gloss: true,
  around: true,
  arabicSize: 52.0,
);

/// The phone's own screen, and whether the prayer left it awake.
class Phone {
  bool awake = false;

  Future<void> keepAwake({required bool enable}) async {
    awake = enable;
  }
}

Future<void> _noWakelockHere({required bool enable}) async {
  throw StateError('this device will not hold the screen open');
}

Future<void> pumpPrayer(
  WidgetTester tester, {
  required Database db,
  required StudySet set,
  required Future<void> Function({required bool enable}) wakelock,
  PrayerCursor? cursor,
  PrayerPrefs prefs = voiceNoPace,
  PrayerPlan? plan,
  List<StudyAya> fatiha = const [],
  PrayerOutcome? outcome,
}) async {
  tester.view.physicalSize = const Size(402, 874);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: nocturneTheme(),
      // The delegates the app has, so the prayer can read its strings the way
      // it will in the app rather than throwing on a null AppLocalizations.
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => PrayerScreen(
                  db: db,
                  // The set alone, one rakʿah of it: what these tests pin is
                  // how the screen moves through ayas, not Al-Fātiḥa.
                  plan: plan ?? PrayerPlan(rakahs: 1, first: set),
                  fatiha: fatiha,
                  prefs: prefs,
                  outcome: outcome,
                  cursor: cursor,
                  wakelock: wakelock,
                ),
              ),
            ),
            child: const Text('the set'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('the set'));
  await tester.pumpAndSettle();
}

/// The word the screen says is being recited: the one carrying the glow.
/// Whether the screen is pointing at no word at all, which is how a prayer
/// opens: the aya stands lit and the word inside it waits to be earned.
bool noWordIsLit(WidgetTester tester) {
  for (final text in tester.widgetList<Text>(find.byType(Text))) {
    if (text.key is WordKey && text.style?.shadows != null) return false;
  }
  return true;
}

int litWord(WidgetTester tester) {
  for (final text in tester.widgetList<Text>(find.byType(Text))) {
    if (text.key is ValueKey<int> && text.style?.shadows != null) {
      return (text.key! as ValueKey<int>).value;
    }
  }
  fail('no word on the screen is lit as the one being recited');
}

double _opacityOf(WidgetTester tester, Finder finder) =>
    tester.widget<Text>(finder).style!.color!.a;

/// A tap, and the turn it starts.
///
/// The aya arriving is animated now, and an AnimatedSwitcher holds both the
/// one leaving and the one arriving while it runs — so a single pump finds
/// the aya the reader has just left and reads it as the one they are on.
/// Settling is not politeness here, it is the difference between asking what
/// is on screen and asking what was.
Future<void> tapOn(WidgetTester tester, Key zone, {int times = 1}) async {
  for (var i = 0; i < times; i++) {
    await tester.tap(find.byKey(zone));
    await tester.pumpAndSettle();
  }
}

void main() {
  late Database db;
  late StudySet set;

  setUp(() async {
    db = await testCorpus();
    set = await alAsr(db);
  });

  testWidgets('the phone goes dark in the middle of the prayer, because '
      'nothing asked its screen to stay awake', (tester) async {
    final phone = Phone();
    await pumpPrayer(tester, db: db, set: set, wakelock: phone.keepAwake);
    expect(phone.awake, isTrue);
  });

  testWidgets('the screen is still held awake long after the prayer ended, '
      'burning the battery for the rest of the day', (tester) async {
    final phone = Phone();
    await pumpPrayer(tester, db: db, set: set, wakelock: phone.keepAwake);
    await tester.tap(find.text('Exit'));
    await tester.pumpAndSettle();
    expect(phone.awake, isFalse);
  });

  testWidgets('leaving the prayer strands the reader on it instead of '
      'putting them back on the set', (tester) async {
    await pumpPrayer(tester, db: db, set: set, wakelock: Phone().keepAwake);
    expect(find.text('the set'), findsNothing);
    await tester.tap(find.text('Exit'));
    await tester.pumpAndSettle();
    expect(find.text('the set'), findsOneWidget);
  });

  testWidgets('a tap moves the prayer on by one word, so a reader with no '
      'microphone taps their way through a set word by word', (tester) async {
    await pumpPrayer(tester, db: db, set: set, wakelock: Phone().keepAwake);
    // Nothing is singled out yet: a prayer opens on the first word of the set
    // without anybody having said it, and pointing at a word nobody has
    // recited is the screen claiming to know something.
    expect(
      noWordIsLit(tester),
      isTrue,
      reason:
          'the screen pointed at a word before the reader had opened '
          'their mouth',
    );
    // 103:2 runs four words and 103:3 runs nine, so a tap that lands on the
    // first word of each of them is carrying an aya and not a word.
    await tapOn(tester, PrayerScreen.nextZone);
    expect(litWord(tester), 103002001);
    await tapOn(tester, PrayerScreen.nextZone);
    expect(litWord(tester), 103003001);
  });

  testWidgets('a reader who brushed the field and skipped an aya cannot get '
      'back to it', (tester) async {
    await pumpPrayer(tester, db: db, set: set, wakelock: Phone().keepAwake);
    await tapOn(tester, PrayerScreen.nextZone, times: 2);
    expect(litWord(tester), 103003001);
    await tapOn(tester, PrayerScreen.backZone);
    expect(litWord(tester), 103002001);
  });

  testWidgets('a reader whose screen ran ahead inside an aya is thrown back '
      'past the start of it', (tester) async {
    await pumpPrayer(
      tester,
      db: db,
      set: set,
      wakelock: Phone().keepAwake,
      // Where a voice being followed leaves the cursor: three words into
      // 103:3, which no tap of the reader's could have reached.
      cursor: PrayerCursor(14, at: 7),
    );
    expect(litWord(tester), 103003003);
    await tapOn(tester, PrayerScreen.backZone);
    expect(litWord(tester), 103003001);
    await tapOn(tester, PrayerScreen.backZone);
    expect(litWord(tester), 103002001);
  });

  testWidgets('the ayas around the one being recited are as loud as it is, '
      'so the reader cannot tell where they are', (tester) async {
    await pumpPrayer(tester, db: db, set: set, wakelock: Phone().keepAwake);
    await tapOn(tester, PrayerScreen.nextZone);
    final recited = _opacityOf(tester, find.byKey(const WordKey(103002001)));
    for (final neighbour in [103001, 103003]) {
      final aya = set.ayas.firstWhere((a) => a.id == neighbour);
      final line = find.text([for (final w in aya.words) w.text].join(' '));
      expect(line, findsOneWidget, reason: 'aya $neighbour is not on screen');
      expect(_opacityOf(tester, line), lessThan(recited));
    }
  });

  testWidgets('the last aya of the last rakʿah leaves the reader with no way '
      'to finish the prayer', (tester) async {
    await pumpPrayer(tester, db: db, set: set, wakelock: Phone().keepAwake);
    expect(find.text("Al-'Asr · 103:1"), findsOneWidget);
    await tapOn(tester, PrayerScreen.nextZone, times: set.ayas.length - 1);
    expect(find.text("Al-'Asr · 103:3"), findsOneWidget);
    await tapOn(tester, PrayerScreen.nextZone);
    expect(find.text('Prayer complete'), findsOneWidget);
    // And it closes itself: the reader is bowing, not reaching for Exit.
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('the set'), findsOneWidget);
  });

  testWidgets('the prayer stops to show a dialog, an error or a spinner, in '
      'a room where none of them can be dealt with', (tester) async {
    await pumpPrayer(tester, db: db, set: set, wakelock: _noWakelockHere);
    await tapOn(tester, PrayerScreen.nextZone, times: 2);
    await tapOn(tester, PrayerScreen.backZone, times: 5);
    // Past the end: the prayer completes, and the taps after land on that.
    await tapOn(tester, PrayerScreen.nextZone, times: 5);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      find.bySubtype<ProgressIndicator>(skipOffstage: false),
      findsNothing,
    );
    expect(find.byType(AlertDialog, skipOffstage: false), findsNothing);
    expect(find.byType(SnackBar, skipOffstage: false), findsNothing);
  });

  testWidgets('an aya too long for the screen stripes an overflow banner '
      'across the prayer', (tester) async {
    await pumpPrayer(
      tester,
      db: db,
      // 2:282 is a page on its own, and the word budget lets it be a whole
      // set: the first aya of a set goes in whatever it costs.
      set: await setOf(db, [2282]),
      wakelock: Phone().keepAwake,
    );
    await tapOn(tester, PrayerScreen.nextZone, times: 3);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a rakʿah that is one long aya cannot be finished by a tap', (
    tester,
  ) async {
    await pumpPrayer(
      tester,
      db: db,
      set: await setOf(db, [2282]),
      wakelock: Phone().keepAwake,
    );
    expect(find.text('Al-Baqarah · 2:282'), findsOneWidget);
    await tapOn(tester, PrayerScreen.nextZone);
    expect(find.text('Prayer complete'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });

  testWidgets('the prayer opens the microphone on a reader who never allowed '
      'it', (tester) async {
    final mic = FakeMic();
    RecordPlatform.instance = mic;
    await setMicPermission(db, MicPermission.denied);

    await pumpPrayer(tester, db: db, set: set, wakelock: Phone().keepAwake);

    expect(mic.opened, isEmpty);
    // And the screen does not claim to be hearing anyone.
    expect(find.text('Tap to advance'), findsOneWidget);
    expect(find.text('Following your voice'), findsNothing);
  });

  testWidgets('a reader who allowed the microphone but never downloaded the '
      'recogniser is listened to anyway', (tester) async {
    final mic = FakeMic();
    RecordPlatform.instance = mic;
    await setMicPermission(db, MicPermission.granted);

    await pumpPrayer(tester, db: db, set: set, wakelock: Phone().keepAwake);

    // Permission alone is not voice-follow. Without the model there is nothing
    // to listen with, and opening the microphone would be a recording nobody
    // asked for.
    expect(mic.opened, isEmpty);
    expect(find.text('Tap to advance'), findsOneWidget);
  });

  group('a prayer of several rakʿahs', () {
    late List<StudyAya> fatiha;

    setUp(() async {
      fatiha = (await setOf(db, [for (var a = 1; a <= 7; a++) 1000 + a])).ayas;
    });

    testWidgets('the second rakʿah begins before the reader has stood up from '
        'the first', (tester) async {
      final outcome = PrayerOutcome();
      await pumpPrayer(
        tester,
        db: db,
        set: set,
        wakelock: Phone().keepAwake,
        plan: PrayerPlan(preset: PrayerPreset.maghrib, rakahs: 3, first: set),
        fatiha: fatiha,
        outcome: outcome,
      );
      expect(find.text('MAGHRIB · RAKʿAH 1 OF 3'), findsOneWidget);
      expect(find.text('Al-Fatihah · 1:1'), findsOneWidget);
      // Seven ayas of Al-Fātiḥa and three of Al-ʿAṣr, then one past the end.
      await tapOn(tester, PrayerScreen.nextZone, times: 10);
      expect(find.text('RAKʿAH 2 OF 3'), findsOneWidget);
      expect(find.text('Tap to begin'), findsOneWidget);
      expect(outcome.reached, 1);
      await tester.tap(find.text('Tap to begin'));
      await tester.pumpAndSettle();
      expect(find.text('MAGHRIB · RAKʿAH 2 OF 3'), findsOneWidget);
      expect(find.text('Al-Fatihah · 1:1'), findsOneWidget);
      expect(outcome.reached, 2);
    });

    testWidgets('the third rakʿah is given a passage it is not recited with', (
      tester,
    ) async {
      await pumpPrayer(
        tester,
        db: db,
        set: set,
        wakelock: Phone().keepAwake,
        plan: PrayerPlan(rakahs: 3, first: set),
        fatiha: fatiha,
      );
      for (var r = 1; r <= 2; r++) {
        await tapOn(tester, PrayerScreen.nextZone, times: 10);
        await tapOn(tester, PrayerScreen.nextZone);
      }
      expect(find.text('PRAYER · RAKʿAH 3 OF 3'), findsOneWidget);
      // Al-Fātiḥa alone: its seventh aya is the last, and then it is over.
      await tapOn(tester, PrayerScreen.nextZone, times: 7);
      expect(find.text('Prayer complete'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
    });
  });

  testWidgets(
    'a reader with neither voice nor pace has a tap skip a whole aya',
    (tester) async {
      await pumpPrayer(
        tester,
        db: db,
        set: set,
        wakelock: Phone().keepAwake,
        prefs: (
          preset: null,
          rakahs: 1,
          voice: false,
          pace: false,
          wpm: 40,
          gloss: true,
          around: true,
          arabicSize: 52,
        ),
      );
      expect(find.text('Tap to advance'), findsOneWidget);
      await tapOn(tester, PrayerScreen.nextZone);
      expect(litWord(tester), 103002001);
      await tapOn(tester, PrayerScreen.nextZone);
      expect(litWord(tester), 103002002);
    },
  );

  testWidgets('a pinched size is lost when the prayer closes', (tester) async {
    final outcome = PrayerOutcome();
    await pumpPrayer(
      tester,
      db: db,
      set: set,
      wakelock: Phone().keepAwake,
      outcome: outcome,
    );
    final field = tester.getCenter(find.byKey(PrayerScreen.nextZone));
    final a = await tester.startGesture(field - const Offset(20, 0));
    final b = await tester.startGesture(
      field + const Offset(20, 0),
      pointer: 9,
    );
    await a.moveBy(const Offset(-20, 0));
    await b.moveBy(const Offset(20, 0));
    await tester.pump();
    await a.up();
    await b.up();
    await tester.pumpAndSettle();
    expect(outcome.size, greaterThan(52));
    expect(find.textContaining('remembered'), findsOneWidget);
  });
}
