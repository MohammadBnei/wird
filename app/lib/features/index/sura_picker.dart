import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import '../../data/sets.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/nocturne.dart';
import '../../widgets/nocturne_input.dart';
import '../../widgets/nocturne_kicker.dart';
import '../../widgets/nocturne_rule.dart';
import '../../widgets/nocturne_segmented.dart';
import '../progress/passage.dart';
// The Arabic search folds names the way the voice folds what it hears, so the
// two never disagree about what a word is. Prayer imports the index for
// SuraEntry; this is the other direction.
import '../prayer/voice_follow.dart';
import 'aya_search.dart';
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

/// A sūra's name reduced to plain letters, so `Al-Fātiḥa`, `fatiha` and
/// `Al-Fatihah` meet. The corpus spells its names in plain ASCII and the
/// reader may not, so both sides fold.
String foldLatin(String s) {
  // A trailing h is how half the transliterations end a tāʾ marbūṭa and the
  // other half do not, so it never decides a match between names. Only
  // names: in running text, "faith" would turn into the French "fait".
  final folded = foldLetters(s);
  return folded.endsWith('h') ? folded.substring(0, folded.length - 1) : folded;
}

/// Latin text reduced to lower-case letters and digits, with the marks of a
/// transliteration and of French folded away — « prière » and "priere" meet,
/// and so do `ḥ-m-d` and "hmd". Spaces, punctuation, ʿ and ʾ go too: the aya
/// search matches across them.
///
/// ponytail: a table of the marks transliterations and French use, not a
/// Unicode decomposition. Dart has none built in; widen the table if a word
/// turns up that it misses.
String foldLetters(String s) {
  const marks = {
    'ā': 'a', 'á': 'a', 'à': 'a', 'â': 'a', 'ī': 'i', 'í': 'i', 'î': 'i', //
    'ū': 'u', 'ú': 'u', 'û': 'u', 'ḥ': 'h', 'ṣ': 's', 'ḍ': 'd', 'ṭ': 't', //
    'ẓ': 'z', 'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e', 'ï': 'i', 'ô': 'o', //
    'ö': 'o', 'ù': 'u', 'ü': 'u', 'ç': 'c', 'œ': 'oe', 'æ': 'ae',
  };
  final out = StringBuffer();
  // Code units rather than a split and a pattern per character: this folds
  // the whole of two translations, 1.7 million characters, as a picker opens.
  for (final unit in s.toLowerCase().codeUnits) {
    if ((unit >= 0x61 && unit <= 0x7A) || (unit >= 0x30 && unit <= 0x39)) {
      out.writeCharCode(unit);
    } else if (unit >= 0x80) {
      final plain = marks[String.fromCharCode(unit)];
      if (plain != null) out.write(plain);
    }
  }
  return out.toString();
}

/// The one list a reader chooses a sūra from, wherever they choose one: the
/// index and the prayer's passage chooser.
///
/// It lists in the reader's reading order, which a toggle above the list
/// turns for as long as the picker is open — Settings keeps the order the
/// reader reads in; this only changes how a sūra is looked for. A search
/// finds sūras by name or number, an aya by reference, ayas by their words in
/// Arabic, English or French, and ayas by a root. What a choice then does is
/// the screen's.
class SuraPicker extends StatefulWidget {
  const SuraPicker({
    super.key,
    required this.suras,
    required this.order,
    required this.onSura,
    required this.onRef,
    required this.goToHint,
    this.db,
    this.progress = false,
    this.exclude = const {},
    this.leading = const [],
    this.trailing,
    this.below,
  });

  /// Every sūra, in written order.
  final List<SuraEntry> suras;

  /// The order the list opens in: the reader's.
  final ReadingOrder order;
  final ValueChanged<SuraEntry> onSura;

  /// A reference typed in full, or an aya the search found, as an aya id.
  final ValueChanged<int> onRef;

  /// Under "Go to …": what choosing the reference does on this screen.
  final String goToHint;

  /// Where the words and roots are searched. Without it the search is names,
  /// numbers and references only.
  final Database? db;

  /// Whether a row shows how much of the sūra the reader has understood.
  final bool progress;

  /// Sūras never offered: not as a row, a reference or an aya found.
  final Set<int> exclude;

