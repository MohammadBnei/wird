import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:sqflite/sqflite.dart';

import 'auth.dart';
import 'sync.dart';

/// The server this build carries the queue to. The define is how a debug run
/// is pointed at a laptop instead.
///
/// The default is a guess that has not come true yet. `wird.bnei.dev` is the
/// host in the client's registered redirect and it resolves, but on 2026-09-24
/// every path under it — `/v1/sync`, `/v1/changes`, `/healthz` — answered Go's
/// bare `404 page not found`, so the API is not behind it today. It stays the
/// default because it is the name the app was given, and it is a define so
/// that a build can say otherwise without a release; whoever deploys the API
/// settles it.
const syncOrigin = String.fromEnvironment(
  'WIRD_ORIGIN',
  defaultValue: 'https://wird.bnei.dev',
);

/// Who asks for a flush.
///
/// [syncNow] was built, certified and called by nothing: no understood aya, no
/// kept note, no prayer and no report had ever left a phone, because a queue
/// only moves when something calls it. This is the something.
///
/// The moment is the app coming back to the foreground, and once at launch —
/// which is the moment a phone that has spent the day in a pocket has a
/// signal, a reader, and no prayer running. It is not "whenever a write is
/// queued": that is a radio wake per aya.
///
/// It stays on the right side of the in-prayer rule without having to know
/// what screen is up. A flush writes to sqlite and returns; 1b reads nothing,
/// awaits nothing and cannot be drawn over, so even the reader who leaves the
/// app mid-prayer and comes back sees no sign of one.
class Flusher with WidgetsBindingObserver {
  Flusher(this.db, this.api, {this.gap = const Duration(minutes: 2)});

  final Database db;
  final SyncApi api;

  /// The floor between two flushes. A phone is unlocked dozens of times an
  /// hour and each flush is a radio wake, a push and a pull.
  ///
  /// ponytail: a fixed floor rather than a backoff. Its ceiling is the reader
  /// who unlocks, writes nothing and unlocks again: they pay one empty round
  /// trip every two minutes. Make it adaptive when a battery measurement asks
  /// for it.
  final Duration gap;

  Future<SyncReport>? _running;
  DateTime? _last;

  /// Watches for the foreground, and flushes once now: a launch is a return
  /// too, and no [AppLifecycleState.resumed] is delivered for it.
  void start() {
    WidgetsBinding.instance.addObserver(this);
    _inTheBackground();
  }

  void stop() => WidgetsBinding.instance.removeObserver(this);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _inTheBackground();
  }

  /// A flush nobody is waiting for, which is every flush this class starts. A
  /// throw must not become an unhandled error and take the app down over a
  /// queue that a throw leaves exactly as it was.
  void _inTheBackground() => unawaited(flush().catchError((Object _) => null));

  /// One flush at a time, and not more often than [gap].
  ///
  /// [syncNow] guards nothing across calls — its "one attempt per op" set
  /// lives inside a single call — so two flushes over one outbox would send
  /// the same op twice in one round and spend two of its ten attempts on one
  /// answer. A caller arriving mid-flush joins the flush already running.
  ///
  /// Null when it was too soon after the last one.
  Future<SyncReport?> flush() {
    final running = _running;
    if (running != null) return running;
    final last = _last;
    if (last != null && DateTime.now().difference(last) < gap) {
      return Future.value(null);
    }
    _last = DateTime.now();
    final run = syncNow(db, api);
    _running = run;
    return run.whenComplete(() => _running = null);
  }
}

/// The queue, signed as whoever is signed in on this device.
///
/// The token attaches here, in the interceptor, and nowhere else: the screens
/// and the repositories above this line do not know one exists. A device with
/// nobody signed in flushes unsigned, is answered 401, and keeps its queue —
/// which is the same ending as a flight with the radio off.
Flusher flusherFor(Database db) => Flusher(
  db,
  SyncApi(
    Dio(BaseOptions(baseUrl: syncOrigin))
      ..interceptors.add(AuthHeader(Account(db))),
  ),
);

/// Holds one [Flusher] for as long as the app is up, which is the only thing
/// the widget tree owes it. It sits here rather than in the app layer because
/// when the queue moves is this file's business, not the navigator's.
class Flushing extends StatefulWidget {
  const Flushing({super.key, required this.flusher, required this.child});

  /// None in a test, which has no server to reach.
  final Flusher? flusher;

  final Widget child;

  @override
  State<Flushing> createState() => _FlushingState();
}

class _FlushingState extends State<Flushing> {
  @override
  void initState() {
    super.initState();
    widget.flusher?.start();
  }

  @override
  void dispose() {
    widget.flusher?.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
