import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

/// A real socket answering the two endpoints, scripted per test.
///
/// The server's own behaviour — idempotency, per-op verdicts, tombstones — is
/// proven in Go against a real Postgres. What is under test here is what the
/// device does with the answers, so the answers are dictated rather than
/// computed: a fake that re-implements the contract only tests itself.
class FakeWird {
  FakeWird._(this._server) : port = _server.port {
    unawaited(_serve());
  }

  static Future<FakeWird> start() async =>
      FakeWird._(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));

  final HttpServer _server;

  /// Held past the close, so a test can point the device at a port nothing is
  /// listening on — which is what airplane mode looks like from here.
  final int port;

  /// Every batch that arrived, in order, as the ops the device sent.
  final List<List<Map<String, dynamic>>> batches = [];

  /// Every cursor the device asked from.
  final List<String> cursorsAsked = [];

  /// The verdict for one op id; applied unless a test says otherwise.
  String Function(String opId) verdict = (_) => 'applied';

  /// A page served in place of every answer, with a 200 on it. A captive
  /// portal on hotel wifi does exactly this: the socket connects, the status
  /// is fine and the body is somebody else's sign-in form.
  String? insteadAPortal;

  /// Change pages, handed over in turn. When they run out the server says
  /// nothing has changed.
  List<Map<String, dynamic>> pages = [];

  /// Every Authorization header that arrived, in order, so a test can say
  /// which token the device chose to send.
  final bearers = <String?>[];

  /// What this server will take. The real one verifies the token against the
  /// issuer's JWKS and answers 401 with nothing else in it; a test that says
  /// no here is an expired token, a revoked session, or a device with nobody
  /// signed in.
  bool Function(String? bearer) accepts = (_) => true;

  Dio get dio => Dio(BaseOptions(baseUrl: 'http://127.0.0.1:$port'));

  List<Map<String, dynamic>> get opsReceived => [
    for (final batch in batches) ...batch,
  ];

  Future<void> stop() => _server.close(force: true);

  Future<void> _serve() async {
    await for (final request in _server) {
      final portal = insteadAPortal;
      if (portal != null) {
        request.response
          ..headers.contentType = ContentType.html
          ..write(portal);
        unawaited(request.response.close());
        continue;
      }
      final bearer = request.headers.value(HttpHeaders.authorizationHeader);
      bearers.add(bearer);
      if (!accepts(bearer)) {
        request.response
          ..statusCode = HttpStatus.unauthorized
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'error': 'token rejected'}));
        unawaited(request.response.close());
        continue;
      }
      if (request.uri.path == '/v1/sync') {
        final body =
            jsonDecode(await utf8.decoder.bind(request).join())
                as Map<String, dynamic>;
        final ops = [
          for (final op in body['ops'] as List) (op as Map).cast<String, dynamic>(),
        ];
        batches.add(ops);
        _answer(request, {
          'results': [
            for (final op in ops)
              {
                'client_op_id': op['client_op_id'],
                'status': verdict(op['client_op_id'] as String),
                'reason': 'refused in this test',
              },
          ],
        });
      } else {
        cursorsAsked.add(request.uri.queryParameters['since'] ?? '');
        _answer(
          request,
          pages.isEmpty
              ? {'changes': [], 'cursor': '', 'more': false}
              : pages.removeAt(0),
        );
      }
    }
  }

  void _answer(HttpRequest request, Map<String, dynamic> body) {
    request.response
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body));
    unawaited(request.response.close());
  }
}