  /// Shown above the sūras while nothing is typed. With anything in it, the
  /// sūras are headed by the order they are listed in.
  final List<Widget> leading;

  /// At the end of a sūra's row, and under it.
  final Widget Function(SuraEntry)? trailing;
  final Widget? Function(SuraEntry)? below;

  @override
  State<SuraPicker> createState() => _SuraPickerState();
}

class _SuraPickerState extends State<SuraPicker> {
  final _field = TextEditingController();
  var _query = '';
  late var _order = widget.order;

  AyaSearch? _search;

  /// What the query found in the text, worked out once per query rather than
  /// on every build: the scan is the whole Qur'an in three languages. The
  /// query it was found for is kept, so a slow answer to an old query is
  /// dropped.
  ({String query, List<AyaHit> words, List<RootHit> roots})? _hits;

  @override
  void initState() {
    super.initState();
    // Read the text as the picker opens, not on the first keystroke, so the
    // first word typed is answered rather than waited on.
    if (widget.db case final db?) {
      unawaited(
        AyaSearch.of(db).then((s) {
          _search = s;
          _find();
        }, onError: (Object _) {}),
      );
    }
  }

  @override
  void didUpdateWidget(SuraPicker old) {
    super.didUpdateWidget(old);
    if (old.order != widget.order) _order = widget.order;
  }

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _type(String q) {
    setState(() => _query = q);
    _find();
  }

  Future<void> _find() async {
    final search = _search;
    final q = _query.trim();
    if (search == null || q.isEmpty) return;
    // A reference is not words, and the digits of one are in no aya.
    final words = RegExp(r'^[\d\s:.]+$').hasMatch(q)
        ? const <AyaHit>[]
        : search.words(q, exclude: widget.exclude);
    final roots = await search.roots(q, exclude: widget.exclude);
    if (mounted && _query.trim() == q) {
      setState(() => _hits = (query: q, words: words, roots: roots));
    }
  }

  bool _offered(int ayahId) => !widget.exclude.contains(ayahId ~/ 1000);

