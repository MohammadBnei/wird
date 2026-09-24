import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import '../../theme/nocturne.dart';
import '../../widgets/nocturne_button.dart';
import '../../widgets/nocturne_input.dart';
import '../../widgets/nocturne_rule.dart';
import '../../widgets/nocturne_segmented.dart';
import 'report.dart';

/// Where a reader says what went wrong, what is missing, or what could be
/// better.
///
/// Two things this screen owes the reader. The context is gathered rather than
/// asked for — nobody should have to find their build number to report that
/// the audio stops — and it is then shown in full, because an app that asks to
/// transmit something owes the person a plain look at what it is sending.
///
/// The send queues and returns. There is no spinner and no failure to show,
/// which is the same contract as marking a set understood: the write is local
/// and the flush is somebody else's problem.
class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key, required this.db, required this.from});

  final Database db;

  /// The route the reader was on when they opened this. It travels with the
  /// report so a bug arrives attached to a screen.
  final String from;

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

/// How close to [reportMaxChars] the reader has to be before the screen
/// mentions it: a paragraph or so.
const _nearTheEnd = 200;

class _ReportScreenState extends State<ReportScreen> {
  final _text = TextEditingController();
  ReportKind _kind = ReportKind.bug;

  /// The four values that will be sent, read once. Null until the corpus
  /// answers, which is also how the send stays disabled until there is
  /// something honest to show.
  Map<String, Object?>? _context;
  bool _sent = false;

  @override
  void initState() {
    super.initState();
    reportContext(widget.db, screen: screenName(widget.from)).then((context) {
      if (mounted) setState(() => _context = context);
    });
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    await sendReport(
      widget.db,
      kind: _kind,
      body: _text.text,
      context: _context!,
    );
    if (mounted) setState(() => _sent = true);
  }

  @override
  Widget build(BuildContext context) {
    final n = Nocturne.of(context);
    return Scaffold(
      backgroundColor: n.bg,
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          n.space('6'),
          n.space('2'),
          n.space('6'),
          n.space('8'),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Report something',
              style: Theme.of(context).textTheme.displaySmall,
            ),
            SizedBox(height: n.space('2')),
            // The one-way decision, said once and in the reader's words. An
            // app that took a report and stayed silent would be promising a
            // correspondence nobody has committed to answering.
            _caption(
              n,
              'This goes one way. It reaches whoever keeps Wird running, and '
              'nothing comes back — there is no inbox here to check.',
            ),
            if (_sent) ..._queued(n) else ..._form(n),
          ],
        ),
      ),
    );
  }

  List<Widget> _form(Nocturne n) => [
    _section(n, 'WHAT KIND'),
    NocturneSegmented(
      options: const ['Bug', 'Request', 'Improvement'],
      selected: _kind.index,
      onChanged: (i) => setState(() => _kind = ReportKind.values[i]),
    ),
    _section(n, 'IN YOUR OWN WORDS'),
    NocturneInput(
      controller: _text,
      multiline: true,
      maxLength: reportMaxChars,
      hint: 'What happened, or what is missing.',
      onChanged: (_) => setState(() {}),
    ),
    // The limit is said when it is near, and not before. A reader with three
    // lines to write has no use for a count, and the one who is about to
    // reach it finds out here rather than by having the report parked.
    if (_text.text.length > reportMaxChars - _nearTheEnd) ...[
      SizedBox(height: n.space('1')),
      _caption(
        n,
        '${reportMaxChars - _text.text.length} characters left of '
        '$reportMaxChars. The server takes no more than that.',
      ),
    ],
    _section(n, 'SENT WITH IT'),
    _gathered(n),
    SizedBox(height: n.space('3')),
    _caption(
      n,
      'Gathered so you do not have to type it. Nothing else travels: not what '
      'you were reading, not what you have kept, not your progress.',
    ),
    SizedBox(height: n.space('6')),
    NocturneButton(
      key: const Key('send report'),
      variant: NocturneButtonVariant.primary,
      block: true,
      onPressed: _context == null || _text.text.trim().isEmpty ? null : _send,
      child: const Text('Send it'),
    ),
  ];

  List<Widget> _queued(Nocturne n) => [
    _section(n, 'QUEUED'),
    Text(
      'It is written down on this phone and goes out with the next sync, even '
      'if you are offline now.',
      style: TextStyle(fontSize: 12, height: 1.45, color: n.textAt(0.75)),
    ),
    SizedBox(height: n.space('6')),
    NocturneButton(
      onPressed: () => setState(() {
        _text.clear();
        _sent = false;
      }),
      child: const Text('Write another'),
    ),
  ];

  /// The context, printed as it will be sent. The values are read out of the
  /// same map the op body is built from, so a reader cannot be shown one
  /// build and have another transmitted.
  Widget _gathered(Nocturne n) {
    final gathered = _context;
    if (gathered == null) return _caption(n, 'Reading this build…');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final field in gathered.entries)
          Padding(
            padding: EdgeInsets.symmetric(vertical: n.space('1')),
            child: Row(
              spacing: n.space('3'),
              children: [
                Expanded(
                  child: Text(
                    field.key.replaceAll('_', ' '),
                    style: TextStyle(fontSize: 11, color: n.textAt(0.5)),
                  ),
                ),
                Text(
                  '${field.value}',
                  style: TextStyle(fontSize: 11, color: n.textAt(0.85)),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _section(Nocturne n, String label) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SizedBox(height: n.space('6')),
      Text(
        label,
        style: TextStyle(
          fontSize: 10,
          height: 1.2,
          letterSpacing: 0.11 * 10,
          color: n.accent,
        ),
      ),
      const NocturneRule(fade: 30),
    ],
  );

  Widget _caption(Nocturne n, String text) => Text(
    text,
    style: TextStyle(fontSize: 10.5, height: 1.4, color: n.textAt(0.5)),
  );
}
