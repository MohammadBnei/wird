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
import 'prayer_plan.dart';

/// What the reader chose for a rakʿah: a passage, the first rakʿah's passage
/// again, or nothing after Al-Fātiḥa (a null set that is not [same]).
typedef PassageChoice = ({StudySet? set, bool same});

/// The passage chooser: the whole Qur'an, searched by sūra name or number or
/// by a reference like 2:255, and then the range inside the sūra.
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
    this.continuing,
    this.recent = const [],
    this.current,
  });

  final Database db;
  final ReadingOrder order;

  /// The rakʿah the passage is for, from one. The second is offered the
  /// first's passage again.
  final int rakah;
  final List<SuraEntry> suras;

  /// The next unread passage, which is where a reader who has not chosen
  /// anything would go on from.
  final StudySet? continuing;
  final List<StudySet> recent;

  /// What the rakʿah recites now, so the suggestion that matches is marked.
  final PassageChoice? current;

  /// The sūra at the top of the range, which leads back to the list.
  static const changeSura = Key('change sura');

  /// One aya's number in the range grid.
  static Key aya(int n) => Key('aya $n');

  @override
  State<PassageChooser> createState() => _PassageChooserState();
}

class _PassageChooserState extends State<PassageChooser> {
  /// The range step, once a sūra is chosen: null while the list is showing.
  ({int sura, int from, int to})? _range;
  StudySet? _ranged;

