import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import '../../data/sets.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/nocturne.dart';
import '../../widgets/nocturne_button.dart';
import '../../widgets/nocturne_kicker.dart';
import '../index/index_screen.dart';
import '../index/sura_picker.dart';
import '../progress/passage.dart';
import 'prayer_plan.dart';

/// What the reader chose for a rakʿah: a passage, the first rakʿah's passage
/// again, or nothing after Al-Fātiḥa (a null set that is not [same]).
typedef PassageChoice = ({StudySet? set, bool same});

/// How long a passage takes, as the reader is told it: "about 40 s".
String aboutTime(AppLocalizations l, int words, int wpm) {
  final time = recitingTime(words, wpm);
  return time.inMinutes >= 1
      ? l.prepare_about_minutes(time.inMinutes)
      : l.prepare_about_seconds(time.inSeconds);
}

/// The passage chooser: the whole Qur'an, searched by sūra, reference, word
/// or root, and then the sūra as text, where the reader taps the range's
/// first aya and then its last.
///
/// A route of its own rather than a sheet, because the list is 114 sūras long
/// and the keyboard takes half the screen.
class PassageChooser extends StatefulWidget {
  const PassageChooser({
    super.key,
    required this.db,
    required this.order,
    required this.rakah,
    required this.suras,
    required this.wpm,
    this.continuing,
    this.after,
    this.first,
    this.recent = const [],
    this.current,
  });

  final Database db;
  final ReadingOrder order;

  /// The rakʿah the passage is for, from one. A later one is offered the
  /// first's passage again, and the ayas after it.
  final int rakah;
  final List<SuraEntry> suras;

  /// The pace the prayer is set to, which is how long a passage is said to
  /// take.
  final int wpm;

  /// The next unread passage: the first rakʿah's suggestion.
  final StudySet? continuing;

  /// The ayas after the previous rakʿah's passage: a later rakʿah's
  /// suggestion.
  final StudySet? after;

  /// The first rakʿah's passage, which a later one may repeat.
  final StudySet? first;
  final List<StudySet> recent;

  /// What the rakʿah recites now, which the chooser opens on.
  final PassageChoice? current;

  /// The back arrow over the range, which leads back to the list.
  static const changeSura = Key('change sura');

  /// One aya of the sūra in the range step.
  static Key aya(int n) => Key('aya $n');

  @override
  State<PassageChooser> createState() => _PassageChooserState();
}

class _PassageChooserState extends State<PassageChooser> {
  /// The range step, once a sūra is chosen: null while the list is showing.
  ({int sura, int from, int to})? _range;
  StudySet? _ranged;

  /// The Arabic of the sūra the range is in, one entry an aya, once read.
  ({int sura, List<String> ayas})? _text;

  /// Each aya's row, so the range and the overview bar can scroll to it.
  final _rows = <int, GlobalKey>{};

  /// Opens the range step on [sura], clamped to the ayas it has, and reads
  /// the ayas the range names.
  Future<void> _openRange(int sura, int from, int to) async {
    final count = widget.suras[sura - 1].ayahCount;
    final f = from.clamp(1, count);
    final t = to.clamp(f, count);
    final opening = _range?.sura != sura;
    // The old range's set goes with it: until the new one is read, the
    // Recite button may not stand for a range not chosen.
    setState(() {
      _range = (sura: sura, from: f, to: t);
      _ranged = null;
      if (opening) _rows.clear();
    });
    if (opening) unawaited(_readText(sura, f));
    final set = await ayaSet(
      widget.db,
      widget.order,
      sura * 1000 + f,
      ayas: t - f + 1,
    );
    if (mounted && _range == (sura: sura, from: f, to: t)) {
      setState(() => _ranged = set);
    }
  }

  Future<void> _readText(int sura, int from) async {
    final rows = await widget.db.query(
      'ayahs',
      columns: ['text_uthmani'],
      where: 'surah_id = ?',
      whereArgs: [sura],
      orderBy: 'number',
    );
    if (!mounted || _range?.sura != sura) return;
    setState(
      () => _text = (
        sura: sura,
        ayas: [for (final r in rows) r['text_uthmani']! as String],
      ),
    );
    _show(from);
  }

  /// Opens [set] in the range step when it lies inside one sūra, so the
  /// reader can still move its ends; otherwise it is chosen as it is.
  void _offer(StudySet set) {
    final first = set.ayas.first;
    final last = set.ayas.last;
    if (set.crossesSurah || first.surahId == 1) {
      _choose((set: set, same: false));
    } else {
      unawaited(_openRange(first.surahId, first.number, last.number));
    }
  }

