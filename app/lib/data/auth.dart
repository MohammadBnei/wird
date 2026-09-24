import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:sqflite/sqflite.dart';

/// Who the reader is to the server, when they have chosen to be anyone.
///
/// Signing in is optional and being signed out blocks nothing: the corpus, the
/// set, the prayer and everything a reader marks are local, and they work with
/// the radio off. What an account adds is that the queue in the outbox has
/// somewhere to land. So nothing on this path is ever awaited by a screen the
/// reader is reading on, and there is no login wall anywhere in the app.
///
/// Signing out drops the tokens and nothing else. A reader who signs out has
/// not asked to forget what they have understood. A *different* reader signing
/// in is the one act that clears this device: see [_handOver].

/// The identity server, and who we are to it. All three are compile-time
/// defines so a debug run can be pointed at the local stub in
/// `docker-compose.yml` without editing this file.
const authIssuer = String.fromEnvironment(
  'WIRD_ISSUER',
  defaultValue: 'https://authentik.bnei.dev/application/o/wird/',
);

const authClientId = String.fromEnvironment(
  'WIRD_CLIENT_ID',
  defaultValue: 'Um9Je1MQghdZ4SqAjB7cWtGNubP64phIuGqzdzro',
);

/// Where the issuer sends the reader back to, and the only place the string is
/// written: [Account.begin] puts it in the authorization URL, the exchange
/// sends it again, and the BROWSABLE intent-filter in
/// `android/app/src/main/AndroidManifest.xml` claims it as an App Link so the
/// browser has somewhere to hand the code to.
///
/// It has to be, character for character, a redirect registered on the
/// Authentik client. When it is not, the issuer answers with a bad-redirect
/// error before the reader is ever shown a password field, and no amount of
/// correct code on this side changes that — which is exactly what a reader
/// walking the app hit.
///
/// The client registers **one**, read off the blueprint rather than assumed:
/// `https://wird.bnei.dev/auth/callback`, `matching_mode: strict`, which is a
/// fullmatch. An earlier version of this comment said there were two and named
/// `dev.bnei.wird://` as the other. There is no such registration and its
/// absence is deliberate: infra-bootstrap ADR-0050 records that a custom
/// scheme is first-come and unclaimable on both platforms, that PKCE does not
/// close that because a copycat runs its own flow with its own challenge, and
/// that against this client's implicit-consent flow a registered scheme would
/// hand a copycat an access token and a ninety-day refresh token without the
/// reader doing anything.
const authRedirect = String.fromEnvironment(
  'WIRD_REDIRECT',
  defaultValue: 'https://wird.bnei.dev/auth/callback',
);

/// `offline_access` is what makes a refresh token come back, and a refresh
/// token is what keeps a reader signed in across the week their phone spends
/// mostly offline. `email` and `profile` are only so settings can say which
/// account is signed in.
const _scopes = 'openid offline_access email profile';

/// What the device sends as its bearer.
///
/// It is the **ID token**, decided by experiment rather than by reading the
/// library's response object: `server/internal/auth/auth.go` builds
/// `provider.Verifier(&oidc.Config{ClientID: audience})` and calls `Verify`,
/// which is go-oidc's ID token path and checks that `aud` carries the client
/// id. Against the local stub on 2026-09-24, with the API on its own port:
/// the ID token was accepted with a 200, and the access token, whose `aud` is
/// `default`, came back 401 with `expected audience "wird" got ["default"]`.
/// docs/authentik-wiring.md carries the same check for the real issuer.
class Tokens {
  const Tokens({
    required this.subject,
    required this.idToken,
    required this.refreshToken,
    required this.expiresAt,
  });

  /// The reader, as the server will know them. Read out of the token without
  /// verifying it, which is safe here and only here: it is shown on the
  /// settings screen and never trusted for anything. The server verifies the
  /// signature before it believes a word of it.
  final String subject;

  final String idToken;

  /// Absent when the issuer gave none, which is what a provider without
  /// `offline_access` does. Then the reader is signed in until the token
  /// expires and signed out after it.
  final String? refreshToken;

  /// The `exp` claim of [idToken] — the instant the server stops taking it.
  final DateTime expiresAt;
}

/// The tokens table, created on the first call rather than in a migration,
/// the way the kept table and the outbox columns are.
Future<void> ensureAuthTable(Database db) => db.execute('''
  CREATE TABLE IF NOT EXISTS auth_tokens (
    id            INTEGER PRIMARY KEY CHECK (id = 1),
    subject       TEXT NOT NULL,
    id_token      TEXT NOT NULL,
    refresh_token TEXT,
    expires_at    TEXT NOT NULL
  )''');

