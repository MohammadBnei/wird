import 'dart:async';

import 'package:flutter/material.dart';

/// The root sheet's content, which a sideways drag carries to the word before
/// or after.
///
/// It slides: the finger takes the content with it, and once a drag passes
/// [_threshold] the content keeps going off the side it was pushed to while
/// the next word is read, then that word comes in from the other side.
/// Arabic reads leftward, so the next word lies to the left: a drag to the
/// right moves on, and the new word enters from the left.
///
/// Where the word on that side has already been read ([next], [previous]), it
/// is drawn beside the content and comes in with the finger, so a step is one
/// slide and not a leave and a return. The neighbours are built only while
/// the content is off its rest, so a sheet at rest holds one word.
///
/// The arrows and the arrow keys slide the same way through [slideNext] and
/// [slidePrevious]. Any other change of word — a tap in the sūra, a jump to
/// another aya — is not a step along the text, and fades instead.
class WordSwipe extends StatefulWidget {
  const WordSwipe({
    super.key,
    required this.wordId,
    required this.child,
    required this.onNext,
    required this.onPrevious,
    this.nextId,
    this.next,
    this.previousId,
    this.previous,
  });

  /// The word shown. A change of it ends a slide, or fades.
  final int wordId;
  final Widget child;

  /// Null where the sūra ends on that side. Each completes once the step has
  /// landed on a word, or has come to nothing.
  final Future<void> Function()? onNext;
  final Future<void> Function()? onPrevious;

  /// The word on each side and how it is drawn, once it has been read. Null
  /// while it is still being read, and a step then leaves and comes back.
  final int? nextId;
  final WidgetBuilder? next;
  final int? previousId;
  final WidgetBuilder? previous;

  @override
  State<WordSwipe> createState() => WordSwipeState();
}

class WordSwipeState extends State<WordSwipe> with TickerProviderStateMixin {
  /// Where the content sits, in widths: 0 is home, 1 is one width right.
  late final _offset = AnimationController.unbounded(vsync: this);
  late final _fade = AnimationController(
    vsync: this,
    value: 1,
    duration: const Duration(milliseconds: 160),
  );

  static const _threshold = 60.0;
  static const _fling = 600.0;
  static const _edge = 24.0;
  static const _travel = Duration(milliseconds: 220);

  double _width = 1;

  /// The side the next word comes in from, once it arrives: -1 left, 1 right.
  double? _enterFrom;

  /// The word a slide with its neighbour drawn is carrying in. Its arrival
  /// is the end of the slide, not a change to fade to.
  int? _gliding;

  /// A drag that started within reach of the screen's edge belongs to the
  /// drawer or the system's back gesture.
  bool _ignored = false;

  bool get _busy => _gliding != null || _enterFrom != null;

  void slideNext() => _slide(1);
  void slidePrevious() => _slide(-1);

  /// A press during a slide with the neighbour drawn, taken once that slide
  /// has landed: two quick presses still move two words, and a held arrow key
  /// moves one word per slide rather than piling up.
  double? _queued;

  void _slide(double side) {
    if (_gliding != null) {
      _queued = side;
      return;
    }
    final forward = side > 0;
    final go = forward ? widget.onNext : widget.onPrevious;
    final id = forward ? widget.nextId : widget.previousId;
    final drawn = forward ? widget.next : widget.previous;
    unawaited(
      id != null && drawn != null ? _glide(side, go, id) : _leave(side, go),
    );
  }

  /// Carries the content off to [side] with the word there beside it, then
  /// asks for that word, which arrives exactly where it is already drawn.
  Future<void> _glide(double side, Future<void> Function()? go, int to) async {
    if (go == null) return;
    _gliding = to;
    try {
      final left = (side - _offset.value).abs().clamp(0.0, 1.0);
      await _offset
          .animateTo(
            side,
            duration: _travel * (left * 1.2),
            curve: Curves.easeOutCubic,
          )
          .orCancel;
      await go();
      await WidgetsBinding.instance.endOfFrame;
    } on TickerCanceled {
      // Overtaken by another change of word, which has put the content back.
    } finally {
      // A step that landed nowhere brings the content back, and the next
      // swipe is not blocked by this one.
      if (mounted && _gliding == to) {
        _gliding = null;
        _queued = null;
        unawaited(
          _offset.animateTo(0, duration: _travel, curve: Curves.easeOut),
        );
      }
      final queued = _queued;
      _queued = null;
      if (mounted && queued != null) _slide(queued);
    }
  }

