import 'package:flutter/material.dart';

import '../theme/nocturne.dart';

enum KickerTone { muted, accent }

/// The small uppercase label over a section or a card.
class NocturneKicker extends StatelessWidget {
  const NocturneKicker(this.text, {super.key, this.tone = KickerTone.muted});

  final String text;
  final KickerTone tone;

  @override
  Widget build(BuildContext context) {
    final n = Nocturne.of(context);
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 10,
        height: 1.2,
        letterSpacing: 1.1,
        color: tone == KickerTone.accent ? n.accent : n.textAt(0.55),
      ),
    );
  }
}
