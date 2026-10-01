import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import '../../data/sets.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/nocturne.dart';
import '../../widgets/nocturne_button.dart';
import '../../widgets/nocturne_input.dart';
import '../../widgets/nocturne_kicker.dart';
import '../index/index_screen.dart';
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

  @override
  State<PassageChooser> createState() => _PassageChooserState();
}

class _PassageChooserState extends State<PassageChooser> {
  var _query = '';

  /// The range step, once a sūra is chosen: null while the list is showing.
  ({int sura, int from, int to})? _range;
  StudySet? _ranged;

  /// Opens the range step on [sura], clamped to the ayas it has, and reads
  /// the ayas the range names.
  Future<void> _openRange(int sura, int from, int to) async {
    final count = widget.suras[sura - 1].ayahCount;
    final f = from.clamp(1, count);
    final t = to.clamp(f, count);
    setState(() => _range = (sura: sura, from: f, to: t));
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
    final ref = parseRef(_query, widget.suras);
    final head = RegExp(r'^\s*(\d{1,3})\s*[:.]').firstMatch(_query);
    // A reference names one sūra; the list narrows to it rather than to every
    // sūra with those digits in its number.
    final rows = head != null
        ? [
            for (final s in widget.suras)
              if (s.id == int.parse(head[1]!)) s,
          ]
        : searchSuras(widget.suras, _query);
    // Al-Fātiḥa is recited in every rakʿah already; offering it as the
    // passage would recite it twice and match every word against two places.
    final offered = [
      for (final s in rows)
        if (s.id != 1) s,
    ];
    final current = widget.current;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 6, 18, 8),
          child: NocturneInput(
            hint: l.chooser_search,
            onChanged: (q) => setState(() => _query = q),
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 20),
            children: [
              if (ref != null) _goTo(n, l, ref),
              if (_query.trim().isEmpty) ...[
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
                  marked:
                      current != null && current.set == null && !current.same,
                  onTap: () => _choose((set: null, same: false)),
                ),
                const SizedBox(height: 16),
                NocturneKicker(l.chooser_all),
              ],
              for (final s in offered)
                InkWell(
                  onTap: () => _openRange(
                    s.id,
                    1,
                    // A short sūra is offered whole; a long one, its opening.
                    s.ayahCount <= 10 ? s.ayahCount : 3,
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: n.divider)),
                    ),
                    child: Row(
                      spacing: 12,
                      children: [
                        SizedBox(
                          width: 30,
                          child: Text(
                            '${s.id}',
                            style: TextStyle(
                              fontSize: 12,
                              color: n.textAt(0.5),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            s.nameEn,
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                        Text(
                          l.prepare_ayas(s.ayahCount),
                          style: TextStyle(
                            fontSize: 11.5,
                            color: n.textAt(0.55),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (_query.trim().isNotEmpty && offered.isEmpty && ref == null)
                Padding(
                  padding: const EdgeInsets.only(top: 20),
                  child: Text(
                    l.chooser_no_match(_query.trim()),
                    style: TextStyle(fontSize: 13, color: n.textAt(0.58)),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _goTo(Nocturne n, AppLocalizations l, int ref) {
    final sura = ref ~/ 1000;
    final aya = ref % 1000;
    return InkWell(
      onTap: () => _openRange(sura, aya, aya + 2),
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
                    l.chooser_go_to_hint,
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

  Widget _rangeStep(
    Nocturne n,
    AppLocalizations l,
    ({int sura, int from, int to}) range,
  ) {
    final count = widget.suras[range.sura - 1].ayahCount;
    final set = _ranged;
    final width = range.to - range.from + 1;
    final spans = [
      (label: l.prepare_ayas(1), from: range.from, to: range.from),
      (label: l.prepare_ayas(3), from: range.from, to: range.from + 2),
      (label: l.prepare_ayas(5), from: range.from, to: range.from + 4),
      if (count <= 40) (label: l.range_whole, from: 1, to: count),
    ];
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: n.surface,
                  borderRadius: BorderRadius.circular(n.radius('lg')),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    NocturneKicker(
                      '${widget.suras[range.sura - 1].nameEn} '
                      '${range.sura}:${range.from}',
                      tone: KickerTone.accent,
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      width: double.infinity,
                      child: Text(
                        set == null
                            ? ''
                            : [for (final w in set.ayas.first.words) w.text]
                                  .join(' '),
                        textDirection: TextDirection.rtl,
                        style: const TextStyle(
                          fontFamily: Nocturne.arabicFamily,
                          fontSize: 24,
                          height: 1.75,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        l.prepare_ayas(width),
                        l.range_in_sura(count),
                      ].join(' · '),
                      style: TextStyle(fontSize: 11.5, color: n.textAt(0.58)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              PrayerStepper(
                label: l.range_from,
                value: range.from,
                less: l.range_earlier,
                more: l.range_later,
                onLess: range.from > 1
                    ? () => _openRange(range.sura, range.from - 1, range.to)
                    : null,
                onMore: range.from < count
                    ? () => _openRange(
                        range.sura,
                        range.from + 1,
                        range.to < range.from + 1 ? range.from + 1 : range.to,
                      )
                    : null,
              ),
              PrayerStepper(
                label: l.range_to,
                value: range.to,
                less: l.range_earlier,
                more: l.range_later,
                onLess: range.to > range.from
                    ? () => _openRange(range.sura, range.from, range.to - 1)
                    : null,
                onMore: range.to < count
                    ? () => _openRange(range.sura, range.from, range.to + 1)
                    : null,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final span in spans)
                    PrayerChip(
                      label: span.label,
                      selected:
                          span.from == range.from &&
                          span.to.clamp(1, count) == range.to,
                      onTap: () => _openRange(range.sura, span.from, span.to),
                    ),
                ],
              ),
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
