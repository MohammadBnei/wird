import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';

import '../../data/auth.dart';
import '../../theme/nocturne.dart';
import '../../widgets/nocturne_button.dart';
import '../../widgets/nocturne_input.dart';

/// Signing in, which the reader may never do.
///
/// It lives in settings because that is where a reader goes to change
/// something about the app rather than about the Qur'an. Nothing else in Wird
/// asks about an account: the reading loop is local, and a signed-out reader
/// is never stopped, queued behind a spinner or shown a login wall.
///
/// ponytail: the address is copied and the answer is pasted back, exactly as
/// `SourceLink` on the about screen copies a licence URL. Opening a browser
/// needs `url_launcher` and catching the redirect needs a scheme in the
/// Android and iOS manifests, neither of which this screen owns. Swap the two
/// halves for `launchUrl` and a deep-link listener when that lands — the token
/// path underneath does not change, only who fetches the code.
class AccountPanel extends StatefulWidget {
  const AccountPanel({super.key, required this.db});

  final Database db;

  @override
  State<AccountPanel> createState() => _AccountPanelState();
}

class _AccountPanelState extends State<AccountPanel> {
  late final Account _account = Account(widget.db);
  final _pasted = TextEditingController();

  Tokens? _reader;
  SignIn? _started;
  String? _trouble;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _pasted.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final reader = await _account.current();
    if (mounted) setState(() => _reader = reader);
  }

  /// Anything the issuer or the network can do to a sign-in is shown here, in
  /// this panel, and never thrown at a reader who is somewhere else in the app.
  Future<void> _attempt(Future<void> Function() step) async {
    setState(() {
      _working = true;
      _trouble = null;
    });
    try {
      await step();
    } on Object catch (e) {
      if (mounted) setState(() => _trouble = _say(e));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _begin() => _attempt(() async {
    final started = await _account.begin();
    await Clipboard.setData(ClipboardData(text: started.url.toString()));
    if (mounted) setState(() => _started = started);
  });

  Future<void> _finish() => _attempt(() async {
    final started = _started;
    if (started == null) return;
    await _account.complete(started, Uri.parse(_pasted.text.trim()));
    _pasted.clear();
    if (mounted) setState(() => _started = null);
    await _load();
  });

  Future<void> _signOut() async {
    await _account.signOut();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final n = Nocturne.of(context);
    final reader = _reader;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (reader != null) ..._signedIn(n, reader) else ..._signedOut(n),
        if (_trouble != null) ...[
          SizedBox(height: n.space('2')),
          Text(
            _trouble!,
            style: TextStyle(fontSize: 10.5, height: 1.4, color: n.text),
          ),
        ],
      ],
    );
  }

  List<Widget> _signedIn(Nocturne n, Tokens reader) => [
    Text(
      'Signed in as ${reader.subject}',
      style: TextStyle(fontSize: 12, color: n.text),
    ),
    SizedBox(height: n.space('2')),
    NocturneButton(onPressed: _signOut, child: const Text('Sign out')),
    SizedBox(height: n.space('1')),
    _caption(
      n,
      'Signing out stops the sync. Everything you have read, kept and '
      'marked stays on this phone.',
    ),
  ];

  List<Widget> _signedOut(Nocturne n) {
    final started = _started;
    return [
      _caption(
        n,
        'Wird works signed out. Signing in carries what you mark and keep to '
        'your other devices.',
      ),
      SizedBox(height: n.space('2')),
      if (started == null)
        NocturneButton(
          onPressed: _working ? null : _begin,
          child: const Text('Sign in'),
        )
      else ...[
        _caption(
          n,
          'The sign-in address is on your clipboard. Open it in a browser, '
          'then paste the address it sends you back to.',
        ),
        SizedBox(height: n.space('1')),
        SelectableText(
          started.url.toString(),
          maxLines: 2,
          style: TextStyle(fontSize: 10.5, color: n.accent),
        ),
        SizedBox(height: n.space('2')),
        NocturneInput(
          controller: _pasted,
          hint: 'The address it sent you back to',
          onChanged: (_) => setState(() {}),
        ),
        SizedBox(height: n.space('2')),
        NocturneButton(
          onPressed: _working || _pasted.text.trim().isEmpty ? null : _finish,
          child: const Text('Finish signing in'),
        ),
      ],
    ];
  }

  Widget _caption(Nocturne n, String text) => Text(
    text,
    style: TextStyle(fontSize: 10.5, height: 1.4, color: n.textAt(0.5)),
  );
}

/// What went wrong, in the reader's language. A thrown [AuthFailed] already
/// says it; anything else here is the network, and the honest thing to say is
/// that the identity server was not reached rather than to print a socket
/// error at someone who wanted to sync their reading.
String _say(Object trouble) => trouble is AuthFailed
    ? trouble.message
    : 'The sign-in server could not be reached. Nothing changed.';
