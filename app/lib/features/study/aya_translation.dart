import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/nocturne.dart';

/// An aya's translation, and whose it is, under the aya — wherever the reading
/// screen draws an aya whole. Nothing when [text] is null: the reader turned
/// translations off, or the corpus has none in their language.
class AyaTranslation extends StatelessWidget {
  const AyaTranslation(this.text, {super.key});

  final String? text;

  @override
  Widget build(BuildContext context) {
    final text = this.text;
    if (text == null) return const SizedBox.shrink();
    final n = Nocturne.of(context);
    return Padding(
      padding: EdgeInsets.only(top: n.space('2')),
      child: Column(
        children: [
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13.5,
              height: 1.55,
              color: n.textAt(0.78),
            ),
          ),
          SizedBox(height: n.space('1')),
          Text(
            AppLocalizations.of(context)!.study_ayaTranslated,
            style: TextStyle(fontSize: 10.5, color: n.textAt(0.45)),
          ),
        ],
      ),
    );
  }
}