/// Whose reading this device holds, named by the `sub` of the account it was
/// last signed into.
///
/// It outlives the tokens on purpose. Signing out drops the tokens and keeps
/// the reading, so the row beside them cannot answer who the reading belongs
/// to; this one can, and it is the only way to tell a reader coming back from
/// a second reader arriving.
Future<void> _ensureReaderTable(Database db) => db.execute('''
  CREATE TABLE IF NOT EXISTS local_reader (
    id  INTEGER PRIMARY KEY CHECK (id = 1),
    sub TEXT NOT NULL
  )''');

/// A sign-in that has been started and not yet finished: the address the
/// reader signs in at, and the two secrets that must still be there when they
/// come back.
///
/// ponytail: held in memory, so a sign-in survives the reader switching to the
/// browser and back but not the OS killing the app while they are in it. Put
/// [verifier] and [state] in the table beside the tokens when the redirect
/// arrives as a deep link into a cold start.
class SignIn {
  const SignIn(this.url, this.verifier, this.state);

  final Uri url;
  final String verifier;
  final String state;
}

/// The account on this device, backed by one row.
///
/// Every read goes to that row rather than to a field, so the settings screen
/// and the flusher's interceptor can each hold their own [Account] over the
/// same database and neither can be looking at a token the other has
/// replaced.
class Account {
  Account(
    this.db, {
    Dio? http,
    this.issuer = authIssuer,
    this.clientId = authClientId,
    this.redirect = authRedirect,
  }) : http = http ?? Dio();

  final Database db;
  final Dio http;
  final String issuer;
  final String clientId;
  final String redirect;

  Map<String, dynamic>? _endpoints;

  /// The reader's tokens, or null when nobody is signed in.
  Future<Tokens?> current() async {
    await ensureAuthTable(db);
    final rows = await db.query('auth_tokens', limit: 1);
    if (rows.isEmpty) return null;
    final row = rows.first;
    return Tokens(
      subject: row['subject']! as String,
      idToken: row['id_token']! as String,
      refreshToken: row['refresh_token'] as String?,
      expiresAt: DateTime.parse(row['expires_at']! as String),
    );
  }

  /// A token the server will still take, refreshed if this one is spent.
  ///
  /// Null means "send the request unsigned": either nobody is signed in, or
  /// the refresh could not be made. Unsigned is answered with a 401, which the
  /// flush reads as never having reached the server — the queue is untouched
  /// and nothing is parked. That is the right ending for both.
  ///
  /// [force] is for the 401 that arrives while the stored token still looks
  /// fresh: a session ended at the issuer, or a clock further out than the
  /// minute of slack below.
  Future<String?> token({bool force = false}) async {
    final held = await current();
    if (held == null) return null;
    if (!force &&
        held.expiresAt.isAfter(
          DateTime.now().add(const Duration(minutes: 1)),
        )) {
      return held.idToken;
    }
    return _refresh(held);
  }

  /// Starts a sign-in. Nothing is stored until [complete].
  Future<SignIn> begin() async {
    final verifier = _randomToken();
    final state = _randomToken();
    final url = Uri.parse(await _endpoint('authorization_endpoint')).replace(
      queryParameters: {
        'response_type': 'code',
        'client_id': clientId,
        'redirect_uri': redirect,
        'scope': _scopes,
        'state': state,
        'code_challenge': _challenge(verifier),
        'code_challenge_method': 'S256',
      },
    );
    return SignIn(url, verifier, state);
  }

  /// Finishes it, from the address the issuer sent the reader back to.
  ///
  /// The state has to match the one [begin] minted: without that check a link
  /// from anywhere could sign this device in as somebody else's account.
  Future<Tokens> complete(SignIn begun, Uri redirected) async {
    final answer = redirected.queryParameters;
    final error = answer['error'];
    if (error != null) {
      throw AuthFailed(answer['error_description'] ?? error);
    }
    final code = answer['code'];
    if (code == null || answer['state'] != begun.state) {
      throw const AuthFailed('that address did not come from this sign-in');
    }
    return _exchange({
      'grant_type': 'authorization_code',
      'code': code,
      'redirect_uri': redirect,
      'client_id': clientId,
      'code_verifier': begun.verifier,
    });
  }

