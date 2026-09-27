import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import '../../data/outbox.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/nocturne.dart';
import '../../widgets/nocturne_button.dart';

/// What the reader is told about writes the server would not take.
///
/// A write that cannot land and that nobody mentions is indistinguishable from
/// a write that never happened, so the parked ops are named here, in 1a's
/// settings panel, with a way to send them again or to let them go.
///
/// Two rules shape it. It is silent when the outbox is healthy — the reader
/// with nothing parked sees nothing new. And it belongs to settings alone: the
/// prayer screen may never raise it, because a write that failed is not the
/// reader's business while they are praying.
class ParkedWrites extends StatefulWidget {
  const ParkedWrites({super.key, required this.db});

  final Database db;

  @override
  State<ParkedWrites> createState() => _ParkedWritesState();
}

class _ParkedWritesState extends State<ParkedWrites> {
  List<PendingOp> _parked = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final parked = await deadLettered(widget.db);
    if (mounted) setState(() => _parked = parked);
  }

  Future<void> _retry(PendingOp op) async {
    await retry(widget.db, op.id);
    await _load();
  }

  Future<void> _discard(PendingOp op) async {
    await discard(widget.db, op.id);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_parked.isEmpty) return const SizedBox.shrink();
    final n = Nocturne.of(context);
    final l = AppLocalizations.of(context)!;
    return Padding(
      padding: EdgeInsets.only(top: n.space('3')),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.settingsParkedCount(_parked.length),
            style: TextStyle(fontSize: 12, color: n.text),
          ),
          SizedBox(height: n.space('1')),
          Text(
            l.settingsParkedCaption,
            style: TextStyle(fontSize: 10.5, color: n.textAt(0.42)),
          ),
          for (final op in _parked)
            Padding(
              padding: EdgeInsets.only(top: n.space('2')),
              child: Row(
                spacing: n.space('2'),
                children: [
                  Expanded(
                    child: Text(
                      describeOp(l, op),
                      style: TextStyle(fontSize: 11, color: n.textAt(0.55)),
                    ),
                  ),
                  NocturneButton(
                    onPressed: () => _retry(op),
                    child: Text(l.settingsSendAgain),
                  ),
                  NocturneButton(
                    onPressed: () => _discard(op),
                    child: Text(l.settingsDiscard),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// The op in the words the reader made it in, not the words the wire uses.
///
/// The kinds themselves stay as they are: `ayah_understood` and the rest are
/// what the server was sent and what the outbox stored, so translating one
/// would park the write under a name no row carries.
String describeOp(AppLocalizations l, PendingOp op) {
  final ayas = (op.body['ayah_ids'] as List?)?.length ?? 0;
  return switch (op.kind) {
    'ayah_understood' => l.settingsParkedUnderstood(ayas),
    'kept_upsert' => l.settingsParkedKept,
    'kept_delete' => l.settingsParkedUnkept,
    'set_recorded' => l.settingsParkedSetRead,
    'set_prayed' => l.settingsParkedPrayer,
    'prefs_set' => l.settingsParkedOrder,
    'report_written' => l.settingsParkedReport,
    _ => l.settingsParkedOther,
  };
}
