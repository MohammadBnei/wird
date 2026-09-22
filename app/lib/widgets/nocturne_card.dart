import 'package:flutter/material.dart';

import '../theme/nocturne.dart';

enum NocturneElevation { sm, md, lg }

/// A surface-filled content card: kicker, title, body and meta slots.
class NocturneCard extends StatelessWidget {
  const NocturneCard({
    super.key,
    this.kicker,
    this.title,
    this.body,
    this.meta,
    this.elevation,
  });

  final String? kicker;
  final String? title;
  final String? body;
  final List<Widget>? meta;
  final NocturneElevation? elevation;

  @override
  Widget build(BuildContext context) {
    final n = Nocturne.of(context);
    final slots = <Widget>[
      if (kicker != null)
        Text(
          kicker!.toUpperCase(),
          style: TextStyle(
            fontSize: 10,
            letterSpacing: 0.1 * 10,
            height: 1.2,
            color: n.accent,
          ),
        ),
      if (title != null)
        Text(title!, style: Theme.of(context).textTheme.titleMedium),
      if (body != null)
        Text(
          body!,
          style: TextStyle(fontSize: 13, height: 1.55, color: n.textAt(0.8)),
        ),
      if (meta != null)
        DefaultTextStyle.merge(
          style: TextStyle(fontSize: 11, height: 1.2, color: n.textAt(0.5)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 6,
            children: meta!,
          ),
        ),
    ];
    return Container(
      padding: EdgeInsets.all(n.space('3')),
      decoration: BoxDecoration(
        color: n.surface,
        borderRadius: BorderRadius.circular(n.radius('md')),
        boxShadow: elevation == null ? null : n.shadow(elevation!.name),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        spacing: n.space('2'),
        children: slots,
      ),
    );
  }
}