  /// Forgets who the reader is, and only that.
  ///
  /// It deletes one row. Everything the reader has understood, kept, prayed
  /// and queued stays exactly where it is, including the ops in the outbox —
  /// they wait for this reader to sign back in. Handing the device to somebody
  /// else and watching them sign in is the other story, and [_handOver] tells
  /// it.
  ///
  /// ponytail: local only. The refresh token is dropped rather than revoked at
  /// the issuer, so it stays live there until it expires. Call the discovery
  /// document's `revocation_endpoint` here when a shared device asks for it —
  /// but signing out must keep working with the radio off, so a failed revoke
  /// can never stop this delete.
  Future<void> signOut() async {
    await ensureAuthTable(db);
    await db.delete('auth_tokens');
  }

  Future<String?> _refresh(Tokens held) async {
    final refresh = held.refreshToken;
    if (refresh == null) return null;
    try {
      final fresh = await _exchange({
        'grant_type': 'refresh_token',
        'refresh_token': refresh,
        'client_id': clientId,
      }, keep: refresh);
      return fresh.idToken;
    } on DioException catch (e) {
      // A refusal of the refresh token itself is the one answer that means
      // the reader really is signed out: it will not start working again.
      // Anything else — no signal, a portal, a 500 — leaves the account alone,
      // because dropping a session over a bad minute makes the reader sign in
      // again for nothing.
      if (e.response?.statusCode == 400) await signOut();
      return null;
    }
  }

