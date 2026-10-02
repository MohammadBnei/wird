import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import '../../data/db.dart';
import '../../data/sets.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/nocturne.dart';
import 'sura_picker.dart';

/// One sūra as the index lists it: what it is called, when and where it was
/// revealed, and how much of it the reader has understood.
typedef SuraEntry = ({
  int id,
  String nameEn,
  String nameAr,
  int revelationOrder,
  bool madani,
  int ayahCount,
  int understood,
});

/// All 114, in written order whatever the reader reads in, with the reader's progress against each.
Future<List<SuraEntry>> suraIndex(Database db) async {
  final rows = await db.rawQuery('''
    SELECT s.id, s.name_en, s.name_ar, s.revelation_order,
           s.revelation_place, s.ayah_count,
           COUNT(u.ayah_id) AS understood
      FROM surahs s
      LEFT JOIN ayahs a ON a.surah_id = s.id
      LEFT JOIN ayah_understood u ON u.ayah_id = a.id
     GROUP BY s.id
     ORDER BY s.id''');
  return [
    for (final row in rows)
      (
        id: row['id']! as int,
        nameEn: row['name_en']! as String,
        nameAr: row['name_ar']! as String,
        revelationOrder: row['revelation_order']! as int,
        madani: row['revelation_place'] == 'madinah',
        ayahCount: row['ayah_count']! as int,
        understood: row['understood']! as int,
      ),
  ];
}

/// The index the design never drew.
///
/// Every screen in the design is downstream of the walk, so the app hands the
/// reader the next unread set and has no other door into the text. This is the
/// other door: a reader who wants Al-Fātiḥa, or the aya they were thinking
/// about, asks for it here.
///
/// It opens nothing itself. The aya the reader chooses is popped back up the
/// stack to screen 1a, which is the app's initial route and the one screen that
/// reads an aya — so there is never a second reader, and never a second live
/// audio player, stacked on the first.
///
/// A sūra row answers with its first aya, because choosing a sūra means
/// reading it. The numbers behind the arrow are for the reader who wants a
/// particular aya of a long one, which is a second, rarer intent and does not
/// get the whole row.
class IndexScreen extends StatefulWidget {
  const IndexScreen({super.key, required this.db});

  final Database db;

  @override
  State<IndexScreen> createState() => _IndexScreenState();
}

class _IndexScreenState extends State<IndexScreen> {
  List<SuraEntry>? _suras;
  ReadingOrder _order = ReadingOrder.mushaf;

  /// The sūra whose aya numbers are showing. A sūra is 286 ayas at its
  /// longest, so they are unfolded one sūra at a time rather than all at once.
  int? _opened;

  /// Leaves the index on [ayahId], which screen 1a opens the sūra at.
  void _read(int ayahId) => Navigator.of(context).pop(ayahId);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final suras = await suraIndex(widget.db);
    final order = await readingOrder(widget.db);
    if (mounted) {
      setState(() {
        _suras = suras;
        _order = order;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = Nocturne.of(context);
    final suras = _suras;
    return Scaffold(
      backgroundColor: n.bg,
      body: SafeArea(
        child: suras == null
            ? const SizedBox.shrink()
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _header(n),
                  Expanded(
                    child: SuraPicker(
                      db: widget.db,
                      suras: suras,
                      order: _order,
                      progress: true,
                      goToHint: AppLocalizations.of(context)!.index_go_to_hint,
                      onSura: (sura) => _read(sura.id * 1000 + 1),
                      onRef: _read,
                      trailing: (sura) => _arrow(n, sura),
                      below: (sura) =>
                          _opened == sura.id ? _ayas(n, sura) : null,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _header(Nocturne n) => Padding(
    padding: EdgeInsets.fromLTRB(n.space('6'), n.space('2'), n.space('6'), 0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppLocalizations.of(context)!.index_kicker,
          style: TextStyle(
            fontSize: 10,
            height: 1.2,
            letterSpacing: 0.11 * 10,
            color: n.accent,
          ),
        ),
        SizedBox(height: n.space('1')),
        Text(
          AppLocalizations.of(context)!.index_title,
          style: Theme.of(context).textTheme.displaySmall,
        ),
        SizedBox(height: n.space('1')),
        Text(
          AppLocalizations.of(context)!.index_hint,
          style: TextStyle(fontSize: 10.5, color: n.textAt(0.45)),
        ),
      ],
    ),
  );

  Widget _arrow(Nocturne n, SuraEntry sura) {
    final opened = _opened == sura.id;
    return Semantics(
      button: true,
      label: AppLocalizations.of(context)!.index_pick_aya(sura.nameEn),
      child: GestureDetector(
        key: ValueKey('ayas-${sura.id}'),
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _opened = opened ? null : sura.id),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: n.space('2'),
            vertical: n.space('3'),
          ),
          child: Icon(
            opened ? Icons.expand_less : Icons.expand_more,
            size: 18,
            color: n.color('accent-300'),
          ),
        ),
      ),
    );
  }

  Widget _ayas(Nocturne n, SuraEntry sura) => Padding(
    padding: EdgeInsets.only(bottom: n.space('3')),
    child: Wrap(
      spacing: n.space('2'),
      runSpacing: n.space('2'),
      children: [
        for (var number = 1; number <= sura.ayahCount; number++)
          GestureDetector(
            key: ValueKey('aya-${sura.id * 1000 + number}'),
            behavior: HitTestBehavior.opaque,
            onTap: () => _read(sura.id * 1000 + number),
            child: Container(
              width: 34,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border.all(color: n.color('accent-700')),
                borderRadius: BorderRadius.circular(n.radius('sm')),
              ),
              child: Text(
                '$number',
                style: TextStyle(fontSize: 11, color: n.color('accent-300')),
              ),
            ),
          ),
      ],
    ),
  );
}
