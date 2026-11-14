// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

/// Tracks whether the current server answers, which is what offline means in
/// this app (docs/plan/05-phase4-offline.md 4.8).
library;

import 'dart:async';

import 'package:dio/dio.dart';

/// Whether the current server answers.
enum ServerReach {
  /// Not checked yet (start-up, account switch). Treated as online.
  unknown,
  online,
  offline,
}

/// Answers whether the server at a base URL responds to `/ping`.
typedef Pinger = Future<bool> Function(Uri baseUrl, Map<String, String> headers);

/// Online means the server answers `/ping` within [timeout], not just "the
/// phone has a network": Tailscale and LAN-only servers make this matter.
/// `/ping` needs no token (docs/abs-api.md section 3); only the account's
/// custom reverse-proxy headers are sent.
Future<bool> pingServer(
  Uri baseUrl,
  Map<String, String> headers, {
  Duration timeout = const Duration(seconds: 3),
}) async {
  final dio = Dio(BaseOptions(connectTimeout: timeout, receiveTimeout: timeout, sendTimeout: timeout));
  try {
    final response = await dio
        .getUri<Object?>(
          baseUrl.replace(path: '${baseUrl.path}/ping'),
          options: Options(headers: headers),
        )
        .timeout(timeout);
    return response.statusCode == 200;
  } on Object {
    return false;
  } finally {
    dio.close(force: true);
  }
}

/// The reachability of one server at a time (the current account's).
///
/// Re-checks when told to ([check]: connectivity change, app foreground),
/// after a request failed ([reportFailure]), and every [offlineRecheck]
/// while the server does not answer.
class Reachability {
  Reachability({required this._ping, this.offlineRecheck = const Duration(seconds: 60)});

  final Pinger _ping;
  final Duration offlineRecheck;
  final _changes = StreamController<ServerReach>.broadcast();

  Uri? _baseUrl;
  Map<String, String> _headers = const {};
  ServerReach _value = ServerReach.unknown;
  Timer? _recheck;
  Future<ServerReach>? _inflight;
  int _generation = 0;

  ServerReach get value => _value;
  Stream<ServerReach> get changes => _changes.stream;
  Uri? get server => _baseUrl;

  /// False only when the server is known not to answer.
  bool get isOnline => _value != ServerReach.offline;

  /// Switches to another server (or none) and checks it.
  Future<ServerReach> setServer(Uri? baseUrl, {Map<String, String> headers = const {}}) {
    _generation++;
    _baseUrl = baseUrl;
    _headers = headers;
    _inflight = null;
    _recheck?.cancel();
    _set(ServerReach.unknown);
    if (baseUrl == null) return Future.value(ServerReach.unknown);
    return check();
  }

  /// Pings now. Concurrent callers share one ping.
  Future<ServerReach> check() {
    final base = _baseUrl;
    if (base == null) return Future.value(_value);
    final generation = _generation;
    return _inflight ??= () async {
      final ok = await _ping(base, _headers);
      if (generation != _generation) return _value;
      _inflight = null;
      _set(ok ? ServerReach.online : ServerReach.offline);
      _recheck?.cancel();
      if (!ok) _recheck = Timer(offlineRecheck, () => unawaited(check()));
      return _value;
    }();
  }

  /// A request to the current server failed without an answer: check soon.
  void reportFailure() => unawaited(check());

  /// A request got an answer: the server is reachable.
  void reportSuccess() {
    if (_value == ServerReach.online) return;
    _recheck?.cancel();
    _set(ServerReach.online);
  }

  void _set(ServerReach value) {
    if (value == _value) return;
    _value = value;
    if (!_changes.isClosed) _changes.add(value);
  }

  void dispose() {
    _recheck?.cancel();
    unawaited(_changes.close());
  }
}
