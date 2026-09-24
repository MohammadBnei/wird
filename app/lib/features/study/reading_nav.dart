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
class ReadingNav extends StatelessWidget {
  const ReadingNav({
    super.key,
    required this.previous,
    required this.next,
    required this.onStep,
    required this.onIndex,
  });

  /// The aya before the set, or null when it starts the sūra.
  ///
  /// ponytail: a step stays inside the sūra, so the reader at 2:1 steps back
  /// to nothing rather than to 1:7. Reach across if reading past a sūra's end
  /// turns out to be what a reader does.
  final int? previous;

  /// The aya after the set, or null when it ends the sūra.
  final int? next;

  /// Opens that aya, which is the same move a kin in the root panel makes.
  final void Function(int ayahId) onStep;

  /// Opens the sūra index, which answers with an aya anywhere in the Qur'an.
  final VoidCallback onIndex;

  @override
  Widget build(BuildContext context) {
    final n = Nocturne.of(context);
    return Container(
      padding: EdgeInsets.fromLTRB(
        n.space('6'),
        n.space('2'),
        n.space('6'),
        n.space('2'),
      ),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: n.divider)),
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
      label: to == null ? label : '$label ${to % 1000}',
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
                Text('${to % 1000}', style: const TextStyle(fontSize: 12.5)),
            ],
          ),
        ),
      ),
    ),
  );
}

/// A control tall enough to hit one-handed, mid-recitation, without looking.
///
/// The app's buttons are sized by their text, which leaves them a shade under
/// 30 px high. That is right for a control the reader stops to press and
/// wrong for the one they press while reciting.
Widget _target(Widget child) =>
    SizedBox(height: 27, child: Center(child: child));
