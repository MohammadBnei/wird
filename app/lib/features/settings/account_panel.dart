import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/auth.dart';
import '../../theme/nocturne.dart';
import '../../widgets/nocturne_button.dart';

/// Signing in, which the reader may never do.
///
/// It lives in settings because that is where a reader goes to change
/// something about the app rather than about the Qur'an. Nothing else in Wird
/// asks about an account: the reading loop is local, and a signed-out reader
/// is never stopped, queued behind a spinner or shown a login wall.
///
/// The address opens in the phone's own browser, and the issuer sends the
/// reader back to a link on [authRedirect]'s scheme, which the Android
/// manifest's second intent-filter hands to this running app. Both halves read
/// that one constant, so the string the issuer has registered is written here
/// once.
///
/// ponytail: the pending sign-in lives on this State, so it survives the
/// reader stepping out to the browser and back but not the OS killing the app
/// behind them, and it is dropped when they leave the panel. Store the
/// verifier and the state beside the tokens when a cold start has to be able
/// to finish one.
class AccountPanel extends StatefulWidget {
  const AccountPanel({
    super.key,
    required this.db,
    this.account,
    this.open,
    this.redirects,
  });

  final Database db;

  /// The three things the phone supplies and a test stands in for: the issuer
  /// this device signs in at, the browser the address is opened in, and the
  /// links the OS delivers when the issuer sends the reader back.
  final Account? account;
  final Future<bool> Function(Uri url)? open;
  final Stream<Uri>? redirects;

  @override
  State<AccountPanel> createState() => _AccountPanelState();
}

class _AccountPanelState extends State<AccountPanel> {
  late final Account _account = widget.account ?? Account(widget.db);

  /// Built on the first sign-in rather than in [initState]: every screen that
  /// shows this panel would otherwise reach for the plugin, including the ones
  /// no reader ever signs in from.
  late final Stream<Uri> _redirects =
      widget.redirects ?? AppLinks().uriLinkStream;

  late final String _ours = Uri.parse(_account.redirect).scheme;

  Tokens? _reader;
  SignIn? _started;
  StreamSubscription<Uri>? _listening;
  String? _trouble;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _listening?.cancel();
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
    // Listening before the browser opens: the link is the only thing that can
    // finish this, and a phone that is not listening when it arrives loses it.
    _listening ??= _redirects.listen(_returned);
    if (mounted) setState(() => _started = started);
    if (!await (widget.open ?? _inTheBrowser)(started.url)) {
      _giveUp();
      throw const AuthFailed('no browser here would open the sign-in address');
    }
  });

  /// A link the OS handed us. Only a sign-in this device started can be
  /// finished by one, and only a link on our own scheme is even looked at.
  void _returned(Uri back) {
    final started = _started;
    if (started == null || back.scheme != _ours) return;
    unawaited(
      _attempt(() async {
        // The verifier is spent whatever the answer is, and the panel offers a
        // fresh sign-in rather than waiting on a link that has already come.
        _giveUp();
        await _account.complete(started, back);
        await _load();
      }),
    );
  }

  /// Drops the pending sign-in: its verifier, its state, and the listening.
  /// The reader who opened the browser and never came back is left where they
  /// started, which is the one place the panel must always be able to return
  /// to.
  void _giveUp() {
    _listening?.cancel();
    _listening = null;
    if (mounted) setState(() => _started = null);
  }

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

  List<Widget> _signedOut(Nocturne n) => [
    _caption(
      n,
      'Wird works signed out. Signing in carries what you mark and keep to '
      'your other devices.',
    ),
    SizedBox(height: n.space('2')),
    if (_started == null)
      NocturneButton(
        onPressed: _working ? null : _begin,
        child: const Text('Sign in'),
      )
    else ...[
      _caption(
        n,
        'Finish signing in in your browser. This phone is waiting for it to '
        'send you back.',
      ),
      SizedBox(height: n.space('2')),
      NocturneButton(onPressed: _giveUp, child: const Text('Cancel')),
    ],
  ];

  Widget _caption(Nocturne n, String text) => Text(
    text,
    style: TextStyle(fontSize: 10.5, height: 1.4, color: n.textAt(0.5)),
  );
}

/// The phone's own browser, never a webview this app is holding: a webview
/// puts the issuer's password field in a window the app itself controls, and
/// Authentik is entitled to refuse one.
Future<bool> _inTheBrowser(Uri url) =>
    launchUrl(url, mode: LaunchMode.externalApplication);

/// What went wrong, in the reader's language. A thrown [AuthFailed] already
/// says it; anything else here is the network, and the honest thing to say is
/// that the identity server was not reached rather than to print a socket
/// error at someone who wanted to sync their reading.
String _say(Object trouble) => trouble is AuthFailed
    ? trouble.message
    : 'The sign-in server could not be reached. Nothing changed.';
