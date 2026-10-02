import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wird/features/study/word_swipe.dart';

/// A host whose word changes only when the test says so, the way the reading
/// screen's does once the next word has been read.
class _Host extends StatefulWidget {
  const _Host({
    required this.onNext,
    required this.onPrevious,
    this.drawn = false,
  });

  final Future<void> Function()? onNext;
  final Future<void> Function()? onPrevious;

  /// Whether the words either side have been read, so the swipe can draw
  /// them beside this one.
  final bool drawn;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  final swipe = GlobalKey<WordSwipeState>();
  int word = 1;

  /// The step under way, which completes when its word arrives.
  Completer<void>? pending;

  void arrive(int next) {
    setState(() => word = next);
    pending?.complete();
    pending = null;
  }

  /// The step comes to nothing: no word arrives.
  void fail() {
    pending?.complete();
    pending = null;
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: double.infinity,
          height: 200,
          child: WordSwipe(
            key: swipe,
            wordId: word,
            onNext: widget.onNext,
            onPrevious: widget.onPrevious,
            nextId: widget.drawn ? word + 1 : null,
            next: widget.drawn ? (_) => Text('word ${word + 1}') : null,
            previousId: widget.drawn ? word - 1 : null,
            previous: widget.drawn ? (_) => Text('word ${word - 1}') : null,
            child: Text('word $word', key: const Key('content')),
          ),
        ),
      ),
    ),
  );
}