  /// Where a sūra opens: whole when it is short; after the passage last
  /// recited from it, when there was one; otherwise its opening three ayas.
  void _openSura(SuraEntry s) {
    if (s.ayahCount <= 20) {
      unawaited(_openRange(s.id, 1, s.ayahCount));
      return;
    }
    final last = widget.recent
        .where((r) => r.ayas.last.surahId == s.id)
        .firstOrNull
        ?.ayas
        .last
        .number;
    final from = last != null && last < s.ayahCount ? last + 1 : 1;
    unawaited(_openRange(s.id, from, from + 2));
  }

  /// A rakʿah that has a passage opens on its range: changing how many ayas
  /// it recites is the common change, and should not cost a search for the
  /// sūra it is already in. The back arrow leads to the whole list.
  @override
  void initState() {
    super.initState();
    final ayas = widget.current?.set?.ayas ?? const <StudyAya>[];
    if (ayas.isNotEmpty &&
        ayas.first.surahId == ayas.last.surahId &&
        ayas.first.surahId != 1) {
      unawaited(
        _openRange(ayas.first.surahId, ayas.first.number, ayas.last.number),
      );
    }
  }

  void _choose(PassageChoice choice) => Navigator.of(context).pop(choice);

  void _toList() => setState(() {
    _range = null;
    _ranged = null;
    _anchor = null;
  });

  @override
  Widget build(BuildContext context) {
    final n = Nocturne.of(context);
    final l = AppLocalizations.of(context)!;
    final range = _range;
    final sura = range == null ? null : widget.suras[range.sura - 1];
    return Scaffold(
      backgroundColor: n.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 4),
              child: Row(
                spacing: 6,
                children: [
                  NocturneButton(
                    key: range == null ? null : PassageChooser.changeSura,
                    variant: NocturneButtonVariant.icon,
                    onPressed: () =>
                        range == null ? Navigator.of(context).pop() : _toList(),
                    child: Icon(
                      range == null ? Icons.close : Icons.chevron_left,
                      size: 18,
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          sura?.nameEn ?? l.chooser_title,
                          style: const TextStyle(fontSize: 16),
                        ),
                        Text(
                          sura == null
                              ? l.chooser_rakah(widget.rakah)
                              : l.range_about(
                                  sura.ayahCount,
                                  sura.madani
                                      ? l.picker_madani
                                      : l.picker_makki,
                                  sura.revelationOrder,
                                ),
                          style: TextStyle(
                            fontSize: 11.5,
                            color: n.textAt(0.58),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: range == null ? _list(n, l) : _rangeStep(n, l, range),
            ),
          ],
        ),
      ),
    );
  }

