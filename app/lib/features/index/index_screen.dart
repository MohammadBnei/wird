import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import '../../theme/nocturne.dart';
import '../../widgets/nocturne_button.dart';
import '../../widgets/nocturne_rule.dart';

/// One sūra as the index lists it: what it is called, when it was revealed,
/// and how much of it the reader has understood.
typedef SuraEntry = ({
  int id,
  String nameEn,
  String nameAr,
  int revelationOrder,
  int ayahCount,
  int understood,
});

/// All 114, in written order, with the reader's progress against each.
Future<List<SuraEntry>> suraIndex(Database db) async {
  final rows = await db.rawQuery('''
    SELECT s.id, s.name_en, s.name_ar, s.revelation_order, s.ayah_count,
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
class IndexScreen extends StatefulWidget {
  const IndexScreen({super.key, required this.db});

  final Database db;

  @override
  State<IndexScreen> createState() => _IndexScreenState();
}

class _IndexScreenState extends State<IndexScreen> {
  List<SuraEntry>? _suras;

  /// The sūra whose ayas are showing. A sūra is 286 ayas at its longest, so
  /// they are opened one sūra at a time rather than all at once.
  int? _opened;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final suras = await suraIndex(widget.db);
    if (mounted) setState(() => _suras = suras);
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
                    child: ListView.builder(
                      padding: EdgeInsets.fromLTRB(
                        n.space('6'),
                        0,
                        n.space('6'),
                        n.space('8'),
                      ),
                      itemCount: suras.length,
                      itemBuilder: (context, i) => _row(n, suras[i]),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _header(Nocturne n) => Padding(
    padding: EdgeInsets.fromLTRB(n.space('6'), n.space('2'), n.space('6'), 0),
    child: Row(
      spacing: n.space('3'),
      children: [
        NocturneButton(
          variant: NocturneButtonVariant.icon,
          onPressed: () => Navigator.of(context).maybePop(),
          child: const Icon(Icons.arrow_back_ios_new, size: 16),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'THE WHOLE QUR’AN',
                style: TextStyle(
                  fontSize: 10,
                  height: 1.2,
                  letterSpacing: 0.11 * 10,
                  color: n.accent,
                ),
              ),
              SizedBox(height: n.space('1')),
              Text(
                'All 114',
                style: Theme.of(context).textTheme.displaySmall,
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _row(Nocturne n, SuraEntry sura) {
    final opened = _opened == sura.id;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          key: ValueKey('sura-${sura.id}'),
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _opened = opened ? null : sura.id),
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
                      color: n.textAt(opened ? 1 : 0.75),
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
                      // by it rather than by the written number.
                      Text(
                        'Revealed ${sura.revelationOrder}',
                        style: TextStyle(fontSize: 10, color: n.textAt(0.42)),
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
        if (opened) _ayas(n, sura),
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
            onTap: () => Navigator.of(context).pop(sura.id * 1000 + number),
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
