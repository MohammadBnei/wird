import 'package:flutter/material.dart';

import '../../theme/nocturne.dart';
import '../../widgets/nocturne_button.dart';

/// A run of consecutive ayas, given by the first and the last.
typedef AyaSpan = ({int first, int last});

/// How the reader moves through the text, under the set they are reading.
///
/// The top of screen 1a says where the reader is; this says where they can
/// go. Two wants, one row: the set next to this one, which is a step, and any
/// other aya of any sūra, which is the index the app already has.
///
/// The unit is the set — the ayas that go to the prayer — and never the aya.
/// A reader who takes five at once moves five at once, and the arrow prints
/// the ayas it will hand them, so the grain is on the control rather than
/// something to be remembered. Stepping by one while the screen was about a
/// set moved the reader by a thing the screen is not about, and the number on
/// the arrow named an aya they had no use for.
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
  /// lands in as well as the ayas. Without it the step up from 2:1 says
  /// "3–7", which reads as ayas of Al-Baqarah and is the end of Al-Fātiḥa.
  final int surahId;

  /// The set before this one, or null at the very start of the Qur'an.
  ///
  /// It crosses the sūra's edge. A step that stopped there was dark on every
  /// sūra opened from the index, which opens one at its first aya: the reader
  /// pressed up on the first press of the walk and nothing moved.
  final AyaSpan? previous;

  /// The set after this one, or null at the very end of the Qur'an.
  final AyaSpan? next;

  /// Opens that set. A kin in the root panel makes the same move onto one
  /// aya; a step is not a reference, so it hands over the whole span.
  final void Function(AyaSpan to) onStep;

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
            flex: 3,
            child: _step(
              'Previous set',
              const Key('previous set'),
              Icons.arrow_upward,
              previous,
            ),
          ),
          // The arrows move by a set; this one goes anywhere, and that is the
          // whole of what it is for. Its old face said "Sūra or aya", which
          // named what the index answers with and left the reader to work out
          // that pressing it moves them at all — the owner walked the app and
          // asked what it was. It says the act instead, and says nothing
          // about where the reader already is, because the header carries
          // that and two places saying it is the defect this screen lost.
          Expanded(
            flex: 3,
            child: NocturneButton(
              key: const Key('open the index'),
              onPressed: onIndex,
              child: _target(
                Semantics(
                  label: 'Go to any sūra or aya',
                  child: const Text('Go to…', style: TextStyle(fontSize: 13)),
                ),
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: _step(
              'Next set',
              const Key('next set'),
              Icons.arrow_downward,
              next,
            ),
          ),
        ],
      ),
    );
  }

  /// An arrow alone would read as "scroll", so the step prints the ayas it
  /// hands over. A screen reader gets the move in words, because the numbers
  /// on their own are not one.
  Widget _step(String label, Key key, IconData icon, AyaSpan? to) =>
      MergeSemantics(
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

  /// The ayas the step hands over: their numbers inside that sūra, and the
  /// sūra as well when the step leaves this one. A span never straddles a
  /// sūra's edge, because a step into a short sūra takes what is there and
  /// stops.
  String _where(AyaSpan to) {
    final surah = to.first ~/ 1000;
    final first = to.first % 1000;
    final last = to.last % 1000;
    final ayas = first == last ? '$first' : '$first–$last';
    return surah == surahId ? ayas : '$surah:$ayas';
  }
}

/// A control tall enough to hit one-handed, mid-recitation, without looking.
///
/// The app's buttons are sized by their text, which leaves them a shade under
/// 30 px high. That is right for a control the reader stops to press and
/// wrong for the one they press while reciting.
Widget _target(Widget child) =>
    SizedBox(height: 27, child: Center(child: child));
