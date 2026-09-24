import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wird/data/audio.dart';
import 'package:wird/data/auth.dart';
import 'package:wird/data/db.dart';
import 'package:wird/features/dashboard/dashboard_screen.dart';
import 'package:wird/features/settings/account_panel.dart';
import 'package:wird/features/settings/settings_screen.dart';

import '../../corpus.dart';
import '../../data/fake_issuer.dart';
import '../../fonts.dart';
import '../../offline.dart';
import '../../wird.dart';

/// The identity server, answered on this side of the socket.
///
/// A widget test runs in a zone that holds real sockets still: anything a
/// screen fetches for itself never comes back. So the panel, which now does
/// its own fetching, is given an issuer that answers inside the test.
/// [FakeIssuer] is the one on a real socket, for the tests that do the
/// fetching themselves.
class IssuerInProcess implements HttpClientAdapter {
  static const issuer = 'https://issuer.test/application/o/wird/';

  /// Every form the device posted to the token endpoint, in order.
  final exchanges = <Map<String, String>>[];

  Dio get client => Dio()..httpClientAdapter = this;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.path.endsWith('/.well-known/openid-configuration')) {
      return _json({
        'issuer': issuer,
        // Away from the issuer path on purpose, as Authentik's are.
        'authorization_endpoint':
            'https://issuer.test/application/o/authorize/',
        'token_endpoint': 'https://issuer.test/application/o/token/',
      });
    }
    exchanges.add(
      Uri.splitQueryString(
        utf8.decode(
          await requestStream!.expand<int>((chunk) => chunk).toList(),
        ),
      ),
    );
    return _json({
      'token_type': 'Bearer',
      'id_token': jwt({
        'sub': 'reader@bnei.dev',
        'email': 'reader@bnei.dev',
        'aud': 'wird-test',
        'exp':
            DateTime.now()
                .add(const Duration(hours: 1))
                .millisecondsSinceEpoch ~/
            1000,
      }),
      'refresh_token': 'a-refresh-token',
    });
  }

  ResponseBody _json(Map<String, dynamic> body) => ResponseBody.fromString(
    jsonEncode(body),
    200,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

void main() {
  late Database db;
  late AudioCache audio;
  late IssuerInProcess issuer;

  /// What the panel asked the phone to open, and what the phone hands back.
  late List<Uri> opened;
  late StreamController<Uri> links;

  setUpAll(() {
    loadBundledFonts();
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  setUp(() async {
    db = await testCorpus();
    await db.delete('ayah_understood');
    await db.execute('DROP TABLE IF EXISTS auth_tokens');
    await db.execute('DROP TABLE IF EXISTS local_reader');
    audio = await emptyCache();
    issuer = IssuerInProcess();
    opened = [];
    links = StreamController<Uri>.broadcast();
  });

  tearDown(() => links.close());

  Account theAccount() => Account(
    db,
    http: issuer.client,
    issuer: IssuerInProcess.issuer,
    clientId: 'wird-test',
    redirect: authRedirect,
  );

  /// The browser's half, which is one redirect: the issuer sends the reader to
  /// the address the app asked to be sent back to, carrying the code and the
  /// state it was given.
  Uri whereItSendsThemBack(Uri authorization) {
    final asked = authorization.queryParameters;
    return Uri.parse(
      '${asked['redirect_uri']}?code=a-code&state=${asked['state']}',
    );
  }

  Future<void> theReaderSignsIn() async {
    final account = theAccount();
    final begun = await account.begin();
    await account.complete(begun, whereItSendsThemBack(begun.url));
  }

  /// The panel with the three things the phone supplies stood in for: the
  /// issuer, a browser that records what it was asked to open, and the links
  /// the OS would deliver when the reader comes back.
  Future<void> openThePanel(WidgetTester tester) async {
    await pumpPhone(
      tester,
      await wirdAround(
        db,
        Scaffold(
          body: AccountPanel(
            db: db,
            account: theAccount(),
            open: (url) async {
              opened.add(url);
              return true;
            },
            redirects: links.stream,
          ),
        ),
      ),
    );
  }

  Future<void> theReaderTapsSignIn(WidgetTester tester) async {
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
  }

  Future<void> thePhoneIsHanded(WidgetTester tester, Uri link) async {
    links.add(link);
    await tester.pumpAndSettle();
  }

  Future<void> openSettings(WidgetTester tester) async {
    await pumpPhone(
      tester,
      await wirdAround(db, const SettingsScreen(), cache: audio),
    );
    await tester.scrollUntilVisible(find.text('ACCOUNT'), 200);
    await tester.pumpAndSettle();
  }

  // The rule the whole design rests on: the reading loop is local and works
  // with the radio off, so an account can never stand between the reader and
  // the Qur'an. A sign-in that greets them at launch, or a screen that waits
  // on one, is the failure.
  testWidgets('the app asks who the reader is before it will open the Qur\'an',
      (tester) async {
    await pumpPhone(tester, await wholeApp(db, cache: audio));

    expect(find.byType(DashboardScreen), findsOneWidget);
    expect(find.text('Sign in'), findsNothing);
    expect(find.textContaining('Signed in'), findsNothing);
  });

  testWidgets('a reader who has not signed in is offered no way to', (
    tester,
  ) async {
    await openSettings(tester);

    expect(find.text('Sign in'), findsOneWidget);
    expect(
      find.textContaining('Wird works signed out'),
      findsOneWidget,
      reason: 'the panel has to say that not signing in is a whole answer',
    );
  });

  // Signing out and forgetting a month of reading are two different acts, and
  // the reader asked for one of them. This is the button that could be wired
  // to both.
  testWidgets("signing out takes the reader's progress with it", (
    tester,
  ) async {
    // Outside the frames: what the panel does for itself below is driven by
    // pumping, and this test is standing in for the reader before it opens.
    await tester.runAsync(theReaderSignsIn);
    await markSetUnderstood(db, newOpId(), [96001, 96002]);

    await openSettings(tester);
    expect(find.text('Signed in as reader@bnei.dev'), findsOneWidget);
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();

    expect(find.text('Sign in'), findsOneWidget);
    expect(await db.query('ayah_understood'), hasLength(2));
    expect(
      await db.query('outbox'),
      hasLength(1),
      reason: 'the queued write waits for the next sign-in, it is not dropped',
    );
  });

  // What the reader walking the app actually hit: they tapped Sign in, the
  // address went to the clipboard, and it was theirs to paste into a browser
  // and paste the answer back from. It also pins the redirect the app sends,
  // which is the string the issuer refuses a sign-in over when it is not the
  // one registered on the client.
  testWidgets('tapping sign in opens nothing and leaves the reader pasting '
      'addresses by hand', (tester) async {
    await openThePanel(tester);

    await theReaderTapsSignIn(tester);

    expect(opened, hasLength(1));
    final asked = opened.single.queryParameters;
    expect(opened.single.path, '/application/o/authorize/');
    expect(asked['redirect_uri'], authRedirect);
    expect(asked['code_challenge_method'], 'S256');
    expect(find.text('Cancel'), findsOneWidget);
  });

  // The other half of the same failure. The browser has the code and hands it
  // back on the scheme in the manifest; a phone that does nothing with that
  // link leaves the reader on a page that cannot go anywhere.
  testWidgets('the issuer sends the reader back and the phone does nothing '
      'with it', (tester) async {
    await openThePanel(tester);
    await theReaderTapsSignIn(tester);

    await thePhoneIsHanded(tester, whereItSendsThemBack(opened.single));

    expect(find.text('Signed in as reader@bnei.dev'), findsOneWidget);
    expect(
      issuer.exchanges.single['redirect_uri'],
      authRedirect,
      reason: 'the code is traded against the same redirect it was asked for',
    );
  });

  // A reader opens the browser, thinks better of it, and comes back by the
  // launcher. The panel used to have nothing on it but a half-finished
  // sign-in, and no way back to the button that starts one.
  testWidgets('a reader who never comes back from the browser is left with a '
      'panel that can only wait', (tester) async {
    await openThePanel(tester);
    await theReaderTapsSignIn(tester);
    final back = whereItSendsThemBack(opened.single);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await thePhoneIsHanded(tester, back);

    expect(find.text('Sign in'), findsOneWidget);
    expect(
      find.textContaining('Signed in as'),
      findsNothing,
      reason: 'the abandoned sign-in was dropped, verifier and state with it',
    );
    expect(issuer.exchanges, isEmpty);
  });

  // The door a deep link opens. Anything on the phone can send this app a link
  // on its scheme, and a panel that trades whatever code arrives signs the
  // device into an account the reader never asked for.
  testWidgets('a link from anywhere signs this phone into somebody else\'s '
      'account', (tester) async {
    await openThePanel(tester);
    await theReaderTapsSignIn(tester);

    await thePhoneIsHanded(
      tester,
      Uri.parse('$authRedirect?code=somebody-elses&state=not-ours'),
    );

    expect(issuer.exchanges, isEmpty);
    expect(await db.query('auth_tokens'), isEmpty);
    expect(find.textContaining('Signed in as'), findsNothing);
    expect(find.text('Sign in'), findsOneWidget);
  });
}
