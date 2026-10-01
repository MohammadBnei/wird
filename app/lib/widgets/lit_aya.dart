import 'dart:math';

import 'package:flutter/material.dart';

import '../data/root_repo.dart';
import '../theme/nocturne.dart';
import '../theme/glow.dart';

/// An aya's words, right to left, with the lit ones glowing.
///
/// [LitAya.window] draws one line: the word at [around] (or the first lit
/// word) with [span] words either side, and "…" where the aya goes on. A
/// long aya cut at the end of its line would otherwise drop the very word it
/// is shown for.
class LitAya extends StatelessWidget {
  const LitAya(this.words, {super.key, required this.glow, required this.style})
    : around = null,
      span = null;

  const LitAya.window(
    this.words, {
    super.key,
    required this.glow,
    required this.style,
    this.around,
    int this.span = 2,
  });

  final List<AyaWord> words;
  final Glow glow;

  /// The unlit words' style: font, size, colour.
  final TextStyle style;

  /// The word the window is centred on, by place; null centres on the first
  /// lit word.
  final int? around;

  /// Words shown either side in a window; null draws the whole aya.
  final int? span;

  @override
  Widget build(BuildContext context) {
    final n = Nocturne.of(context);
    final lit = style.merge(glowing(n, glow));
    final span = this.span;
    var shown = words;
    var before = false, after = false;
    if (span != null && words.isNotEmpty) {
      final centre = around ?? max(0, words.indexWhere((w) => w.lit));
      final lo = max(0, centre - span);
      final hi = min(words.length, centre + span + 1);
      shown = words.sublist(lo, hi);
      before = lo > 0;
      after = hi < words.length;
    }
    final text = Text.rich(
      TextSpan(
        children: [
          if (before) const TextSpan(text: '… '),
          for (final (i, word) in shown.indexed)
            TextSpan(
              text: i == 0 ? word.text : ' ${word.text}',
              style: word.lit ? lit : null,
            ),
          if (after) const TextSpan(text: ' …'),
        ],
      ),
      textDirection: TextDirection.rtl,
      style: style,
      maxLines: span == null ? null : 1,
      softWrap: span == null,
      overflow: span == null ? null : TextOverflow.ellipsis,
    );
    // Room for the glow above and below, so a clipped parent does not cut it.
    return span == null
        ? text
        : Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: text,
          );
  }
}
