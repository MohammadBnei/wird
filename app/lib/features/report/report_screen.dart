import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import '../../l10n/app_localizations.dart';
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
/// The send queues and returns. There is no spinner, which is the same
/// contract as marking a set understood: the write is local and the flush is
/// somebody else's problem. A local write can still fail — a full disk — and
/// then the reader's words stay in the box with a line saying so.
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

  /// The five values that will be sent, read once. Null until the corpus
  /// answers, which is also how the send stays disabled until there is
  /// something honest to show. A value can be empty — a phone that has never
  /// fetched a sense pack sends an empty sense_version — and it is drawn empty,
  /// because what the reader is owed is the thing that leaves the phone.
  Map<String, Object?>? _context;
  bool _sent = false;
  bool _failed = false;

  /// The language the context was read for. The locale is read off the
  /// widget tree, which `initState` cannot reach, and is read again if the
  /// device changes language under the screen.
  String? _locale;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final locale = Localizations.localeOf(context).languageCode;
    if (locale == _locale) return;
    _locale = locale;
    reportContext(
      widget.db,
      screen: screenName(widget.from),
      locale: locale,
    ).then((context) {
      if (mounted && _locale == locale) setState(() => _context = context);
    });
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    try {
      await sendReport(
        widget.db,
        kind: _kind,
        body: _text.text,
        context: _context!,
      );
    } on Object {
      // The words are still in the box; the reader is told and can press
      // again.
      if (mounted) setState(() => _failed = true);
      return;
    }
    if (mounted) {
      setState(() {
        _sent = true;
        _failed = false;
      });
    }
  }

  /// The strings, read off the locale the device is in. A getter rather than a
  /// field because `State.context` is what carries the locale, and it changes
  /// under the screen when the device does.
  AppLocalizations get _l10n => AppLocalizations.of(context)!;

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
              _l10n.report_title,
              style: Theme.of(context).textTheme.displaySmall,
            ),
            SizedBox(height: n.space('2')),
            // The one-way decision, said once and in the reader's words. An
            // app that took a report and stayed silent would be promising a
            // correspondence nobody has committed to answering.
            _caption(n, _l10n.report_one_way),
            if (_sent) ..._queued(n) else ..._form(n),
          ],
        ),
      ),
    );
  }

  List<Widget> _form(Nocturne n) => [
    _section(n, _l10n.report_kind_heading),
    NocturneSegmented(
      // In [ReportKind] order: the index the chooser hands back is the enum's,
      // and the enum's names are what the server's constraint accepts.
      options: [
        _l10n.report_kind_bug,
        _l10n.report_kind_request,
        _l10n.report_kind_improvement,
      ],
      selected: _kind.index,
      onChanged: (i) => setState(() => _kind = ReportKind.values[i]),
    ),
    _section(n, _l10n.report_words_heading),
    NocturneInput(
      controller: _text,
      multiline: true,
      maxLength: reportMaxChars,
      hint: _l10n.report_words_hint,
      onChanged: (_) => setState(() {}),
    ),
    // The limit is said when it is near, and not before. A reader with three
    // lines to write has no use for a count, and the one who is about to
    // reach it finds out here rather than by having the report parked.
    if (_text.text.length > reportMaxChars - _nearTheEnd) ...[
      SizedBox(height: n.space('1')),
      _caption(
        n,
        _l10n.report_chars_left(
          reportMaxChars - _text.text.length,
          reportMaxChars,
        ),
      ),
    ],
    _section(n, _l10n.report_context_heading),
    _gathered(n),
    SizedBox(height: n.space('3')),
    _caption(n, _l10n.report_context_only),
    SizedBox(height: n.space('6')),
    NocturneButton(
      key: const Key('send report'),
      variant: NocturneButtonVariant.primary,
      block: true,
      onPressed: _context == null || _text.text.trim().isEmpty ? null : _send,
      child: Text(_l10n.report_send),
    ),
    if (_failed) ...[
      SizedBox(height: n.space('2')),
      _caption(n, _l10n.report_failed),
    ],
  ];

  List<Widget> _queued(Nocturne n) => [
    _section(n, _l10n.report_queued_heading),
    Text(
      _l10n.report_queued_body,
      style: TextStyle(fontSize: 12, height: 1.45, color: n.textAt(0.75)),
    ),
    SizedBox(height: n.space('6')),
    NocturneButton(
      onPressed: () => setState(() {
        _text.clear();
        _sent = false;
      }),
      child: Text(_l10n.report_write_another),
    ),
  ];

  /// The context, printed as it will be sent. The values are read out of the
  /// same map the op body is built from, so a reader cannot be shown one
  /// build and have another transmitted.
  ///
  /// Neither the names nor the values are localised, and that is the point:
  /// they are the op body's own field names and the protocol words the server
  /// accepts. A translated label here would be a label, not the thing being
  /// sent, and the guarantee above is that the reader sees the thing.
  Widget _gathered(Nocturne n) {
    final gathered = _context;
    if (gathered == null) return _caption(n, _l10n.report_context_loading);
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