  /// Sends the content off to [side] and asks for the word there. A step
  /// that lands nowhere — the words could not be read, or a newer step
  /// overtook it — brings the content back, so it is never left off-screen.
  Future<void> _leave(double side, Future<void> Function()? go) async {
    if (go == null) return;
    _enterFrom = -side;
    unawaited(
      _offset.animateTo(side * 1.1, duration: _travel, curve: Curves.easeIn),
    );
    try {
      await go();
      // The new word reaches this widget on the next frame, not when the
      // step completes; deciding before then would undo a slide that landed.
      await WidgetsBinding.instance.endOfFrame;
    } finally {
      if (mounted && _enterFrom != null) {
        _enterFrom = null;
        unawaited(
          _offset.animateTo(0, duration: _travel, curve: Curves.easeOut),
        );
      }
    }
  }

  @override
  void didUpdateWidget(WordSwipe oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.wordId == widget.wordId) return;
    final landed = _gliding == widget.wordId;
    _gliding = null;
    final from = _enterFrom;
    _enterFrom = null;
    if (landed) {
      // Already drawn where the content rests now.
      _offset.value = 0;
    } else if (from == null) {
      _offset.value = 0;
      _fade.forward(from: 0);
    } else {
      _offset.value = from;
      _offset.animateTo(0, duration: _travel, curve: Curves.easeOut);
    }
  }

  void _start(DragStartDetails d) {
    final width = MediaQuery.sizeOf(context).width;
    _ignored =
        d.globalPosition.dx < _edge || d.globalPosition.dx > width - _edge;
  }

  void _update(DragUpdateDetails d) {
    if (_ignored || _busy) return;
    final dx = _offset.value * _width + d.delta.dx;
    // Resisted where there is nowhere to go.
    final stuck =
        (dx > 0 && widget.onNext == null) ||
        (dx < 0 && widget.onPrevious == null);
    _offset.value = (stuck ? dx - d.delta.dx * 0.75 : dx) / _width;
  }

  void _end(DragEndDetails d) {
    if (_ignored || _busy) return;
    final dx = _offset.value * _width;
    // A flick moves on as surely as a long drag, if it goes the same way.
    final flung = (d.primaryVelocity ?? 0) * dx.sign > _fling;
    if ((dx > _threshold || flung && dx > 0) && widget.onNext != null) {
      return slideNext();
    }
    if ((dx < -_threshold || flung && dx < 0) && widget.onPrevious != null) {
      return slidePrevious();
    }
    _offset.animateTo(0, duration: _travel, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _offset.dispose();
    _fade.dispose();
    super.dispose();
  }

  /// The word on one side, drawn from its top and without a scroll of its
  /// own, at [x] widths from rest. Nothing in it answers a touch or a screen
  /// reader: it is a glimpse until it lands.
  Widget _beside(String side, WidgetBuilder drawn, double x) => Positioned.fill(
    key: ValueKey(side),
    child: FractionalTranslation(
      translation: Offset(x, 0),
      child: IgnorePointer(
        child: ExcludeSemantics(
          child: ClipRect(
            child: OverflowBox(
              alignment: Alignment.topCenter,
              minHeight: 0,
              maxHeight: double.infinity,
              child: Builder(builder: drawn),
            ),
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      _width = box.maxWidth;
      return GestureDetector(
        key: const Key('swipe'),
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: _start,
        onHorizontalDragUpdate: _update,
        onHorizontalDragEnd: _end,
        child: AnimatedBuilder(
          animation: Listenable.merge([_offset, _fade]),
          builder: (context, child) {
            final x = _offset.value;
            // Not while a word is being read: the side it went off is empty.
            final glimpse = _enterFrom == null;
            final next = widget.next;
            final previous = widget.previous;
            return ClipRect(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // The next word lies to the left.
                  if (glimpse && x > 0 && next != null)
                    _beside('next', next, x - 1),
                  KeyedSubtree(
                    key: const ValueKey('current'),
                    child: FractionalTranslation(
                      translation: Offset(x, 0),
                      child: Opacity(opacity: _fade.value, child: child),
                    ),
                  ),
                  if (glimpse && x < 0 && previous != null)
                    _beside('previous', previous, x + 1),
                ],
              ),
            );
          },
          child: widget.child,
        ),
      );
    },
  );
}
