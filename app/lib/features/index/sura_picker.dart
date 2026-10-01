import 'package:flutter/material.dart';

import '../../data/sets.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/nocturne.dart';
import '../../widgets/nocturne_input.dart';
import '../../widgets/nocturne_rule.dart';
// The Arabic search folds names the way the voice folds what it hears, so the
// two never disagree about what a word is. Prayer imports the index for
// SuraEntry; this is the other direction.
import '../prayer/voice_follow.dart';
import 'index_screen.dart';

/// [suras] in the order the reader reads the Qur'an: as written, or by
/// revelation. The list handed in stays in written order everywhere else,
/// where `suras[id - 1]` is how a sūra is looked up; only what is drawn is
/// reordered.
List<SuraEntry> inOrder(List<SuraEntry> suras, ReadingOrder order) =>
    switch (order) {
      ReadingOrder.mushaf => suras,
      ReadingOrder.nuzul => [
        ...suras,
      ]..sort((a, b) => a.revelationOrder.compareTo(b.revelationOrder)),
    };

/// The aya id a reference like `2:255` names, or null when it is not one or
/// names an aya the sūra does not have. `2.255` is accepted too, because a
/// phone keyboard in numbers mode offers the dot before the colon.
int? parseRef(String query, List<SuraEntry> suras) {
  final m = RegExp(r'^(\d{1,3})\s*[:.]\s*(\d{1,3})$').firstMatch(query.trim());
  if (m == null) return null;
  final sura = int.parse(m[1]!);
  final aya = int.parse(m[2]!);
  if (sura < 1 || sura > suras.length) return null;
  if (aya < 1 || aya > suras[sura - 1].ayahCount) return null;
  return sura * 1000 + aya;
}

/// The sūras [query] could mean: by number, by English name typed with or
/// without the marks a transliteration carries, or by Arabic name typed with
/// or without harakāt. An empty query is every sūra.
///
/// A reference being typed, `2:` or `2.25`, names one sūra, so it narrows to
/// that one rather than to nothing while the aya is still coming.
List<SuraEntry> searchSuras(List<SuraEntry> suras, String query) {
  final q = query.trim();
  if (q.isEmpty) return suras;
  final head = RegExp(r'^(\d{1,3})\s*[:.]').firstMatch(q);
  final number = head != null ? int.parse(head[1]!) : int.tryParse(q);
  if (number != null) return suras.where((s) => s.id == number).toList();
  final latin = foldLatin(q);
  final arabic = recitationKey(q.replaceAll(' ', ''));
  return [
    for (final s in suras)
      if ((latin.isNotEmpty && foldLatin(s.nameEn).contains(latin)) ||
          (arabic.isNotEmpty &&
              recitationKey(s.nameAr.replaceAll(' ', '')).contains(arabic)))
        s,
  ];
}

/// A transliterated name reduced to plain letters, so `Al-Fātiḥa`, `fatiha`
/// and `Al-Fatihah` meet. The corpus spells its names in plain ASCII and the
/// reader may not, so both sides fold.
///
/// ponytail: a table of the marks sūra-name transliterations use, not a
/// Unicode decomposition. Dart has none built in; widen the table if a name
/// turns up that it misses.
String foldLatin(String s) {
  const marks = {
    'ā': 'a', 'á': 'a', 'à': 'a', 'â': 'a', 'ī': 'i', 'í': 'i', 'î': 'i', //
    'ū': 'u', 'ú': 'u', 'û': 'u', 'ḥ': 'h', 'ṣ': 's', 'ḍ': 'd', 'ṭ': 't', //
    'ẓ': 'z', 'é': 'e', 'è': 'e', 'ê': 'e',
  };
  final out = StringBuffer();
  for (final ch in s.toLowerCase().split('')) {
    final plain = marks[ch] ?? ch;
    if (RegExp('[a-z0-9]').hasMatch(plain)) out.write(plain);
  }
  // A trailing h is how half the transliterations end a tāʾ marbūṭa and the
  // other half do not, so it never decides a match.
  final folded = out.toString();
  return folded.endsWith('h') ? folded.substring(0, folded.length - 1) : folded;
}

/// The one list a reader chooses a sūra from, wherever they choose one: the
/// index and the prayer's passage chooser.
///
/// It searches by name, number or reference, and lists in the reader's
/// reading order. What a choice then does is the screen's.
class SuraPicker extends StatefulWidget {
  const SuraPicker({
    super.key,
    required this.suras,
    required this.order,
    required this.onSura,
    required this.onRef,
    required this.goToHint,
    this.exclude = const {},
    this.leading = const [],
    this.trailing,
    this.below,
  });

  /// Every sūra, in written order.
  final List<SuraEntry> suras;
  final ReadingOrder order;
  final ValueChanged<SuraEntry> onSura;

  /// A reference typed in full, as an aya id.
  final ValueChanged<int> onRef;

  /// Under "Go to …": what choosing the reference does on this screen.
  final String goToHint;

  /// Sūras never offered, neither as a row nor through a reference.
  final Set<int> exclude;

  /// Shown above the sūras while nothing is typed.
  final List<Widget> leading;

  /// At the end of a sūra's row, and under it.
  final Widget Function(SuraEntry)? trailing;
  final Widget? Function(SuraEntry)? below;

  @override
  State<SuraPicker> createState() => _SuraPickerState();
}

class _SuraPickerState extends State<SuraPicker> {
  var _query = '';

