import 'package:flutter/material.dart';

import '../../app.dart';
import '../../data/db.dart' show Reciter;
import '../../l10n/app_localizations.dart';
import '../../theme/nocturne.dart';

/// The reciters, one row each: who, in which style and what that style is
/// for, and a button to hear them on the basmala before choosing.
///
/// A list of names was a choice made blind — the two Husary rows differed by a
/// word few readers know — and finding out meant leaving for the reading
/// screen and pressing play. The width is held to a phone's, so on a tablet
/// the rows do not stretch a ring across the whole screen.
class ReciterList extends StatelessWidget {
  const ReciterList({
    super.key,
    required this.reciters,
    required this.selected,
    required this.onChanged,
  });

  final List<Reciter> reciters;
  final String selected;
  final ValueChanged<String> onChanged;

  String? _style(AppLocalizations l, String? style) => switch (style) {
    null => null,
    'Muallim' => l.settingsStyleMuallim,
    'Murattal' => l.settingsStyleMurattal,
    final other => other,
  };

  @override
  Widget build(BuildContext context) {
    final n = Nocturne.of(context);
    final l = AppLocalizations.of(context)!;
    final recitation = Wird.of(context).recitation;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: n.divider),
          borderRadius: BorderRadius.circular(n.radius('md')),
        ),
        clipBehavior: Clip.antiAlias,
        child: ValueListenableBuilder<String?>(
          valueListenable: recitation.sampling,
          builder: (context, sampling, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, r) in reciters.indexed) ...[
                if (i > 0) Container(height: 1, color: n.divider),
                _row(context, n, l, r, sampling == r.slug, recitation),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(
    BuildContext context,
    Nocturne n,
    AppLocalizations l,
    Reciter r,
    bool sounding,
    Recitation recitation,
  ) {
    final chosen = r.slug == selected;
    final style = _style(l, r.style);
    return Semantics(
      selected: chosen,
      button: true,
      child: InkWell(
        onTap: () => onChanged(r.slug),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: chosen ? n.accent : Colors.transparent),
          ),
          padding: const EdgeInsets.only(left: 12, top: 6, bottom: 6),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 2,
                  children: [
                    Text(
                      r.name,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.2,
                        color: chosen ? n.accent : n.text,
                      ),
                    ),
                    if (style != null)
                      Text(
                        style,
                        style: TextStyle(
                          fontSize: 10.5,
                          height: 1.3,
                          color: n.textAt(0.5),
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                key: Key('sample ${r.slug}'),
                tooltip: sounding
                    ? l.settingsStopSample
                    : l.settingsHearReciter(r.name),
                onPressed: () => recitation.sample(r.slug),
                icon: Icon(
                  sounding ? Icons.stop : Icons.play_arrow,
                  size: 20,
                  color: sounding ? n.accent : n.textAt(0.7),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
