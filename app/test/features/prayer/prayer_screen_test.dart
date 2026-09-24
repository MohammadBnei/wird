import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wird/data/mic.dart';
import 'package:wird/data/sets.dart';
import 'package:wird/features/prayer/prayer_cursor.dart';
import 'package:wird/features/prayer/prayer_screen.dart';
import 'package:wird/theme/nocturne.dart';

import '../../corpus.dart';
import '../../microphone.dart';
import 'sets.dart';

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
}) async {
  tester.view.physicalSize = const Size(402, 874);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: nocturneTheme(),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => PrayerScreen(
                  db: db,
                  set: set,
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

Future<void> tapOn(WidgetTester tester, Key zone, {int times = 1}) async {
  for (var i = 0; i < times; i++) {
    await tester.tap(find.byKey(zone));
    await tester.pump();
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
    expect(litWord(tester), 103001001);
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
      cursor: PrayerCursor(14, position: 7),
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
    final recited = _opacityOf(tester, find.byKey(const ValueKey(103002001)));
    for (final neighbour in [103001, 103003]) {
      final aya = set.ayas.firstWhere((a) => a.id == neighbour);
      final line = find.text([for (final w in aya.words) w.text].join(' '));
      expect(line, findsOneWidget, reason: 'aya $neighbour is not on screen');
      expect(_opacityOf(tester, line), lessThan(recited));
    }
  });

  testWidgets('the set recited a second time inside the same prayer runs off '
      'the end instead of starting again', (tester) async {
    await pumpPrayer(tester, db: db, set: set, wakelock: Phone().keepAwake);
    expect(find.text('1st reading'), findsOneWidget);
    await tapOn(tester, PrayerScreen.nextZone, times: set.ayas.length);
    expect(litWord(tester), 103001001);
    expect(find.text('2nd reading'), findsOneWidget);
  });

  testWidgets('the prayer stops to show a dialog, an error or a spinner, in '
      'a room where none of them can be dealt with', (tester) async {
    await pumpPrayer(tester, db: db, set: set, wakelock: _noWakelockHere);
    await tapOn(tester, PrayerScreen.nextZone, times: 40);
    await tapOn(tester, PrayerScreen.backZone, times: 5);
    await tester.tap(find.text('Exit'));
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

  testWidgets('a set that is one long aya swallows the tap, because the jump '
      'to the next reading is further than the prayer takes in one step', (
    tester,
  ) async {
    await pumpPrayer(
      tester,
      db: db,
      set: await setOf(db, [2282]),
      wakelock: Phone().keepAwake,
    );
    expect(find.text('1st reading'), findsOneWidget);
    await tapOn(tester, PrayerScreen.nextZone);
    expect(find.text('2nd reading'), findsOneWidget);
  });

  testWidgets('the prayer opens the microphone on a reader who never allowed '
      'it', (tester) async {
    final mic = FakeMic();
    RecordPlatform.instance = mic;
    await setMicPermission(db, MicPermission.denied);

    await pumpPrayer(tester, db: db, set: set, wakelock: Phone().keepAwake);

    expect(mic.opened, isEmpty);
    // And the screen does not claim to be hearing anyone.
    expect(find.text('IN PRAYER'), findsOneWidget);
    expect(find.text('FOLLOWING YOUR VOICE'), findsNothing);
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
    expect(find.text('IN PRAYER'), findsOneWidget);
  });
}