  Future<Tokens> _exchange(Map<String, String> form, {String? keep}) async {
    final answer = await http.post<dynamic>(
      await _endpoint('token_endpoint'),
      data: form,
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );
    final body = (answer.data as Map).cast<String, dynamic>();
    final idToken = body['id_token'] as String?;
    if (idToken == null) {
      throw const AuthFailed('the issuer returned no ID token');
    }
    final claims = claimsOf(idToken);
    final sub = claims['sub'];
    if (sub is! String || sub.isEmpty) {
      throw const AuthFailed('the issuer returned a token naming no reader');
    }
    final tokens = Tokens(
      subject:
          (claims['email'] ??
                  claims['preferred_username'] ??
                  claims['sub'] ??
                  '')
              as String,
      idToken: idToken,
      // Authentik rotates the refresh token on use and Authentik's stub does
      // not. Keeping the old one when the answer carries none is what makes
      // both work.
      refreshToken: body['refresh_token'] as String? ?? keep,
      expiresAt: _expiry(claims),
    );
    await ensureAuthTable(db);
    await _ensureReaderTable(db);
    // One transaction, so there is no instant in which the device has been
    // cleared for a reader whose token was never written, or signed in with
    // somebody else's reading still under it.
    await db.transaction((txn) async {
      await _handOver(txn, sub);
      await txn.insert('auth_tokens', {
        'id': 1,
        'subject': tokens.subject,
        'id_token': tokens.idToken,
        'refresh_token': tokens.refreshToken,
        'expires_at': tokens.expiresAt.toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
    return tokens;
  }

  /// The issuer's own discovery document, which is how the authorization and
  /// token endpoints are found rather than guessed. Authentik does not put
  /// either of them under the issuer path — `/application/o/authorize/` against
  /// an issuer of `/application/o/wird/` — so a URL built by joining strings
  /// here would be wrong for the one provider this app talks to.
  Future<String> _endpoint(String name) async {
    final doc = _endpoints ??= await _discover();
    final endpoint = doc[name];
    if (endpoint is! String) {
      throw AuthFailed('the issuer advertises no $name');
    }
    return endpoint;
  }

  Future<Map<String, dynamic>> _discover() async {
    final base = issuer.endsWith('/') ? issuer : '$issuer/';
    final answer = await http.get<dynamic>(
      '$base.well-known/openid-configuration',
    );
    return (answer.data as Map).cast<String, dynamic>();
  }
}

/// What one reader's own reading is kept in. The corpus is the same for
/// everyone and is not here; neither are `display_prefs` and `mic_consent`,
/// which are how this glass is set up rather than anything about who is
/// holding it.
///
/// ponytail: a list, because no local row carries a user id — the column
/// db.dart's opening comment promised never arrived, and adding one now would
/// mean a key on every table for a device that shows one reader at a time.
/// Give the rows an owner if this device ever has to hold two readings at once.
const _theReadersOwn = [
  'ayah_understood',
  'kept_items',
  'user_prefs',
  'sets',
  'set_prayers',
  'set_span',
  'outbox',
  'sync_state',
];

/// Hands the device to whoever has just signed in.
///
/// A device remembers one reader. When that is the reader signing in, nothing
/// happens: signing out is not asking to forget, so signing back in is not
/// somebody arriving. Neither is a first sign-in on a device that has never
/// met an issuer — a month read before deciding an account was worth it is
/// that reader's own, and they keep it.
///
/// A different `sub` is a second person on a shared tablet, and they are not
/// shown the first one's reading. That is the whole of it: every table in
/// [_theReadersOwn] is keyed by aya or by op id and none of them says whose,
/// so the only way a note of one reader's stays out of the other's screen is
/// that it is no longer here.
///
/// The comparison is on `sub` rather than on [Tokens.subject]. What settings
/// prints is an email or a username, the reader's own to change at the
/// issuer, and a device emptied over a renamed mailbox is the same loss by
/// another road.
///
/// The outbox goes with the rest, and that is a deletion of writing nobody
/// asked to delete. It is still the better ending: an op left here would
/// flush under the new reader's token and write the first reader's notes into
/// an account that is not theirs, and an op parked instead would print those
/// notes in the parked-writes panel of the person now holding the tablet.
/// Both endings hand the writing to the wrong reader; this one only loses it,
/// and only the part that never reached the server.
Future<void> _handOver(Transaction txn, String sub) async {
  final held = await txn.query('local_reader', columns: ['sub'], limit: 1);
  if (held.isNotEmpty && held.first['sub'] != sub) {
    // `kept_items` and `sync_state` are created by the first write that needs
    // them, so on a device that has never kept a note or synced they are not
    // there to empty.
    final present = {
      for (final row in await txn.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      ))
        row['name'],
    };
    for (final table in _theReadersOwn) {
      if (present.contains(table)) await txn.delete(table);
    }
  }
  await txn.insert('local_reader', {
    'id': 1,
    'sub': sub,
  }, conflictAlgorithm: ConflictAlgorithm.replace);
}

/// A sign-in that cannot go on, in words the settings screen can print.
class AuthFailed implements Exception {
  const AuthFailed(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The claims of a JWT, unverified. Only for what this device shows itself.
Map<String, dynamic> claimsOf(String jwt) {
  final parts = jwt.split('.');
  if (parts.length != 3) throw const AuthFailed('that is not a token');
  final payload = utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
  return (jsonDecode(payload) as Map).cast<String, dynamic>();
}

/// The `exp` claim. A token with no expiry is treated as already spent, so
/// that the first request refreshes rather than sending something the server
/// may have stopped taking.
DateTime _expiry(Map<String, dynamic> claims) {
  final exp = claims['exp'];
  return exp is num
      ? DateTime.fromMillisecondsSinceEpoch(exp.toInt() * 1000)
      : DateTime.fromMillisecondsSinceEpoch(0);
}

/// Attaches the reader's token to every request the sync client makes, and
/// nowhere else does a token exist. No screen and no repository knows there is
/// one.
class AuthHeader extends Interceptor {
  AuthHeader(this.account);

  final Account account;

  /// The retry rides a plain client: this interceptor is already inside its
  /// own error handler, and a retry through the same one could refresh and
  /// retry again on the answer to the retry.
  final _plain = Dio();

  static const _retried = 'the token was already refreshed once';

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = await account.token();
    if (token != null) options.headers['Authorization'] = 'Bearer $token';
    handler.next(options);
  }

  /// A 401 is a token that has gone stale mid-flush, never the server refusing
  /// the write. It is answered by refreshing once and sending the same request
  /// again; if that cannot be done the error is passed on as it arrived, which
  /// is a [DioException] and so reads as "the flush never reached the server".
  /// The outbox keeps every op, spends no attempt and parks nothing.
  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    if (err.response?.statusCode != 401 ||
        err.requestOptions.extra.containsKey(_retried)) {
      return handler.next(err);
    }
    final token = await account.token(force: true);
    if (token == null) return handler.next(err);
    final options = err.requestOptions
      ..extra[_retried] = true
      ..headers['Authorization'] = 'Bearer $token';
    try {
      handler.resolve(await _plain.fetch<dynamic>(options));
    } on DioException catch (again) {
      handler.next(again);
    }
  }
}

final _entropy = Random.secure();

/// 43 to 128 unreserved characters, per RFC 7636. 32 random bytes in base64url
/// is 43 of them.
String _randomToken() => base64UrlEncode([
  for (var i = 0; i < 32; i++) _entropy.nextInt(256),
]).replaceAll('=', '');

String _challenge(String verifier) =>
    base64UrlEncode(sha256.convert(ascii.encode(verifier)).bytes)
        .replaceAll('=', '');
