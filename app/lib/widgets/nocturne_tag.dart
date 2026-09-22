import 'package:flutter/material.dart';

import '../theme/nocturne.dart';

enum NocturneTagVariant { accent, accent2, neutral, outline }

/// A small label tinted from the ramps.
class NocturneTag extends StatelessWidget {
  const NocturneTag(
    this.label, {
    super.key,
    this.variant = NocturneTagVariant.neutral,
  });

  final String label;
  final NocturneTagVariant variant;

  @override
  Widget build(BuildContext context) {
    final n = Nocturne.of(context);
    final ramp = switch (variant) {
      NocturneTagVariant.accent => 'accent',
      NocturneTagVariant.accent2 => 'accent-2',
      _ => 'neutral',
    };
    final outlined = variant == NocturneTagVariant.outline;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: outlined ? null : n.color('$ramp-800'),
        border: outlined ? Border.all(color: n.accent) : null,
        borderRadius: BorderRadius.circular(n.radius('md') * 0.75),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          letterSpacing: 0.02 * 11,
          height: 1.2,
          color: outlined ? n.accent : n.color('$ramp-100'),
        ),
      ),
    );
  }
}