void main() {
  late List<String> asked;

  Future<_HostState> pump(
    WidgetTester tester, {
    bool next = true,
    bool previous = true,
    bool drawn = false,
  }) async {
    asked = [];
    late _HostState host;
    Future<void> step(String which) {
      asked.add(which);
      return (host.pending = Completer<void>()).future;
    }

    await tester.pumpWidget(
      _Host(
        onNext: next ? () => step('next') : null,
        onPrevious: previous ? () => step('previous') : null,
        drawn: drawn,
      ),
    );
    return host = tester.state<_HostState>(find.byType(_Host));
  }

  /// Where the content sits, left edge, relative to where it rests.
  double shift(WidgetTester tester, double home) =>
      tester.getTopLeft(find.byKey(const Key('content'))).dx - home;

  testWidgets('a short drag changes word, or leaves the word off to one side', (
    tester,
  ) async {
    await pump(tester);
    final home = tester.getTopLeft(find.byKey(const Key('content'))).dx;

    await tester.drag(find.byKey(const Key('swipe')), const Offset(40, 0));
    await tester.pumpAndSettle();

    expect(asked, isEmpty);
    expect(shift(tester, home), 0);
  });

  testWidgets('a released swipe snaps back before the next word arrives', (
    tester,
  ) async {
    final host = await pump(tester);
    final home = tester.getTopLeft(find.byKey(const Key('content'))).dx;

    await tester.drag(find.byKey(const Key('swipe')), const Offset(120, 0));
    await tester.pumpAndSettle();

    // The word is still being read: the old one is gone off the right side.
    expect(asked, ['next']);
    expect(shift(tester, home), greaterThan(250));

    host.arrive(2);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(
      shift(tester, home),
      lessThan(0),
      reason:
          'the next word lies to the left in Arabic, so it enters from there',
    );
    await tester.pumpAndSettle();
    expect(shift(tester, home), 0);
  });

  testWidgets('the next word arrives from the side it lies on', (tester) async {
    final host = await pump(tester);
    final home = tester.getTopLeft(find.byKey(const Key('content'))).dx;

    host.swipe.currentState!.slidePrevious();
    await tester.pumpAndSettle();
    expect(asked, ['previous']);
    expect(shift(tester, home), lessThan(-250));

    host.arrive(0);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(shift(tester, home), greaterThan(0));
  });

  testWidgets('a word reached by a jump slides in as if it were the next one', (
    tester,
  ) async {
    final host = await pump(tester);
    final home = tester.getTopLeft(find.byKey(const Key('content'))).dx;

    host.arrive(40);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));

    expect(shift(tester, home), 0);
    await tester.pumpAndSettle();
  });

  testWidgets('a drag at the end of the sūra changes nothing yet moves as '
      'freely as one with somewhere to go', (tester) async {
    await pump(tester, next: false);
    final home = tester.getTopLeft(find.byKey(const Key('content'))).dx;
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('swipe'))),
    );
    await gesture.moveBy(const Offset(20, 0));
    await gesture.moveBy(const Offset(100, 0));
    await tester.pump();

    expect(shift(tester, home), lessThan(60));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(asked, isEmpty);
  });

  testWidgets("a drag from the screen's edge is taken from the drawer", (
    tester,
  ) async {
    await pump(tester);
    final gesture = await tester.startGesture(const Offset(10, 300));
    await gesture.moveBy(const Offset(200, 0));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(asked, isEmpty);
  });

  testWidgets('a step that lands nowhere leaves the word off the side of the '
      'sheet', (tester) async {
    final host = await pump(tester);
    final home = tester.getTopLeft(find.byKey(const Key('content'))).dx;

    host.swipe.currentState!.slideNext();
    await tester.pumpAndSettle();
    host.fail();
    await tester.pumpAndSettle();

    expect(shift(tester, home), 0);
  });

  testWidgets('half way through a drag the next word is not on screen, so the '
      'sheet flicks instead of sliding', (tester) async {
    await pump(tester, drawn: true);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('swipe'))),
    );
    await gesture.moveBy(const Offset(20, 0));
    await gesture.moveBy(const Offset(150, 0));
    await tester.pump();

    final current = tester.getTopLeft(find.text('word 1')).dx;
    final beside = tester.getTopLeft(find.text('word 2')).dx;
    expect(
      beside,
      lessThan(current),
      reason: 'the next word lies to the left in Arabic',
    );
    expect(find.text('word 0'), findsNothing);
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('a slide that lands takes the word off and brings it back in '
      'rather than leaving the next one where it already is', (tester) async {
    final host = await pump(tester, drawn: true);
    final home = tester.getTopLeft(find.byKey(const Key('content'))).dx;

    host.swipe.currentState!.slideNext();
    await tester.pumpAndSettle();
    expect(asked, ['next']);

    host.arrive(2);
    await tester.pump();
    expect(find.text('word 2'), findsOneWidget);
    expect(shift(tester, home), 0);
    await tester.pumpAndSettle();
    expect(shift(tester, home), 0);
  });

  testWidgets('a held arrow key piles up steps the reader never sees', (
    tester,
  ) async {
    final host = await pump(tester, drawn: true);

    for (var i = 0; i < 5; i++) {
      host.swipe.currentState!.slideNext();
      await tester.pump(const Duration(milliseconds: 30));
    }
    await tester.pumpAndSettle();
    host.arrive(2);
    await tester.pumpAndSettle();

    expect(asked, ['next', 'next']);
  });

  testWidgets('a slide that lands nowhere leaves the swipe dead', (
    tester,
  ) async {
    final host = await pump(tester, drawn: true);
    final home = tester.getTopLeft(find.byKey(const Key('content'))).dx;

    host.swipe.currentState!.slideNext();
    await tester.pumpAndSettle();
    host.fail();
    await tester.pumpAndSettle();
    expect(shift(tester, home), 0);

    host.swipe.currentState!.slideNext();
    await tester.pumpAndSettle();
    expect(asked, ['next', 'next']);
  });

  testWidgets('a jump during a slide is carried on as a step to the word '
      'beside', (tester) async {
    final host = await pump(tester, drawn: true);
    final home = tester.getTopLeft(find.byKey(const Key('content'))).dx;

    host.swipe.currentState!.slideNext();
    await tester.pump(const Duration(milliseconds: 60));
    host.arrive(40);
    await tester.pumpAndSettle();

    expect(asked, isEmpty);
    expect(shift(tester, home), 0);
    expect(find.text('word 40'), findsOneWidget);
  });
}
