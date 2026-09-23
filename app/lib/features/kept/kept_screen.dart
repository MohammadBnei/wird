import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import '../../data/db.dart';
import '../../data/kept_repo.dart';
import '../../theme/nocturne.dart';
import '../../widgets/nocturne_input.dart';
import '../../widgets/nocturne_segmented.dart';
import '../../widgets/nocturne_tag.dart';

/// The design's own page gutter on this screen; it is not a step of the
/// space scale.
const _gutter = 20.0;

/// Screen 1e — the ayas, roots and notes the reader kept.
class KeptScreen extends StatefulWidget {
  const KeptScreen({super.key, required this.db});

  final Database db;

  @override
  State<KeptScreen> createState() => _KeptScreenState();
}

class _KeptScreenState extends State<KeptScreen> {
  var _kind = KeptKind.aya;
  var _search = '';
  List<KeptItem>? _items;

  /// The kin a root card shows, read once per root on screen. A kept list is
  /// short, so this stays a handful of queries rather than a join.
  final _kin = <String, RootDetail>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await keptItems(widget.db, kind: _kind, search: _search);
    for (final item in items) {
      final letters = item.rootLetters;
      if (item.kind != KeptKind.root || letters == null) continue;
      if (_kin.containsKey(letters)) continue;
      final detail = await rootDetail(widget.db, letters);
      if (detail != null) _kin[letters] = detail;
    }
    if (mounted) setState(() => _items = items);
  }

  Future<void> _forget(KeptItem item) async {
    await forget(widget.db, item.id);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final n = Nocturne.of(context);
    final items = _items;
    return Scaffold(
      backgroundColor: n.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _head(n),
            Expanded(
              child: items == null
                  ? const SizedBox.shrink()
                  : items.isEmpty
                  ? _nothingKept(n)
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(
                        _gutter,
                        16,
                        _gutter,
                        _gutter,
                      ),
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 11),
                      itemBuilder: (_, i) => Dismissible(
                        // Nothing in the design removes a kept item, and a
                        // list that only grows is a list nobody trusts. The
                        // platform's own swipe costs the screen no chrome.
                        key: ValueKey(items[i].id),
                        onDismissed: (_) => _forget(items[i]),
                        child: _card(n, items[i]),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _head(Nocturne n) => Padding(
    padding: const EdgeInsets.fromLTRB(_gutter, 8, _gutter, 0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Kept', style: Theme.of(context).textTheme.displaySmall),
        const SizedBox(height: 12),
        NocturneInput(
          hint: 'Search ayas, roots, your words',
          onChanged: (value) {
            _search = value;
            _load();
          },
        ),
        const SizedBox(height: 11),
        // The title and the search field want the whole gutter, so this
        // column stretches — and a stretched segmented control is handed a
        // tight full width its options cannot fill, leaving half a pill of
        // empty tube. It sizes to its three words, as settings' two do.
        Align(
          alignment: Alignment.centerLeft,
          child: NocturneSegmented(
            options: const ['Ayas', 'Roots', 'Notes'],
            selected: _kind.index,
            onChanged: (i) {
              setState(() => _kind = KeptKind.values[i]);
              _load();
            },
          ),
        ),
      ],
    ),
  );

  Widget _nothingKept(Nocturne n) => Padding(
    padding: const EdgeInsets.fromLTRB(_gutter, 16, _gutter, 0),
    child: Text(
      _search.isNotEmpty
          ? 'Nothing kept matches “$_search”.'
          : switch (_kind) {
              KeptKind.aya =>
                'No ayas kept yet. The bookmark on a set keeps '
                    'one here.',
              KeptKind.root =>
                'No roots kept yet. The keep icon on a root '
                    'keeps one here.',
              KeptKind.note =>
                'No notes yet. What you write on an aya is '
                    'kept here.',
            },
      style: TextStyle(fontSize: 12.5, height: 1.55, color: n.textAt(0.5)),
    ),
  );

  Widget _card(Nocturne n, KeptItem item) {
    final arabic = item.kind == KeptKind.note ? null : item.arabic;
    final kin = _kin[item.rootLetters]?.kin ?? const [];
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: n.surface,
        borderRadius: BorderRadius.circular(n.radius('md')),
        boxShadow: n.shadow('sm'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 7,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  _kicker(item),
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                    fontSize: 10,
                    height: 1.2,
                    letterSpacing: 0.1 * 10,
                    color: n.accent,
                  ),
                ),
              ),
              Text(
                _meta(item),
                style: TextStyle(
                  fontFamilyFallback: const [Nocturne.arabicFamily],
                  fontSize: 10,
                  height: 1.2,
                  color: n.textAt(0.58),
                ),
              ),
            ],
          ),
          if (arabic != null)
            Text(
              arabic,
              textDirection: TextDirection.rtl,
              style: TextStyle(
                fontFamily: Nocturne.arabicFamily,
                fontSize: 22,
                height: 1.7,
                color: n.text,
              ),
            ),
          // The design rules the reader's own words off from the revelation
          // with a dashed line, and only where both are on the card.
          if (arabic != null && item.body.isNotEmpty)
            SizedBox(
              width: double.infinity,
              height: 1,
              child: CustomPaint(painter: _Dashes(n.textAt(0.2))),
            ),
          if (item.body.isNotEmpty)
            Text(
              item.body,
              style: TextStyle(
                // A note about a word quotes the word: the reader's own line
                // is Latin with Arabic inside it.
                fontFamilyFallback: const [Nocturne.arabicFamily],
                fontSize: 12.5,
                height: 1.55,
                color: n.textAt(0.78),
              ),
            ),
          if (kin.isNotEmpty || item.tags.isNotEmpty)
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final word in kin) _arabicTag(n, word.text),
                for (final tag in item.tags)
                  if (tag != 'revisit')
                    NocturneTag(tag, variant: NocturneTagVariant.outline),
              ],
            ),
        ],
      ),
    );
  }

  String _kicker(KeptItem item) {
    if (item.kind == KeptKind.root) {
      return 'Root · ${item.rootLetters ?? ''}'.toUpperCase();
    }
    final at = item.ayahId == null
        ? item.kind.name
        : '${item.surahId} : ${item.ayahNumber}';
    return (item.flagged ? '$at · revisit' : at).toUpperCase();
  }

  String _meta(KeptItem item) {
    if (item.flagged && item.rootLetters != null) {
      return 'flagged for ${item.rootLetters}';
    }
    if (item.kind == KeptKind.root && item.ayahId != null) {
      return 'kept from ${item.surahId}:${item.ayahNumber}';
    }
    // The design counts a kept item's age in prayers. Prayers are not
    // recorded on the device yet, so it is counted in days until they are.
    final days = DateTime.now().difference(item.createdAt).inDays;
    return switch (days) {
      0 => 'today',
      1 => 'yesterday',
      _ => '$days days ago',
    };
  }

  /// The design sets a card's Arabic tags at 13px, which the shared tag does
  /// not carry.
  Widget _arabicTag(Nocturne n, String word) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
    decoration: BoxDecoration(
      color: n.color('neutral-800'),
      borderRadius: BorderRadius.circular(n.radius('md') * 0.75),
    ),
    child: Text(
      word,
      textDirection: TextDirection.rtl,
      style: TextStyle(
        fontFamily: Nocturne.arabicFamily,
        fontSize: 13,
        height: 1.2,
        color: n.color('neutral-100'),
      ),
    ),
  );
}

/// The card's dashed rule: 2px on, 5px off.
class _Dashes extends CustomPainter {
  const _Dashes(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    for (var x = 0.0; x < size.width; x += 7) {
      canvas.drawRect(Rect.fromLTWH(x, 0, 2, 1), paint);
    }
  }

  @override
  bool shouldRepaint(_Dashes old) => old.color != color;
}
