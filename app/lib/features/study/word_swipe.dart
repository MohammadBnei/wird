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
  });

  /// The word shown. A change of it ends a slide, or fades.
  final int wordId;
  final Widget child;

  /// Null where the sūra ends on that side. Each completes once the step has
  /// landed on a word, or has come to nothing.
  final Future<void> Function()? onNext;
  final Future<void> Function()? onPrevious;

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
  static const _edge = 24.0;
  static const _travel = Duration(milliseconds: 220);

  double _width = 1;

  /// The side the next word comes in from, once it arrives: -1 left, 1 right.
  double? _enterFrom;

  /// A drag that started within reach of the screen's edge belongs to the
  /// drawer or the system's back gesture.
  bool _ignored = false;

  void slideNext() => unawaited(_leave(1, widget.onNext));
  void slidePrevious() => unawaited(_leave(-1, widget.onPrevious));

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
    final from = _enterFrom;
    _enterFrom = null;
    if (from == null) {
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
    if (_ignored || _enterFrom != null) return;
    final dx = _offset.value * _width + d.delta.dx;
    // Resisted where there is nowhere to go.
    final stuck =
        (dx > 0 && widget.onNext == null) ||
        (dx < 0 && widget.onPrevious == null);
    _offset.value = (stuck ? dx - d.delta.dx * 0.75 : dx) / _width;
  }

  void _end(DragEndDetails _) {
    if (_ignored || _enterFrom != null) return;
    final dx = _offset.value * _width;
    if (dx > _threshold && widget.onNext != null) return slideNext();
    if (dx < -_threshold && widget.onPrevious != null) return slidePrevious();
    _offset.animateTo(0, duration: _travel, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _offset.dispose();
    _fade.dispose();
    super.dispose();
  }

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
          builder: (context, child) => FractionalTranslation(
            translation: Offset(_offset.value, 0),
            child: Opacity(opacity: _fade.value, child: child),
          ),
          child: widget.child,
        ),
      );
    },
  );
}
