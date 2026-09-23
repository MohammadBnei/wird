import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import '../../data/outbox.dart';
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
    return Padding(
      padding: EdgeInsets.only(top: n.space('3')),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _parked.length == 1
                ? '1 change has not reached the server'
                : '${_parked.length} changes have not reached the server',
            style: TextStyle(fontSize: 12, color: n.text),
          ),
          SizedBox(height: n.space('1')),
          Text(
            'They are still on this phone. Send them again, or let them go.',
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
                      describeOp(op),
                      style: TextStyle(fontSize: 11, color: n.textAt(0.55)),
                    ),
                  ),
                  NocturneButton(
                    onPressed: () => _retry(op),
                    child: const Text('Send again'),
                  ),
                  NocturneButton(
                    onPressed: () => _discard(op),
                    child: const Text('Discard'),
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
String describeOp(PendingOp op) {
  final ayas = (op.body['ayah_ids'] as List?)?.length ?? 0;
  return switch (op.kind) {
    'ayah_understood' when ayas == 1 => 'An aya you marked understood',
    'ayah_understood' => '$ayas ayas you marked understood',
    'kept_upsert' => 'Something you kept',
    'kept_delete' => 'Something you removed from Kept',
    'set_recorded' => 'A set you read',
    'set_prayed' => 'A prayer you counted',
    'prefs_set' => 'Your reading order',
    _ => 'A change you made',
  };
}