  @override
  Widget build(BuildContext context) {
    final n = Nocturne.of(context);
    final l = AppLocalizations.of(context)!;
    final ref = switch (parseRef(_query, widget.suras)) {
      final id? when !widget.exclude.contains(id ~/ 1000) => id,
      _ => null,
    };
    final rows = inOrder([
      for (final s in searchSuras(widget.suras, _query))
        if (!widget.exclude.contains(s.id)) s,
    ], widget.order);
    final query = _query.trim();
    final heads = [
      if (ref != null) _goTo(n, l, ref),
      if (query.isEmpty) ...widget.leading,
    ];
    final tail = [
      if (query.isNotEmpty && rows.isEmpty && ref == null)
        Padding(
          padding: EdgeInsets.only(top: n.space('4')),
          child: Text(
            l.chooser_no_match(query),
            style: TextStyle(fontSize: 13, color: n.textAt(0.58)),
          ),
        ),
    ];
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            n.space('6'),
            n.space('2'),
            n.space('6'),
            n.space('2'),
          ),
          child: NocturneInput(
            hint: l.chooser_search,
            onChanged: (q) => setState(() => _query = q),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.fromLTRB(
              n.space('6'),
              0,
              n.space('6'),
              n.space('8'),
            ),
            itemCount: heads.length + rows.length + tail.length,
            itemBuilder: (context, i) {
              if (i < heads.length) return heads[i];
              i -= heads.length;
              if (i < rows.length) return _row(n, l, rows[i]);
              return tail[i - rows.length];
            },
          ),
        ),
      ],
    );
  }

  Widget _goTo(Nocturne n, AppLocalizations l, int ref) {
    final sura = ref ~/ 1000;
    final aya = ref % 1000;
    return InkWell(
      onTap: () => widget.onRef(ref),
      child: Container(
        margin: const EdgeInsets.only(top: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: n.color('accent-900'),
          border: Border.all(color: n.color('accent-700')),
          borderRadius: BorderRadius.circular(n.radius('lg')),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.chooser_go_to(
                      '${widget.suras[sura - 1].nameEn} $sura:$aya',
                    ),
                    style: TextStyle(
                      fontSize: 14,
                      color: n.color('accent-100'),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.goToHint,
                    style: TextStyle(fontSize: 11.5, color: n.textAt(0.66)),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 16, color: n.textAt(0.6)),
          ],
        ),
      ),
    );
  }

  Widget _row(Nocturne n, AppLocalizations l, SuraEntry sura) {
    final below = widget.below?.call(sura);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          spacing: n.space('3'),
          children: [
            Expanded(
              child: GestureDetector(
                key: ValueKey('sura-${sura.id}'),
                behavior: HitTestBehavior.opaque,
                onTap: () => widget.onSura(sura),
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: n.space('2')),
                  child: Row(
                    spacing: n.space('3'),
                    children: [
                      SizedBox(
                        width: 74,
                        child: Text(
                          sura.nameAr,
                          textAlign: TextAlign.right,
                          textDirection: TextDirection.rtl,
                          style: TextStyle(
                            fontFamily: Nocturne.arabicFamily,
                            fontSize: 19,
                            color: n.textAt(below != null ? 1 : 0.75),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '${sura.id} · ${sura.nameEn}',
                                  style: TextStyle(fontSize: 11, color: n.text),
                                ),
                                Text(
                                  '${sura.understood} / ${sura.ayahCount}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: n.textAt(0.55),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            // The revelation order is the other way the app reads the
                            // Qur'an, so a reader in that order can find their place
                            // by it rather than by the written number. It is spelled
                            // out because a bare number under a count of ayas reads
                            // as a second count.
                            Text(
                              l.index_revealed_nth(
                                _ordinal(
                                  Localizations.localeOf(context).languageCode,
                                  sura.revelationOrder,
                                ),
                              ),
                              style: TextStyle(
                                fontSize: 10,
                                color: n.textAt(0.42),
                              ),
                            ),
                            const SizedBox(height: 4),
                            _bar(n, sura),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (widget.trailing case final trailing?) trailing(sura),
          ],
        ),
        ?below,
        const NocturneRule(fade: 30),
      ],
    );
  }

  Widget _bar(Nocturne n, SuraEntry sura) => ClipRRect(
    borderRadius: BorderRadius.circular(2),
    child: Container(
      height: 3,
      color: n.color('neutral-800'),
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: sura.understood / sura.ayahCount,
        child: Container(color: n.color('accent-700')),
      ),
    ),
  );
}

/// "1st", "22nd", "113th" in English; "1re", "22e", "113e" in French — the
/// ordinal the reader sees, agreeing with the feminine "sourate" it qualifies.
///
/// The suffix is the one reader-facing string that cannot live in the ARB:
/// gen-l10n rejects ICU `selectordinal`, and `plural`'s `=1 =2 =3` match only
/// the literal numbers, so 21 and 22 would come out "21th" and "22th". The
/// sentence around it is `index_revealed_nth`, which takes this already spelled.
///
// ponytail: two languages, inline. A third locale means a real ordinal
// formatter — reach for one then, not now.
String _ordinal(String languageCode, int n) {
  if (languageCode == 'fr') return n == 1 ? '${n}re' : '${n}e';
  final suffix = n % 100 >= 11 && n % 100 <= 13
      ? 'th'
      : switch (n % 10) {
          1 => 'st',
          2 => 'nd',
          3 => 'rd',
          _ => 'th',
        };
  return '$n$suffix';
}
