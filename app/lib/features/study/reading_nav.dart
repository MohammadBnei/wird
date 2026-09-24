import 'package:flutter/material.dart';

import '../../theme/nocturne.dart';
import '../../widgets/nocturne_button.dart';

/// How the reader moves through the text, under the set they are reading.
///
/// The top of screen 1a says where the reader is; this says where they can
/// go. Two wants, one row: the aya next to this one, which is a step, and any
/// other aya of any sūra, which is the index the app already has.
///
/// The arrows point up and down rather than left and right because that is
/// how the reading moves on the screen — earlier is above, later is below —
/// and a left arrow beside right-to-left Arabic says two things at once.
///
/// It never folds. It is one row against the root panel's twelve, and a
/// reader mid-recitation cannot be asked to unfold a thing before they can
/// move with it.
///
/// The edge above it belongs to the footer it sits in rather than to this
/// row, because what is sounding is drawn above it under the same edge.
class ReadingNav extends StatelessWidget {
  const ReadingNav({
    super.key,
    required this.surahId,
    required this.previous,
    required this.next,
    required this.onStep,
    required this.onIndex,
  });

  /// The sūra the reader is in, so that a step out of it prints the sūra it
  /// lands in as well as the aya. Without it the step up from 2:1 says "7",
  /// which reads as an aya of Al-Baqarah and is Al-Fātiḥa's last.
  final int surahId;

  /// The aya before the set, or null at the very start of the Qur'an.
  ///
  /// It crosses the sūra's edge. A step that stopped there was dark on every
  /// sūra opened from the index, which opens one at its first aya: the reader
  /// pressed up on the first press of the walk and nothing moved.
  final int? previous;

  /// The aya after the set, or null at the very end of the Qur'an.
  final int? next;

  /// Opens that aya, which is the same move a kin in the root panel makes.
  final void Function(int ayahId) onStep;

  /// Opens the sūra index, which answers with an aya anywhere in the Qur'an.
  final VoidCallback onIndex;

  @override
  Widget build(BuildContext context) {
    final n = Nocturne.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        n.space('6'),
        n.space('2'),
        n.space('6'),
        n.space('2'),
      ),
      child: Row(
        spacing: n.space('2'),
        children: [
          Expanded(
            flex: 2,
            child: _step(
              'Previous aya',
              const Key('previous aya'),
              Icons.arrow_upward,
              previous,
            ),
          ),
          Expanded(
            flex: 5,
            child: NocturneButton(
              key: const Key('open the index'),
              onPressed: onIndex,
              child: _target(
                const Text('Sūra or aya', style: TextStyle(fontSize: 13)),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: _step(
              'Next aya',
              const Key('next aya'),
              Icons.arrow_downward,
              next,
            ),
          ),
        ],
      ),
    );
  }

  /// An arrow alone would read as "scroll", so the step prints the number of
  /// the aya it lands on. It also says where the reader is without the footer
  /// repeating the title above the set. A screen reader gets the move in
  /// words, because the number on its own is not one.
  Widget _step(String label, Key key, IconData icon, int? to) => MergeSemantics(
    child: Semantics(
      label: to == null ? label : '$label ${_where(to)}',
      child: NocturneButton(
        key: key,
        onPressed: to == null ? null : () => onStep(to),
        child: _target(
          Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 4,
            children: [
              Icon(icon, size: 16),
              if (to != null)
                Text(_where(to), style: const TextStyle(fontSize: 12.5)),
            ],
          ),
        ),
      ),
    ),
  );

  /// The aya the step lands on: its number inside this sūra, and its sūra as
  /// well when the step leaves this one.
  String _where(int to) =>
      to ~/ 1000 == surahId ? '${to % 1000}' : '${to ~/ 1000}:${to % 1000}';
}

/// A control tall enough to hit one-handed, mid-recitation, without looking.
///
/// The app's buttons are sized by their text, which leaves them a shade under
/// 30 px high. That is right for a control the reader stops to press and
/// wrong for the one they press while reciting.
Widget _target(Widget child) =>
    SizedBox(height: 27, child: Center(child: child));