  @override
  Widget build(BuildContext context) {
    final n = Nocturne.of(context);
    final l = AppLocalizations.of(context)!;
    final query = _query.trim();
    final items = query.isEmpty ? _browse(n, l) : _found(n, l, query);
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            n.space('6'),
            n.space('2'),
            n.space('6'),
            n.space('2'),
          ),
          child: Stack(
            alignment: AlignmentDirectional.centerEnd,
            children: [
              NocturneInput(
                hint: l.chooser_search,
                controller: _field,
                onChanged: _type,
              ),
              if (query.isNotEmpty)
                Semantics(
                  button: true,
                  label: l.picker_clear,
                  excludeSemantics: true,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      _field.clear();
                      _type('');
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Icon(Icons.close, size: 14, color: n.textAt(0.6)),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(n.space('6'), 0, n.space('6'), 8),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: NocturneSegmented(
              options: [l.picker_mushaf, l.picker_revelation],
              selected: _order == ReadingOrder.mushaf ? 0 : 1,
              onChanged: (i) => setState(
                () =>
                    _order = i == 0 ? ReadingOrder.mushaf : ReadingOrder.nuzul,
              ),
            ),
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
            itemCount: items.length,
            itemBuilder: (context, i) => items[i](),
          ),
        ),
      ],
    );
  }

  /// Nothing typed: the screen's own rows, then every sūra, headed where a
  /// juz begins in written order and where Makkah gives way to Madinah in
  /// the order of revelation.
  List<Widget Function()> _browse(Nocturne n, AppLocalizations l) {
    final rev = _order == ReadingOrder.nuzul;
    final items = <Widget Function()>[
      for (final w in widget.leading) () => w,
      if (widget.leading.isNotEmpty)
        () => _header(
          n,
          l.chooser_all(
            rev ? l.picker_order_revelation : l.picker_order_mushaf,
          ),
        ),
    ];
    String? last;
    for (final s in inOrder(widget.suras, _order)) {
      if (widget.exclude.contains(s.id)) continue;
      final head = rev
          ? (s.madani ? l.picker_madani : l.picker_makki)
          : l.picker_juz(juzOf(s.id * 1000 + 1));
      // Written order opens under the list's own header, so its first juz
      // goes unsaid; by revelation the first header is the first thing said.
      if (head != last && (last != null || rev)) {
        items.add(() => _header(n, head));
      }
      last = head;
      items.add(() => _row(n, l, s));
    }
    return items;
  }

  /// Something typed: the reference it is, the sūras it names, the roots it
  /// names and the ayas whose words hold it.
  List<Widget Function()> _found(Nocturne n, AppLocalizations l, String query) {
    final ref = switch (parseRef(query, widget.suras)) {
      final id? when _offered(id) => id,
      _ => null,
    };
    final suras = inOrder([
      for (final s in searchSuras(widget.suras, query))
        if (!widget.exclude.contains(s.id)) s,
    ], _order);
    final hits = _hits?.query == query ? _hits : null;
    final roots = [
      for (final r in hits?.roots ?? const <RootHit>[])
        if (r.ayas.isNotEmpty) r,
    ];
    final words = ref != null ? const <AyaHit>[] : hits?.words ?? const [];
    final items = <Widget Function()>[
      if (ref != null) () => _goTo(n, l, ref),
      if (suras.isNotEmpty) () => _header(n, l.picker_suras),
      for (final s in suras) () => _row(n, l, s),
      for (final r in roots) ...[
        () => _header(n, l.picker_root(r.display, r.translit)),
        for (final a in r.ayas) () => _aya(n, a),
      ],
      if (words.isNotEmpty) () => _header(n, l.picker_containing(query)),
      for (final a in words) () => _aya(n, a),
    ];
    if (items.isEmpty) {
      items.add(
        () => Padding(
          padding: EdgeInsets.only(top: n.space('4')),
          child: Text(
            l.chooser_no_match(query),
            style: TextStyle(fontSize: 13, color: n.textAt(0.58)),
          ),
        ),
      );
    }
    return items;
  }

  Widget _header(Nocturne n, String text) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 6),
    child: NocturneKicker(text),
  );

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

  /// An aya the search found: where it is, its Arabic, and its meaning in
  /// the reader's language.
  Widget _aya(Nocturne n, AyaHit a) {
    final sura = widget.suras[a.id ~/ 1000 - 1];
    final meaning = Localizations.localeOf(context).languageCode == 'fr'
        ? a.fr
        : a.en;
    return InkWell(
      key: ValueKey('found-${a.id}'),
      onTap: () => widget.onRef(a.id),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: n.divider)),
        ),
        child: Row(
          spacing: 12,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '${sura.nameEn} ${sura.id}:${a.id % 1000}',
                    style: const TextStyle(fontSize: 14),
                  ),
                  Text(
                    a.ar,
                    textDirection: TextDirection.rtl,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: Nocturne.arabicFamily,
                      fontSize: 18,
                      height: 1.6,
                    ),
                  ),
                  Text(
                    meaning,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, color: n.textAt(0.58)),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 15, color: n.textAt(0.45)),
          ],
        ),
      ),
    );
  }

  Widget _row(Nocturne n, AppLocalizations l, SuraEntry sura) {
    final below = widget.below?.call(sura);
    final rev = _order == ReadingOrder.nuzul;
    final place = sura.madani ? l.picker_madani : l.picker_makki;
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
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  child: Row(
                    spacing: 12,
                    children: [
                      SizedBox(
                        width: 30,
                        child: Text(
                          '${rev ? sura.revelationOrder : sura.id}',
                          style: TextStyle(fontSize: 12, color: n.textAt(0.5)),
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    sura.nameEn,
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                ),
                                if (widget.progress)
                                  Text(
                                    '${sura.understood} / ${sura.ayahCount}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: n.textAt(0.55),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              [
                                l.picker_sura_sub(sura.ayahCount, place),
                                if (rev) l.picker_mushaf_n(sura.id),
                              ].join(' · '),
                              style: TextStyle(
                                fontSize: 11.5,
                                color: n.textAt(0.55),
                              ),
                            ),
                            if (widget.progress) ...[
                              const SizedBox(height: 4),
                              // The revelation order is the other way the app
                              // reads the Qur'an. It is spelled out because a
                              // bare number under a count of ayas reads as a
                              // second count.
                              Text(
                                l.index_revealed_nth(
                                  ordinal(
                                    Localizations.localeOf(context)
                                        .languageCode,
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
String ordinal(String languageCode, int n) {
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