  Widget _list(Nocturne n, AppLocalizations l) {
    final later = widget.rakah > 1;
    final suggested = later ? widget.after : widget.continuing;
    return SuraPicker(
      db: widget.db,
      suras: widget.suras,
      order: widget.order,
      goToHint: l.chooser_go_to_hint,
      // Al-Fātiḥa is recited in every rakʿah already; offering it as the
      // passage would recite it twice and match every word against two places.
      exclude: const {1},
      onSura: _openSura,
      onRef: (ref) => _openRange(ref ~/ 1000, ref % 1000, ref % 1000),
      leading: [
        if (suggested != null)
          _card(
            n,
            kicker: later
                ? l.chooser_after(widget.rakah - 1)
                : l.chooser_continue,
            sub: later
                ? l.chooser_follows(passageTitle(widget.first!, widget.suras))
                : l.chooser_left_off,
            set: suggested,
          ),
        if (later && widget.first != null)
          _suggestion(
            n,
            l.chooser_same,
            passageTitle(widget.first!, widget.suras),
            onTap: () => _choose((set: null, same: true)),
          ),
        _suggestion(
          n,
          l.chooser_fatiha_only,
          l.chooser_fatiha_only_hint,
          onTap: () => _choose((set: null, same: false)),
        ),
        if (widget.recent.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 16, bottom: 6),
            child: NocturneKicker(l.chooser_recent),
          ),
        for (final set in widget.recent)
          _suggestion(
            n,
            passageTitle(set, widget.suras),
            [
              l.prepare_ayas(set.ayas.length),
              aboutTime(
                l,
                [for (final a in set.ayas) ...a.words].length,
                widget.wpm,
              ),
            ].join(' · '),
            onTap: () => _offer(set),
          ),
      ],
    );
  }

  /// The one suggestion drawn as a card: where the reader would go on from,
  /// with its first aya, so it is recognised before it is read.
  Widget _card(
    Nocturne n, {
    required String kicker,
    required String sub,
    required StudySet set,
  }) => InkWell(
    key: const Key('suggested'),
    onTap: () => _offer(set),
    child: Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: n.color('accent-900'),
        border: Border.all(color: n.color('accent-700')),
        borderRadius: BorderRadius.circular(n.radius('lg')),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            spacing: 8,
            children: [
              NocturneKicker(kicker, tone: KickerTone.accent),
              Expanded(
                child: Text(
                  sub,
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: n.textAt(0.62)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            passageTitle(set, widget.suras),
            style: TextStyle(fontSize: 15, color: n.color('accent-100')),
          ),
          const SizedBox(height: 4),
          Text(
            [for (final w in set.ayas.first.words) w.text].join(' '),
            textDirection: TextDirection.rtl,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: Nocturne.arabicFamily,
              fontSize: 19,
              height: 1.7,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _suggestion(
    Nocturne n,
    String title,
    String? sub, {
    required VoidCallback onTap,
  }) => InkWell(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: n.divider)),
      ),
      child: Row(
        spacing: 12,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 14)),
                if (sub != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    sub,
                    style: TextStyle(fontSize: 11.5, color: n.textAt(0.58)),
                  ),
                ],
              ],
            ),
          ),
          Icon(Icons.chevron_right, size: 15, color: n.textAt(0.45)),
        ],
      ),
    ),
  );

  /// Tapping an aya after the range is shown starts a new one there; the
  /// next tap is its other end.
  int? _anchor;

  /// Scrolls the sūra's text to [aya], a third of the way down.
  void _show(int aya) => WidgetsBinding.instance.addPostFrameCallback((_) {
    final row = _rows[aya]?.currentContext;
    if (row != null) {
      unawaited(Scrollable.ensureVisible(row, alignment: 0.1));
    }
  });

  void _tapAya(int sura, int aya) {
    final anchor = _anchor;
    if (anchor == null) {
      setState(() => _anchor = aya);
      unawaited(_openRange(sura, aya, aya));
    } else {
      setState(() => _anchor = null);
      unawaited(_openRange(sura, min(anchor, aya), max(anchor, aya)));
    }
  }

  /// Sets the range from a chip, and shows where it begins.
  void _set(int sura, int from, int to) {
    setState(() => _anchor = null);
    unawaited(_openRange(sura, from, to));
    _show(from);
  }

  int _words(String aya) => aya.split(' ').where((w) => w.isNotEmpty).length;

  Widget _rangeStep(
    Nocturne n,
    AppLocalizations l,
    ({int sura, int from, int to}) range,
  ) {
    final count = widget.suras[range.sura - 1].ayahCount;
    final set = _ranged;
    final text = _text?.sura == range.sura ? _text!.ayas : null;
    final k = range.to - range.from + 1;
    final words = text == null
        ? null
        : [for (var a = range.from; a <= range.to; a++) _words(text[a - 1])]
              .fold<int>(0, (x, y) => x + y);
    // The end a minute of recitation reaches from the range's first aya.
    int minute() {
      var t = range.from;
      var said = _words(text![t - 1]);
      while (t < count && said * 60 / widget.wpm < 60) {
        said += _words(text[t]);
        t++;
      }
      return t;
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _overview(n, l, range, count),
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                spacing: 10,
                children: [
                  Flexible(
                    child: Text(
                      _anchor == null ? l.range_tap_hint : l.range_last_hint,
                      style: TextStyle(
                        fontSize: 13,
                        color: n.color('accent-200'),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      words == null
                          ? ''
                          : l.range_meta(
                              k,
                              aboutTime(l, words, widget.wpm),
                              juzOf(range.sura * 1000 + range.from),
                            ),
                      textAlign: TextAlign.right,
                      style: TextStyle(fontSize: 11.5, color: n.textAt(0.58)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
            // ponytail: every aya laid out at once, which is what lets the
            // range and the overview bar scroll to one by its key. Al-Baqarah
            // is the worst at 286; a lazy list with an index-based scroll if
            // opening it is ever measured slow.
            child: Column(
              spacing: 6,
              children: [
                for (var aya = 1; aya <= count; aya++)
                  _ayaRow(
                    n,
                    aya,
                    text?[aya - 1],
                    inRange: aya >= range.from && aya <= range.to,
                    anchor: aya == _anchor,
                    onTap: () => _tapAya(range.sura, aya),
                  ),
              ],
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.only(top: 10),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: n.divider)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Row(
                  spacing: 6,
                  children: [
                    PrayerChip(
                      label: l.range_three,
                      selected: k == 3,
                      onTap: () => _set(range.sura, range.from, range.from + 2),
                    ),
                    if (text != null)
                      PrayerChip(
                        label: l.range_minute,
                        selected: false,
                        onTap: () => _set(range.sura, range.from, minute()),
                      ),
                    // A whole sūra is a passage only while it is a short one.
                    if (count > 1 && count <= 40)
                      PrayerChip(
                        label: l.range_whole,
                        selected: range.from == 1 && range.to == count,
                        onTap: () => _set(range.sura, 1, count),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
                child: NocturneButton(
                  variant: NocturneButtonVariant.primary,
                  block: true,
                  onPressed: set == null
                      ? null
                      : () => _choose((set: set, same: false)),
                  child: Text(
                    l.range_recite(
                      set == null ? '' : passageTitle(set, widget.suras),
                    ),
                    style: const TextStyle(fontSize: 14.5),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// The whole sūra as a thin line with the range on it. A tap scrolls the
  /// text to that point; it does not move the range.
  Widget _overview(
    Nocturne n,
    AppLocalizations l,
    ({int sura, int from, int to}) range,
    int count,
  ) => Semantics(
    label: l.range_overview,
    child: LayoutBuilder(
      builder: (context, box) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) => _show(
          (1 + (d.localPosition.dx / box.maxWidth * count).floor()).clamp(
            1,
            count,
          ),
        ),
        child: SizedBox(
          height: 16,
          child: Stack(
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: 7,
                height: 2,
                child: ColoredBox(color: n.color('neutral-800')),
              ),
              Positioned(
                left: (range.from - 1) / count * box.maxWidth,
                top: 5,
                height: 6,
                width: max(
                  4,
                  (range.to - range.from + 1) / count * box.maxWidth,
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: n.accent,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _ayaRow(
    Nocturne n,
    int aya,
    String? ar, {
    required bool inRange,
    required bool anchor,
    required VoidCallback onTap,
  }) => Semantics(
    key: _rows.putIfAbsent(aya, GlobalKey.new),
    button: true,
    selected: inRange,
    child: GestureDetector(
      key: PassageChooser.aya(aya),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: anchor
              ? n.color('accent-800')
              : inRange
              ? n.color('accent-900')
              : null,
          border: Border.all(
            color: inRange ? n.color('accent-700') : Colors.transparent,
          ),
          borderRadius: BorderRadius.circular(n.radius('lg')),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 12,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 4),
              constraints: const BoxConstraints(minWidth: 26),
              height: 22,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: inRange ? n.accent : n.color('neutral-800'),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Text(
                '$aya',
                style: TextStyle(
                  fontSize: 11,
                  color: inRange ? n.bg : n.textAt(0.58),
                ),
              ),
            ),
            Expanded(
              child: Text(
                ar ?? '',
                textDirection: TextDirection.rtl,
                style: const TextStyle(
                  fontFamily: Nocturne.arabicFamily,
                  fontSize: 21,
                  height: 1.8,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// A labelled number with a minus and a plus, as the design draws every count
/// it lets the reader change.
class PrayerStepper extends StatelessWidget {
  const PrayerStepper({
    super.key,
    required this.label,
    required this.value,
    required this.less,
    required this.more,
    this.onLess,
    this.onMore,
    this.hint,
  });

  final String label;
  final String? hint;
  final int value;

  /// What the minus and plus do, for a reader who cannot see them.
  final String less;
  final String more;
  final VoidCallback? onLess;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    final n = Nocturne.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: n.divider)),
      ),
      child: Row(
        spacing: 10,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 14)),
                if (hint != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    hint!,
                    style: TextStyle(fontSize: 11.5, color: n.textAt(0.58)),
                  ),
                ],
              ],
            ),
          ),
          _step(less, '−', onLess),
          SizedBox(
            width: 30,
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
          ),
          _step(more, '+', onMore),
        ],
      ),
    );
  }

  Widget _step(String label, String sign, VoidCallback? onPressed) => Semantics(
    label: label,
    button: true,
    excludeSemantics: true,
    child: NocturneButton(
      variant: NocturneButtonVariant.icon,
      onPressed: onPressed,
      child: Text(sign, style: const TextStyle(fontSize: 16)),
    ),
  );
}

/// A rounded choice among a few, selected or not.
class PrayerChip extends StatelessWidget {
  const PrayerChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final n = Nocturne.of(context);
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: selected ? n.color('accent-900') : n.surface,
            border: Border.all(color: selected ? n.accent : n.divider),
            borderRadius: BorderRadius.circular(16),
          ),
          // Centred on its own width: an aligned container would stretch to
          // the row and every chip would be a full-width bar.
          child: Center(
            widthFactor: 1,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                color: selected ? n.color('accent-100') : n.text,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