  /// Opens the range step on [sura], clamped to the ayas it has, and reads
  /// the ayas the range names.
  Future<void> _openRange(int sura, int from, int to) async {
    final count = widget.suras[sura - 1].ayahCount;
    final f = from.clamp(1, count);
    final t = to.clamp(f, count);
    final opening = _range?.sura != sura;
    // The old range's set goes with it: until the new one is read, neither
    // its first aya nor the Recite button may stand for a range not chosen.
    setState(() {
      _range = (sura: sura, from: f, to: t);
      _ranged = null;
    });
    if (opening) _showFirst();
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

  @override
  Widget build(BuildContext context) {
    final n = Nocturne.of(context);
    final l = AppLocalizations.of(context)!;
    final range = _range;
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
                    variant: NocturneButtonVariant.icon,
                    onPressed: () => range == null
                        ? Navigator.of(context).pop()
                        : setState(() {
                            _range = null;
                            _ranged = null;
                          }),
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
                          range == null
                              ? l.chooser_title
                              : widget.suras[range.sura - 1].nameEn,
                          style: const TextStyle(fontSize: 16),
                        ),
                        Text(
                          l.chooser_rakah(widget.rakah),
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
    final current = widget.current;
    return SuraPicker(
      suras: widget.suras,
      order: widget.order,
      goToHint: l.chooser_go_to_hint,
      // Al-Fātiḥa is recited in every rakʿah already; offering it as the
      // passage would recite it twice and match every word against two places.
      exclude: const {1},
      onSura: (s) => _openRange(
        s.id,
        1,
        // A short sūra is offered whole; a long one, its opening.
        s.ayahCount <= 10 ? s.ayahCount : 3,
      ),
      onRef: (ref) => _openRange(ref ~/ 1000, ref % 1000, ref % 1000 + 2),
      leading: [
        const SizedBox(height: 8),
        NocturneKicker(l.chooser_suggested),
        if (widget.rakah == 2)
          _suggestion(
            n,
            l.chooser_same,
            null,
            marked: current?.same ?? false,
            onTap: () => _choose((set: null, same: true)),
          ),
        if (widget.continuing case final next?)
          _suggestion(
            n,
            l.chooser_continue,
            passageTitle(next, widget.suras),
            onTap: () => _choose((set: next, same: false)),
          ),
        for (final set in widget.recent)
          _suggestion(
            n,
            passageTitle(set, widget.suras),
            l.chooser_recent,
            marked: current?.set?.id == set.id,
            onTap: () => _choose((set: set, same: false)),
          ),
        _suggestion(
          n,
          l.chooser_fatiha_only,
          l.chooser_fatiha_only_hint,
          marked: current != null && current.set == null && !current.same,
          onTap: () => _choose((set: null, same: false)),
        ),
        const SizedBox(height: 16),
        NocturneKicker(l.chooser_all),
      ],
    );
  }

  Widget _suggestion(
    Nocturne n,
    String title,
    String? sub, {
    bool marked = false,
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
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: marked ? n.accent : Colors.transparent,
            ),
          ),
        ],
      ),
    ),
  );

  /// Tapping an aya after the range is shown starts a new one there; the
  /// next tap is its other end.
  int? _anchor;

  /// The range's first aya in the grid, scrolled to when the step opens: in a
  /// long sūra it is otherwise a few hundred numbers down.
  final _first = GlobalKey();

  void _showFirst() => WidgetsBinding.instance.addPostFrameCallback((_) {
    final cell = _first.currentContext;
    if (cell != null) {
      unawaited(Scrollable.ensureVisible(cell, alignment: 0.3));
    }
  });

  void _tapAya(int sura, int aya) {
    final anchor = _anchor;
    if (anchor == null) {
      _anchor = aya;
      unawaited(_openRange(sura, aya, aya));
    } else {
      _anchor = null;
      unawaited(_openRange(sura, min(anchor, aya), max(anchor, aya)));
    }
  }

  Widget _rangeStep(
    Nocturne n,
    AppLocalizations l,
    ({int sura, int from, int to}) range,
  ) {
    final sura = widget.suras[range.sura - 1];
    final count = sura.ayahCount;
    final set = _ranged;
    return Column(
      children: [
        // The sūra, what it says, and how to choose stand still; only the
        // numbers scroll, so a long sūra never carries them off.
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The sūra, and the way to another one, at the top where the
              // eye starts: changing it should not be a hunt for a back arrow.
              InkWell(
                key: PassageChooser.changeSura,
                onTap: () => setState(() {
                  _range = null;
                  _ranged = null;
                  _anchor = null;
                }),
                borderRadius: BorderRadius.circular(n.radius('lg')),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: n.surface,
                    borderRadius: BorderRadius.circular(n.radius('lg')),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l.range_sura(sura.id, sura.nameEn),
                              style: const TextStyle(fontSize: 16),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              l.range_in_sura(count),
                              style: TextStyle(
                                fontSize: 11.5,
                                color: n.textAt(0.58),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        l.range_change_sura,
                        style: TextStyle(fontSize: 12.5, color: n.accent),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // The first aya of the range, so the reader sees what they are
              // about to recite rather than only its number.
              SizedBox(
                width: double.infinity,
                child: Text(
                  set == null
                      ? ''
                      : [for (final w in set.ayas.first.words) w.text]
                            .join(' '),
                  textDirection: TextDirection.rtl,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: Nocturne.arabicFamily,
                    fontSize: 24,
                    height: 1.75,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                l.range_tap_hint,
                style: TextStyle(fontSize: 12, color: n.textAt(0.66)),
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
            children: [
              Wrap(
                children: [
                  for (var aya = 1; aya <= count; aya++)
                    _ayaCell(
                      n,
                      aya,
                      key: aya == range.from ? _first : null,
                      inRange: aya >= range.from && aya <= range.to,
                      end: aya == range.from || aya == range.to,
                      onTap: () => _tapAya(range.sura, aya),
                    ),
                ],
              ),
              // A whole sūra is a passage only while it is a short one.
              if (count > 1 && count <= 40) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: PrayerChip(
                    label: l.range_whole,
                    selected: range.from == 1 && range.to == count,
                    onTap: () {
                      _anchor = null;
                      unawaited(_openRange(range.sura, 1, count));
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: n.divider)),
          ),
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
    );
  }

  Widget _ayaCell(
    Nocturne n,
    int aya, {
    Key? key,
    required bool inRange,
    required bool end,
    required VoidCallback onTap,
  }) => Semantics(
    key: key,
    button: true,
    selected: inRange,
    // 48 to the finger, 40 to the eye: the gap between cells is the margin.
    child: GestureDetector(
      key: PassageChooser.aya(aya),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox.square(
        dimension: 48,
        child: Center(
          child: Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: end
                  ? n.accent
                  : inRange
                  ? n.color('accent-900')
                  : n.surface,
              border: Border.all(color: inRange ? n.accent : n.divider),
              borderRadius: BorderRadius.circular(n.radius('md')),
            ),
            child: Text(
              '$aya',
              style: TextStyle(
                fontSize: 13,
                color: end ? n.bg : (inRange ? n.color('accent-100') : n.text),
              ),
            ),
          ),
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
