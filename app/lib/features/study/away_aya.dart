import 'package:flutter/material.dart';

import '../../data/root_repo.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/glow.dart';
import '../../theme/nocturne.dart';
import '../../widgets/lit_aya.dart';
import '../../widgets/nocturne_kicker.dart';
import 'aya_translation.dart';

/// Another aya the reader opened from the root's list, in place of the sūra:
/// the aya with the root's words lit, its translation when the reader shows
/// translations, and the way back to the word they left. [compact] is the
/// one-line form, while the sheet below is open.
class AwayAya extends StatelessWidget {
  const AwayAya({
    super.key,
    required this.aya,
    required this.homeRef,
    required this.compact,
    required this.translation,
    required this.onBack,
    required this.onReadFromHere,
  });

  final RootAya aya;

  /// Where the reader was, as a reference: what "back" returns to.
  final String homeRef;
  final bool compact;

  /// The aya's translation when the reader shows translations, else null.
  final String? translation;

  final VoidCallback onBack;
  final VoidCallback onReadFromHere;

  @override
  Widget build(BuildContext context) {
    final n = Nocturne.of(context);
    final l = AppLocalizations.of(context)!;
    final ref = NocturneKicker(ayahRef(aya.ayahId), tone: KickerTone.accent);
    if (compact) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          spacing: 10,
          children: [
            OutlinedButton(onPressed: onBack, child: Text('‹ $homeRef')),
            ref,
            Expanded(
              child: LitAya.window(
                aya.words,
                glow: Glow.reading,
                style: TextStyle(
                  fontFamily: Nocturne.arabicFamily,
                  fontSize: 20,
                  height: 1.6,
                  color: n.textAt(0.62),
                ),
              ),
            ),
          ],
        ),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OutlinedButton.icon(
            key: const Key('back to reading'),
            onPressed: onBack,
            icon: const Icon(Icons.chevron_left, size: 14),
            label: Text(l.study_backTo(homeRef)),
          ),
          const SizedBox(height: 18),
          ref,
          const SizedBox(height: 6),
          LitAya(
            aya.words,
            glow: Glow.reading,
            style: TextStyle(
              fontFamily: Nocturne.arabicFamily,
              fontSize: 28,
              height: 1.8,
              color: n.text,
            ),
          ),
          AyaTranslation(translation),
          TextButton(
            key: const Key('read from here'),
            onPressed: onReadFromHere,
            child: Text(l.study_readFromHere),
          ),
        ],
      ),
    );
  }
}
