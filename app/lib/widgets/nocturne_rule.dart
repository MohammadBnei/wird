import 'package:flutter/material.dart';

import '../theme/nocturne.dart';

/// A horizontal rule that fades to transparent over 48px at each end — the
/// system's signature edge, not a line that stops cleanly.
class NocturneRule extends StatelessWidget {
  const NocturneRule({super.key, this.fade = 48});

  final double fade;

  @override
  Widget build(BuildContext context) {
    final n = Nocturne.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: n.space('4')),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stop = (fade / constraints.maxWidth).clamp(0.0, 0.5);
          return Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                stops: [0, stop, 1 - stop, 1],
                colors: [
                  n.divider.withValues(alpha: 0),
                  n.divider,
                  n.divider,
                  n.divider.withValues(alpha: 0),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
