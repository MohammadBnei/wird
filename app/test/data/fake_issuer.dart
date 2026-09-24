import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// An identity server on a real socket: discovery, an authorization endpoint
/// that sends a code back the way a browser would, and a token endpoint.
///
/// It signs nothing, because nothing on the device ever checks a signature —
/// the Go server does that against the issuer's JWKS, and it is proven there
/// against a real issuer. What a test needs from this one is the shape of the
/// answers and a record of what the device sent to get them: the PKCE
/// challenge, the verifier that came back with the code, and which grant was
/// used.
class FakeIssuer {
  FakeIssuer._(this._server) : port = _server.port {
    unawaited(_serve());
  }

  static Future<FakeIssuer> start() async =>
      FakeIssuer._(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));

  final HttpServer _server;
  final int port;

  String get issuer => 'http://127.0.0.1:$port/wird';

  /// Who the reader is, in the `sub` of every token minted from here.
  String subject = 'reader@bnei.dev';

  /// What the reader calls themselves, in the `email` claim. Theirs to change
  /// at the issuer without becoming anybody else, which is why it is a second
  /// field rather than the subject again.
  String? email;

  /// How long the ID token it mints is good for. Negative mints one that has
  /// already expired, which is the state a phone that has been asleep for a
  /// day wakes up in.
  Duration life = const Duration(hours: 1);

  /// The refresh token is refused, the way an issuer refuses one that has been
  /// revoked or already rotated. That is the one answer the device is allowed
  /// to read as "this reader really is signed out".
  bool refusesRefresh = false;

  /// What the device sent, in the order it sent it.
  final challenges = <String>[];
  final verifiers = <String>[];
  final grants = <String>[];

  /// The ID token and the access token of the last mint, so a test can say
  /// which of the two the device went on to put in its Authorization header.
  String idToken = '';
  String accessToken = '';

  /// One per token minted, so two tokens for the same reader in the same
  /// second are still two different strings — which is what lets a test say
  /// whether a retry carried the refreshed one.
  var _minted = 0;

  Future<void> stop() => _server.close(force: true);

  Future<void> _serve() async {
    await for (final request in _server) {
      switch (request.uri.path) {
        case '/wird/.well-known/openid-configuration':
          _json(request, {
            'issuer': issuer,
            // Away from the issuer path on purpose: Authentik's endpoints are
            // not under its issuer either, so a device that builds these by
            // joining strings fails here as it would there.
            'authorization_endpoint': 'http://127.0.0.1:$port/oauth/authorize',
            'token_endpoint': 'http://127.0.0.1:$port/oauth/token',
          });
        case '/oauth/authorize':
          final asked = request.uri.queryParameters;
          challenges.add(asked['code_challenge'] ?? '');
          request.response
            ..statusCode = HttpStatus.found
            ..headers.set(
              HttpHeaders.locationHeader,
              '${asked['redirect_uri']}?code=a-code&state=${asked['state']}',
            );
          unawaited(request.response.close());
        case '/oauth/token':
          final form = Uri.splitQueryString(
            await utf8.decoder.bind(request).join(),
          );
          grants.add(form['grant_type'] ?? '');
          if (form['code_verifier'] != null) {
            verifiers.add(form['code_verifier']!);
          }
          if (form['grant_type'] == 'refresh_token' && refusesRefresh) {
            request.response.statusCode = HttpStatus.badRequest;
            _json(request, {'error': 'invalid_grant'});
            continue;
          }
          final exp = DateTime.now().add(life).millisecondsSinceEpoch ~/ 1000;
          final jti = '${++_minted}';
          idToken = _jwt({
            'sub': subject,
            'email': email ?? subject,
            'aud': form['client_id'],
            'exp': exp,
            'jti': jti,
          });
          // `aud` is the trap this whole decision turns on: the access token
          // carries an audience that is not the client, so a server verifying
          // an ID token refuses it.
          accessToken = _jwt({
            'sub': subject,
            'aud': 'default',
            'exp': exp,
            'jti': jti,
          });
          _json(request, {
            'token_type': 'Bearer',
            'id_token': idToken,
            'access_token': accessToken,
            'refresh_token': 'a-refresh-token',
            'expires_in': life.inSeconds,
          });
        default:
          request.response.statusCode = HttpStatus.notFound;
          unawaited(request.response.close());
      }
    }
  }

  void _json(HttpRequest request, Map<String, dynamic> body) {
    request.response
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body));
    unawaited(request.response.close());
  }
}

String _jwt(Map<String, dynamic> claims) => [
  _segment({'alg': 'none'}),
  _segment(claims),
  'not-a-signature',
].join('.');

String _segment(Map<String, dynamic> part) =>
    base64Url.encode(utf8.encode(jsonEncode(part))).replaceAll('=', '');
