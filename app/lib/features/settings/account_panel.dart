import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/auth.dart';
import '../../data/flush.dart';
import '../../l10n/app_localizations.dart';
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
    this.wird,
  });

  final Database db;

  /// The three things the phone supplies and a test stands in for: the issuer
  /// this device signs in at, the browser the address is opened in, and the
  /// links the OS delivers when the issuer sends the reader back.
  final Account? account;
  final Future<bool> Function(Uri url)? open;
  final Stream<Uri>? redirects;

  /// The Wird server an account deletion is sent to.
  final Dio? wird;

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
  bool _confirmingDelete = false;

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
      if (mounted) {
        setState(() => _trouble = _say(AppLocalizations.of(context)!, e));
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _begin() => _attempt(() async {
    // Read before the first await: this message is thrown and then printed in
    // the panel, so it has to be the reader's, and a BuildContext is not to be
    // touched across an await.
    final noBrowser = AppLocalizations.of(context)!.settingsNoBrowser;
    final started = await _account.begin();
    // Listening before the browser opens: the link is the only thing that can
    // finish this, and a phone that is not listening when it arrives loses it.
    _listening ??= _redirects.listen(_returned);
    if (mounted) setState(() => _started = started);
    if (!await (widget.open ?? _inTheBrowser)(started.url)) {
      _giveUp();
      throw AuthFailed(noBrowser);
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

  /// The store rule: the reader can delete their account from here. It takes
  /// two taps, and a failure leaves both the account and the phone as they
  /// were, so the message says nothing was removed.
  Future<void> _delete() async {
    final failed = AppLocalizations.of(context)!.settingsDeleteAccountFailed;
    await _attempt(() async {
      try {
        await _account.deleteAccount(
          widget.wird ?? Dio(BaseOptions(baseUrl: syncOrigin)),
        );
      } on Object {
        throw AuthFailed(failed);
      }
      if (mounted) setState(() => _confirmingDelete = false);
      await _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final n = Nocturne.of(context);
    final l = AppLocalizations.of(context)!;
    final reader = _reader;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (reader != null) ..._signedIn(n, l, reader) else ..._signedOut(n, l),
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

  List<Widget> _signedIn(Nocturne n, AppLocalizations l, Tokens reader) => [
    Text(
      l.settingsSignedInAs(reader.subject),
      style: TextStyle(fontSize: 12, color: n.text),
    ),
    SizedBox(height: n.space('2')),
    NocturneButton(onPressed: _signOut, child: Text(l.settingsSignOut)),
    SizedBox(height: n.space('1')),
    _caption(n, l.settingsSignOutCaption),
    SizedBox(height: n.space('3')),
    if (!_confirmingDelete)
      NocturneButton(
        onPressed: () => setState(() => _confirmingDelete = true),
        child: Text(l.settingsDeleteAccount),
      )
    else ...[
      _caption(n, l.settingsDeleteAccountCaption),
      SizedBox(height: n.space('2')),
      NocturneButton(
        onPressed: _working ? null : _delete,
        child: Text(l.settingsDeleteAccountConfirm),
      ),
      SizedBox(height: n.space('1')),
      NocturneButton(
        onPressed: () => setState(() => _confirmingDelete = false),
        child: Text(l.settingsDeleteAccountCancel),
      ),
    ],
  ];

  List<Widget> _signedOut(Nocturne n, AppLocalizations l) => [
    _caption(n, l.settingsSignedOutCaption),
    SizedBox(height: n.space('2')),
    if (_started == null)
      NocturneButton(
        onPressed: _working ? null : _begin,
        child: Text(l.settingsSignIn),
      )
    else ...[
      _caption(n, l.settingsFinishInBrowser),
      SizedBox(height: n.space('2')),
      NocturneButton(onPressed: _giveUp, child: Text(l.settingsCancelSignIn)),
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
String _say(AppLocalizations l, Object trouble) => trouble is AuthFailed
    ? trouble.message
    : l.settingsSignInUnreachable;
